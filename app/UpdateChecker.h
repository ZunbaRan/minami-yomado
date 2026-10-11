#ifndef YOMADO_UPDATE_CHECKER_H
#define YOMADO_UPDATE_CHECKER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const YMUpdateErrorDomain;

typedef NS_ENUM(NSInteger, YMUpdateErrorCode) {
    YMUpdateErrorInvalidVersion = 1,
    YMUpdateErrorInvalidResponse,
    YMUpdateErrorNoComparableRelease,
    YMUpdateErrorRateLimited,
    YMUpdateErrorHTTP,
    YMUpdateErrorNetwork,
};

typedef NS_ENUM(NSInteger, YMUpdateStatus) {
    YMUpdateStatusUpToDate,
    YMUpdateStatusAvailable,
};

@interface YMUpdateResult : NSObject
@property(nonatomic, readonly) YMUpdateStatus status;
@property(nonatomic, copy, readonly) NSString *currentVersion;
@property(nonatomic, copy, readonly) NSString *latestVersion;
@property(nonatomic, copy, readonly) NSURL *releaseURL;
@property(nonatomic, readonly, getter=isPrerelease) BOOL prerelease;
@end

typedef void (^YMUpdateCompletion)(YMUpdateResult * _Nullable result, NSError * _Nullable error);

// An explicit user action must initiate a check. This sends an anonymous GET
// only to the official GitHub repository, never downloads/installs an update,
// and includes experimental releases because yomado is currently experimental.
// Create, read `checking`, and call checkWithCompletion: on the main thread.
// Concurrent checks share one request; every callback is asynchronous on main.
@interface YMUpdateChecker : NSObject
- (instancetype)initWithCurrentVersion:(NSString *)currentVersion;
@property(nonatomic, readonly, getter=isChecking) BOOL checking;
- (void)checkWithCompletion:(YMUpdateCompletion)completion;

// Dependency injection for transport tests. Privacy settings are enforced even
// on the supplied configuration; the endpoint cannot be changed by callers.
- (instancetype)initWithCurrentVersion:(NSString *)currentVersion
                 sessionConfiguration:(NSURLSessionConfiguration *)configuration;

// Pure policy seam. Input must be the complete non-paginated releases array.
// Unknown public tags/schema fail explicitly, never report "up to date".
+ (nullable YMUpdateResult *)resultForReleases:(id)releases
                               currentVersion:(NSString *)currentVersion
                                        error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
#endif
