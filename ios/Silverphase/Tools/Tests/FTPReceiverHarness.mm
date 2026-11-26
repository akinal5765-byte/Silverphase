#import "../../Sources/SilverphaseFTPReceiver.h"
#include <cstdio>

// Local test only. The production receiver never prints credentials or binds loopback.
int main(int argc, const char **argv) {
    @autoreleasepool {
        if(argc != 2)return 64;
        NSURL *folder=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        SilverphaseFTPReceiver *receiver=[[SilverphaseFTPReceiver alloc] initWithDirectory:folder film:@"QA-film"];
        NSString *host=[receiver start];
        if(![host isEqualToString:@"127.0.0.1"])return 1;
        printf("%s\n",receiver.password.UTF8String); fflush(stdout);
        // Stop on a byte from the parent, leaving any in-flight partial upload uncommitted.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
            (void)getchar();
            dispatch_async(dispatch_get_main_queue(), ^{
                [receiver stop];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500*NSEC_PER_MSEC),
                               dispatch_get_main_queue(), ^{exit(0);});
            });
        });
        [NSRunLoop.mainRunLoop run];
    }
    return 0;
}
