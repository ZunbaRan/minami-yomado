#import <Foundation/Foundation.h>
@interface YMWorkspaceService : NSObject
- (instancetype)initWithDirectory:(NSString *)directory;
- (NSDictionary *)handle:(NSString *)method arguments:(NSDictionary *)arguments;
@end
