#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Foreground-only upload sink. Call start/stop and read properties on the main thread.
/// Files ending in .ARW are complete; their immutable .json contains display name and film ID.
@interface SilverphaseFTPReceiver : NSObject <NSNetServiceDelegate>
@property(nonatomic, readonly) NSString *password;
@property(nonatomic, readonly, nullable) NSString *publicationError;
- (instancetype)initWithDirectory:(NSURL *)directory film:(NSString *)film;
- (nullable NSString *)start;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
