#pragma once
#include <cstdio>
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <sys/stat.h>
// Bounded classic-TIFF preflight for Sony ARW. Not a pixel checksum or decoder.
// Validate IFD fields and every declared strip/tile extent before admitting a RAW.
inline bool validateARW(const char *path, std::string &error) {
    FILE *f=fopen(path,"rb");if(!f){error="cannot open RAW";return false;}
    struct Close{FILE *f;~Close(){fclose(f);}} close{f};
    struct stat st{};if(fstat(fileno(f),&st)||st.st_size<8){error="RAW header truncated";return false;}
    uint64_t size=uint64_t(st.st_size);bool little=true;
    auto read=[&](uint64_t off,void *p,size_t n){return off<=size && n<=size-off && fseeko(f,off,SEEK_SET)==0 && fread(p,1,n,f)==n;};
    auto u16=[&](const uint8_t *p)->uint16_t{return little ? uint16_t(p[0])|uint16_t(p[1])<<8:uint16_t(p[1])|uint16_t(p[0])<<8;};
    auto u32=[&](const uint8_t *p)->uint32_t{return little ? uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24:uint32_t(p[3])|uint32_t(p[2])<<8|uint32_t(p[1])<<16|uint32_t(p[0])<<24;};
    uint8_t h[8];if(!read(0,h,8)){error="header read failed";return false;}
    if(h[0]=='I'&&h[1]=='I')little=true;else if(h[0]=='M'&&h[1]=='M')little=false;else {error="not TIFF/ARW";return false;}
    if(u16(h+2)!=42){error="unsupported TIFF variant";return false;}
    std::vector<uint32_t> todo{u32(h+4)};std::set<uint32_t> seen;bool payload=false; uint64_t parsedValues=0;
    const unsigned widths[]={0,1,1,2,4,8,1,1,2,4,8,4,8,4};
    while(!todo.empty()) {
        uint32_t off=todo.back();todo.pop_back();if(!off)continue;
        if(!seen.insert(off).second){error="cyclic IFD";return false;}
        if(seen.size()>64){error="too many IFDs";return false;}
        uint8_t countData[2];if(!read(off,countData,2)){error="IFD truncated";return false;}
        unsigned count=u16(countData);if(count>4096){error="IFD too large";return false;}
        std::vector<uint8_t> entries(size_t(count)*12+4);
        if(!read(uint64_t(off)+2,entries.data(),entries.size())){error="IFD entries truncated";return false;}
        std::vector<uint32_t> stripOffsets,stripBytes,tileOffsets,tileBytes;
        for(unsigned i=0;i<count;i++) {
            const auto *e=entries.data()+i*12;unsigned tag=u16(e),type=u16(e+2);uint32_t n=u32(e+4);
            if(type==0||type>=sizeof(widths)/sizeof(widths[0])){error="unsupported TIFF field type";return false;}
            uint64_t bytes=uint64_t(n)*widths[type];uint32_t fieldOff=u32(e+8);
            if(bytes>4 && (fieldOff>size || bytes>size-fieldOff)){error="declared TIFF field extends beyond EOF";return false;}
            bool relevant=tag==273||tag==279||tag==324||tag==325||tag==330||tag==34665||tag==34853;
            if(!relevant)continue;
            parsedValues += n;
            if(parsedValues>262144 || n>65536 || (type!=3&&type!=4&&type!=13)){error="unsupported image extent field";return false;}
            std::vector<uint8_t> values(bytes);if(bytes<=4)std::copy(e+8,e+8+bytes,values.data());else if(!read(fieldOff,values.data(),bytes)){error="extent table unreadable";return false;}
            std::vector<uint32_t> v;for(uint32_t j=0;j<n;j++)v.push_back(type==3?u16(values.data()+j*2):u32(values.data()+j*4));
            if(tag==273)stripOffsets=v;else if(tag==279)stripBytes=v;else if(tag==324)tileOffsets=v;else if(tag==325)tileBytes=v;else { if(todo.size()+v.size()>64){error="too many child IFDs";return false;} todo.insert(todo.end(),v.begin(),v.end()); }
        }
        auto extents=[&](const std::vector<uint32_t>& offsets,const std::vector<uint32_t>& lengths){
            if(offsets.empty()&&lengths.empty())return true;
            if(offsets.empty()||offsets.size()!=lengths.size())return false;
            for(size_t j=0;j<offsets.size();j++)if(offsets[j]>size||uint64_t(lengths[j])>size-offsets[j])return false;
            payload=payload || std::any_of(lengths.begin(),lengths.end(),[](uint32_t len){return len>0;});return true;
        };
        if(!extents(stripOffsets,stripBytes)||!extents(tileOffsets,tileBytes)){error="RAW strip/tile data truncated";return false;}
        todo.push_back(u32(entries.data()+count*12));
    }
    if(!payload){error="no declared image payload";return false;}
    return true;
}
