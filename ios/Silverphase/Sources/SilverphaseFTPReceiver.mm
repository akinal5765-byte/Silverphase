#if DEBUG
#import "SilverphaseFTPReceiver.h"
#import <CommonCrypto/CommonDigest.h>
#include <algorithm>
#include "FTPARRawIntegrity.hpp"
#include <net/if.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <unistd.h>
#include <atomic>
#include <string>
#include <poll.h>
#include <fcntl.h>
#include <mutex>
#include <chrono>
#include <cerrno>
#include <memory>
#include <vector>

static int listener(uint16_t port, in_addr address) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if(fd<0)return -1;
    int one = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_len=sizeof(a); a.sin_addr=address;
    if (bind(fd, (sockaddr *)&a, sizeof(a)) || listen(fd, 4)) { close(fd); return -1; }
    return fd;
}
static void timeout(int fd) {
    timeval t{20,0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof(t));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &t, sizeof(t));
    int one=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
}
static bool reply(int fd, NSString *s) {
    NSData *d=[[s stringByAppendingString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding];
    const char *p=(const char *)d.bytes; size_t n=d.length;
    while(n) { ssize_t k=send(fd,p,n,0); if(k<=0)return false; p+=k;n-=k; } return true;
}
// Bound every read wait so stopping a generation never depends on a camera
// sending another byte. Keep authenticated sessions idle for 15 minutes.
static std::string line(int fd, const std::atomic<bool> &running,
                        const std::atomic<unsigned> &current, unsigned generation,
                        int idleSeconds) {
    std::string s;
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(idleSeconds);
    while(s.size()<1024 && running && current==generation) {
        if(std::chrono::steady_clock::now()>=deadline){errno=ETIMEDOUT;return {};}
        pollfd p{fd,POLLIN,0};int ready=poll(&p,1,250);
        if(ready<0){if(errno==EINTR)continue;return {};}
        if(ready==0)continue;
        char c;ssize_t n=recv(fd,&c,1,0);
        if(n<=0){if(n<0 && errno==EINTR)continue;return {};}
        if(c=='\n')return s;
        if(c!='\r')s+=c;
    }
    errno=running && current==generation?EMSGSIZE:ECANCELED;
    return {};
}
// Each control session owns its passive/data sockets. A stalled camera session
// must not block accepting a replacement connection or close its sockets.
struct FTPSockets {
    std::atomic<int> control, data{-1}, passive{-1};
    std::mutex mutex;
    explicit FTPSockets(int fd):control(fd){}
    void closeFD(std::atomic<int> &slot){std::lock_guard<std::mutex> guard(mutex);int fd=slot.exchange(-1);if(fd>=0)close(fd);}
    void setData(int fd){std::lock_guard<std::mutex> guard(mutex);data=fd;}
    void setPassive(int fd){std::lock_guard<std::mutex> guard(mutex);passive=fd;}
    void shutdownAll(){std::lock_guard<std::mutex> guard(mutex);for(int fd:{control.load(),data.load(),passive.load()})if(fd>=0)shutdown(fd,SHUT_RDWR);}
    ~FTPSockets(){closeFD(passive);closeFD(data);closeFD(control);}
};
static bool privateIPv4(in_addr address) {
    const uint32_t value=ntohl(address.s_addr);
    return (value>>24)==10 || (value>>20)==0xac1 || (value>>16)==0xc0a8;
}
static in_addr wifiAddress() {
#if SILVERPHASE_FTP_LOOPBACK_TEST
    return {htonl(INADDR_LOOPBACK)};
#else
    ifaddrs *list=nullptr; in_addr result{};
    if(getifaddrs(&list)==0) {
        for(auto p=list;p;p=p->ifa_next) {
            if(!p->ifa_addr || p->ifa_addr->sa_family!=AF_INET || !(p->ifa_flags&IFF_UP) ||
               strcmp(p->ifa_name,"en0")!=0)continue;
            auto address=reinterpret_cast<const sockaddr_in *>(p->ifa_addr)->sin_addr;
            if(privateIPv4(address)){result=address;break;}
        }
        freeifaddrs(list);
    }
    return result;
#endif
}
static constexpr uint16_t ftpPort=2121;
static std::mutex uploadMutex;
static constexpr uint64_t maxFile=256ull*1024*1024;
static bool safeARWName(NSString *arg) {
    if(arg.length<5 || arg.length>120 || [arg hasPrefix:@"."] ||
       ![arg.pathExtension.lowercaseString isEqualToString:@"arw"])return false;
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:
                          @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.- "] invertedSet];
    return [arg rangeOfCharacterFromSet:bad].location==NSNotFound;
}
@implementation SilverphaseFTPReceiver {
    NSURL *_directory;
    NSString *_password;
    NSString *_film;
    NSString *_publicationError;
    NSString *_endpoint;
    NSNetService *_bonjourService;
    std::atomic<bool> _running;
    std::atomic<unsigned> _generation;
    dispatch_queue_t _serverQueue;
    std::atomic<int> _listenFD;
    std::mutex _listenerMutex;
    std::mutex _clientsMutex;
    std::vector<std::shared_ptr<FTPSockets>> _clients;
}
- (instancetype)initWithDirectory:(NSURL *)directory film:(NSString *)film {
    if((self=[super init])) {
        _directory=directory; _film=[film copy];
        // A fresh credential for each receiver, never stored in preferences or printed.
        _password=[[[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:12] lowercaseString];
        _serverQueue=dispatch_queue_create("com.silverphase.editor.tether.ftp",DISPATCH_QUEUE_SERIAL);
        _running=false; _generation=0; _listenFD=-1;
    }
    return self;
}
- (NSString *)password { return _password; }
- (NSString *)publicationError { return _publicationError; }
- (NSString *)start {
    if(_running.exchange(true)) return _endpoint;
    unsigned generation=++_generation;
    {
        // Only clean the inbox if no previous generation is finishing an upload.
        std::unique_lock<std::mutex> upload(uploadMutex,std::try_to_lock);
        if(upload){
            NSFileManager *fm=NSFileManager.defaultManager;
            NSArray<NSURL *> *items=[fm contentsOfDirectoryAtURL:_directory
                includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil];
            const NSTimeInterval receiptWindow=7*24*60*60;
            for(NSURL *item in items) {
                if([item.pathExtension isEqualToString:@"part"] && [item.lastPathComponent hasPrefix:@"upload-"])
                    [fm removeItemAtURL:item error:nil];
                if([item.pathExtension isEqualToString:@"json"] && ![fm fileExistsAtPath:item.URLByDeletingPathExtension.path])
                    [fm removeItemAtURL:item error:nil];
                if([item.pathExtension isEqualToString:@"done"]) {
                    NSURL *source=item.URLByDeletingPathExtension;
                    // A durable receipt means this staged copy was already imported.
                    if([fm fileExistsAtPath:source.path])[fm removeItemAtURL:source error:nil];
                    NSDate *date=nil;
                    [item getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
                    if(date && date.timeIntervalSinceNow < -receiptWindow && ![fm fileExistsAtPath:source.path])
                        [fm removeItemAtURL:item error:nil];
                }
            }
        }
    }
    const in_addr address=wifiAddress();
    if(!address.s_addr){_running=false;return nil;}
    int fd=listener(ftpPort,address); _listenFD=fd;
    if(fd<0){_running=false;return nil;}
    if(fcntl(fd,F_SETFL,fcntl(fd,F_GETFL,0)|O_NONBLOCK)<0){
        close(fd);_listenFD=-1;_running=false;return nil;
    }
#ifndef SILVERPHASE_FTP_LOOPBACK_TEST
    // Publishing a Bonjour service requests iOS local network consent.
    _bonjourService=[[NSNetService alloc] initWithDomain:@"local." type:@"_ftp._tcp." name:@"Silverphase Tether" port:ftpPort];
    _bonjourService.delegate=self;
    [_bonjourService publish];
#endif
    char ip[INET_ADDRSTRLEN]{};
    inet_ntop(AF_INET,&address,ip,sizeof(ip));
    _endpoint=[NSString stringWithFormat:@"%s",ip];
    dispatch_async(_serverQueue, ^{
        while(self->_running && self->_generation==generation) {
            pollfd pending{fd,POLLIN,0};int ready=poll(&pending,1,250);
            if(ready<0 && errno==EINTR)continue;
            if(!self->_running || self->_generation!=generation)break;
            if(ready==0)continue;
            int c=-1; sockaddr_in peer{}; socklen_t len=sizeof(peer);
            {
                // stop() cannot close/reuse this descriptor between the generation
                // check and accept(). The listener itself is nonblocking.
                std::lock_guard<std::mutex> guard(self->_listenerMutex);
                if(!self->_running || self->_generation!=generation)break;
                if(ready>0 && (pending.revents&POLLIN))c=accept(fd,(sockaddr *)&peer,&len);
            }
            if(c<0){
                if(errno==EAGAIN || errno==EWOULDBLOCK || errno==EINTR)continue;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if(self->_generation==generation){self->_publicationError=@"listener";[self stop];}
                });
                self->_running=false;break;
            }
#if !SILVERPHASE_FTP_LOOPBACK_TEST
            if(!privateIPv4(peer.sin_addr)){close(c);continue;}
#endif
            fcntl(c,F_SETFL,fcntl(c,F_GETFL,0)&~O_NONBLOCK);
            timeout(c);
            auto sockets=std::make_shared<FTPSockets>(c);
            {
                std::lock_guard<std::mutex> guard(self->_clientsMutex);
                if(!self->_running || self->_generation!=generation){continue;}
                if(self->_clients.size()>=4)continue;
                self->_clients.push_back(sockets);
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                @autoreleasepool {
                    if(self->_running && self->_generation==generation)
                        [self client:sockets generation:generation];
                    sockets->closeFD(sockets->control);
                    std::lock_guard<std::mutex> guard(self->_clientsMutex);
                    std::erase(self->_clients,sockets);
                }
            });
        }
    });
    return _endpoint;
}
- (void)client:(std::shared_ptr<FTPSockets>)sockets generation:(unsigned)generation {
    int c=sockets->control.load();
    if(!reply(c,@"220 Silverphase camera upload"))return;
    BOOL user=NO,auth=NO; unsigned failures=0;
    while(_running && _generation==generation) {
        auto raw=line(c,_running,_generation,generation,auth?900:20);
        if(raw.empty() || raw.find(char(0))!=std::string::npos)break;
        NSString *s=[NSString stringWithUTF8String:raw.c_str()]; if(!s)break;
        NSRange space=[s rangeOfString:@" "]; NSString *cmd=[[s substringToIndex:space.location==NSNotFound?s.length:space.location] uppercaseString];
        NSString *arg=space.location==NSNotFound?@"":[s substringFromIndex:space.location+1];
        if([cmd isEqual:@"USER"]) {
            user=[arg isEqual:@"silverphase"]; auth=NO;
            sockets->closeFD(sockets->passive); reply(c,@"331 Password required");
        }
        else if([cmd isEqual:@"PASS"]) {
            auth=user && [arg isEqual:_password]; reply(c,auth?@"230 Login successful":@"530 Login incorrect");
            if(!auth && ++failures>=3)break;
        }
        else if([cmd isEqual:@"QUIT"]) {reply(c,@"221 Bye");break;}
        else if([cmd isEqual:@"SYST"])reply(c,@"215 UNIX Type: L8");
        else if([cmd isEqual:@"FEAT"])reply(c,@"211-Features\r\n EPSV\r\n UTF8\r\n211 End");
        else if(!auth)reply(c,@"530 Login first");
        else if([cmd isEqual:@"PWD"])reply(c,@"257 \"/\"");
        else if([cmd isEqual:@"TYPE"])reply(c,[arg.uppercaseString isEqual:@"I"]?@"200 Binary":@"504 Use binary");
        else if([cmd isEqual:@"NOOP"] || ([cmd isEqual:@"OPTS"] && [arg.uppercaseString isEqual:@"UTF8 ON"]))reply(c,@"200 OK");
        else if([cmd isEqual:@"CWD"] && [@[@"/",@"."] containsObject:arg])reply(c,@"250 OK");
        else if([cmd isEqual:@"PASV"] || [cmd isEqual:@"EPSV"]) {
            sockets->closeFD(sockets->passive);
            sockaddr_in local{}; socklen_t localLen=sizeof(local);
            int p=getsockname(c,(sockaddr *)&local,&localLen)==0 ? listener(0,local.sin_addr) : -1;
            if(p>=0 && fcntl(p,F_SETFL,fcntl(p,F_GETFL,0)|O_NONBLOCK)<0){close(p);p=-1;}
            sockets->setPassive(p);
            if(p<0){reply(c,@"425 Cannot open passive socket");continue;}
            sockaddr_in a{}; socklen_t len=sizeof(a); getsockname(p,(sockaddr *)&a,&len); unsigned port=ntohs(a.sin_port);
            if([cmd isEqual:@"EPSV"])reply(c,[NSString stringWithFormat:@"229 Entering Extended Passive Mode (|||%u|)",port]);
            else { getsockname(c,(sockaddr *)&a,&len); uint32_t ip=ntohl(a.sin_addr.s_addr);
                reply(c,[NSString stringWithFormat:@"227 Entering Passive Mode (%u,%u,%u,%u,%u,%u)",ip>>24,(ip>>16)&255,(ip>>8)&255,ip&255,port/256,port%256]); }
        }
        else if([cmd isEqual:@"STOR"]) {
            if(sockets->passive<0){reply(c,@"425 Use PASV or EPSV");continue;}
            if(!safeARWName(arg)) {reply(c,@"553 Only plain ARW filenames accepted");sockets->closeFD(sockets->passive);continue;}
            std::unique_lock<std::mutex> upload(uploadMutex,std::try_to_lock);
            if(!upload){reply(c,@"450 Another upload is in progress");sockets->closeFD(sockets->passive);continue;}
            NSFileManager *fm=NSFileManager.defaultManager;
            NSDictionary *disk=[fm attributesOfFileSystemForPath:_directory.path error:nil];
            NSArray<NSURL *> *items=[fm contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:@[NSURLFileSizeKey] options:0 error:nil];
            uint64_t staged=0;
            for(NSURL *item in items) {
                if(![item.pathExtension isEqualToString:@"ARW"])continue;
                NSNumber *bytes=nil;
                [item getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
                staged+=bytes.unsignedLongLongValue;
            }
            if(!items || [disk[NSFileSystemFreeSize] unsignedLongLongValue]<2*maxFile ||
               staged+maxFile>8*maxFile || items.count>=4096){
                reply(c,@"452 Receiver inbox or storage full");sockets->closeFD(sockets->passive);continue;
            }
            reply(c,@"150 Opening data connection");
            int passive=sockets->passive.load();bool dataReady=false;
            auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(20);
            while(_running && _generation==generation && std::chrono::steady_clock::now()<deadline){
                pollfd pending{passive,POLLIN,0};int ready=poll(&pending,1,250);
                if(ready<0 && errno==EINTR)continue;
                if(ready<0 || (ready>0 && !(pending.revents&POLLIN)))break;
                if(ready>0){dataReady=true;break;}
            }
            if(!dataReady || !_running || _generation!=generation){reply(c,@"425 Data timeout or receiver stopped");sockets->closeFD(sockets->passive);continue;}
            sockaddr_in peer{}; socklen_t len=sizeof(peer); int d=accept(sockets->passive,(sockaddr *)&peer,&len); sockets->closeFD(sockets->passive);
            sockaddr_in control{}; getpeername(c,(sockaddr *)&control,&len);
            if(d<0 || peer.sin_addr.s_addr!=control.sin_addr.s_addr) {if(d>=0)close(d);reply(c,@"425 Invalid data peer");continue;}
            // Darwin may propagate O_NONBLOCK from the listening descriptor.
            // The accepted stream uses bounded blocking reads with SO_RCVTIMEO.
            int flags=fcntl(d,F_GETFL,0);
            if(flags<0 || fcntl(d,F_SETFL,flags&~O_NONBLOCK)<0){
                close(d);reply(c,@"425 Cannot configure data connection");continue;
            }
            sockets->setData(d); timeout(d);
            NSURL *part=[_directory URLByAppendingPathComponent:[NSString stringWithFormat:@"upload-%@.part",NSUUID.UUID.UUIDString]];
            CC_SHA256_CTX hash;CC_SHA256_Init(&hash);
            FILE *file=fopen(part.fileSystemRepresentation,"wb"); bool ok=file!=nullptr; size_t total=0; char buffer[65536]; ssize_t n=0;
            auto uploadDeadline=std::chrono::steady_clock::now()+std::chrono::minutes(3);
            while(ok && _running && _generation==generation) {
                n=recv(d,buffer,sizeof(buffer),0);
                if(n<0 && errno==EINTR)continue;
                if(n<=0)break;
                total+=n;
                if(total>maxFile || std::chrono::steady_clock::now()>uploadDeadline ||
                   fwrite(buffer,1,n,file)!=(size_t)n){ok=false;break;}
                CC_SHA256_Update(&hash,buffer,(CC_LONG)n);
            }
            if(n<0 || !_running || _generation!=generation || total==0)ok=false;
            if(ok && (fflush(file)!=0 || fsync(fileno(file))!=0))ok=false;
            if(file && fclose(file)!=0)ok=false;
            sockets->closeFD(sockets->data);
            std::string integrityError;
            if(ok && !validateARW(part.fileSystemRepresentation,integrityError)) {
                unlink(part.fileSystemRepresentation);reply(c,@"550 RAW structure incomplete or unsupported");
                continue;
            }
            if(!ok){unlink(part.fileSystemRepresentation);reply(c,@"451 Transfer incomplete or inbox write failed");continue;}
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(digest,&hash);
            NSMutableString *key=[NSMutableString new];for(unsigned char b:digest)[key appendFormat:@"%02x",b];
            NSURL *final=[_directory URLByAppendingPathComponent:[key stringByAppendingString:@".ARW"]];
            NSURL *metadata=[final URLByAppendingPathExtension:@"json"];
            NSURL *receipt=[final URLByAppendingPathExtension:@"done"];
            if([fm fileExistsAtPath:final.path] || [fm fileExistsAtPath:receipt.path]) {
                unlink(part.fileSystemRepresentation); reply(c,@"226 Already received identical RAW");continue;
            }
            NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"name": arg, @"film": _film} options:0 error:nil];
            if(!_running || _generation!=generation || !data || ![data writeToURL:metadata options:NSDataWritingAtomic error:nil] ||
               rename(part.fileSystemRepresentation,final.fileSystemRepresentation)!=0){
                unlink(part.fileSystemRepresentation);[fm removeItemAtURL:metadata error:nil];reply(c,@"451 Could not commit to inbox");continue;
            }
            reply(c,@"226 Transfer complete");

        }
        else reply(c,@"502 Command not implemented");
    }
    sockets->closeFD(sockets->passive);
}
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    if(sender==_bonjourService){_publicationError=@"local-network";[self stop];}
}
- (void)stop {
    [_bonjourService stop];_bonjourService.delegate=nil;_bonjourService=nil;
    _running=false;++_generation;
    // Session workers own their descriptors; shutdown cancels existing I/O.
    {
        std::lock_guard<std::mutex> guard(_clientsMutex);
        for(auto &sockets:_clients)sockets->shutdownAll();
    }
    {
        std::lock_guard<std::mutex> guard(_listenerMutex);
        int fd=_listenFD.exchange(-1);if(fd>=0){shutdown(fd,SHUT_RDWR);close(fd);}
    }
}
@end

#endif
