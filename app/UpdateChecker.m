#import "UpdateChecker.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const YMUpdateErrorDomain = @"dev.chekusu.yomado.update";

static NSError *YMUpdateError(YMUpdateErrorCode code, NSString *message) {
    return [NSError errorWithDomain:YMUpdateErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

// String comparison avoids overflowing NSInteger for a valid SemVer component.
static NSComparisonResult YMCompareNumber(NSString *a, NSString *b) {
    if (a.length != b.length) return a.length < b.length ? NSOrderedAscending : NSOrderedDescending;
    return [a compare:b options:NSLiteralSearch];
}

static BOOL YMDigits(NSString *s) {
    return s.length > 0 && [s rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound;
}

static NSDictionary *YMParseVersion(NSString *input) {
    if (![input isKindOfClass:NSString.class] || input.length == 0 || input.length > 256) return nil;
    NSString *version = [input hasPrefix:@"v"] ? [input substringFromIndex:1] : input;
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
            @"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$"
            options:0 error:NULL];
    });
    NSTextCheckingResult *match = [expression firstMatchInString:version options:0 range:NSMakeRange(0, version.length)];
    if (!match || !NSEqualRanges(match.range, NSMakeRange(0, version.length))) return nil;
    NSMutableArray *core = [NSMutableArray array];
    for (NSUInteger i = 1; i <= 3; ++i) [core addObject:[version substringWithRange:[match rangeAtIndex:i]]];
    NSArray *pre = @[];
    if ([match rangeAtIndex:4].location != NSNotFound) {
        pre = [[version substringWithRange:[match rangeAtIndex:4]] componentsSeparatedByString:@"."];
        for (NSString *identifier in pre) {
            if (YMDigits(identifier) && identifier.length > 1 && [identifier hasPrefix:@"0"]) return nil;
        }
    }
    return @{@"version": version, @"core": core, @"pre": pre};
}

static NSComparisonResult YMCompareVersion(NSDictionary *a, NSDictionary *b) {
    for (NSUInteger i = 0; i < 3; ++i) {
        NSComparisonResult value = YMCompareNumber(a[@"core"][i], b[@"core"][i]);
        if (value != NSOrderedSame) return value;
    }
    NSArray *ap = a[@"pre"], *bp = b[@"pre"];
    if (!ap.count && !bp.count) return NSOrderedSame;
    if (!ap.count) return NSOrderedDescending;
    if (!bp.count) return NSOrderedAscending;
    for (NSUInteger i = 0; i < MIN(ap.count, bp.count); ++i) {
        NSString *ai = ap[i], *bi = bp[i];
        BOOL an = YMDigits(ai), bn = YMDigits(bi);
        NSComparisonResult value = an && bn ? YMCompareNumber(ai, bi) :
            (an != bn ? (an ? NSOrderedAscending : NSOrderedDescending) : [ai compare:bi options:NSLiteralSearch]);
        if (value != NSOrderedSame) return value;
    }
    return ap.count == bp.count ? NSOrderedSame : (ap.count < bp.count ? NSOrderedAscending : NSOrderedDescending);
}

static BOOL YMBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

@interface YMUpdateResult ()
@property(nonatomic) YMUpdateStatus status;
@property(nonatomic, copy) NSString *currentVersion;
@property(nonatomic, copy) NSString *latestVersion;
@property(nonatomic, copy) NSURL *releaseURL;
@property(nonatomic, getter=isPrerelease) BOOL prerelease;
@end
@implementation YMUpdateResult
@end

@interface YMUpdateChecker () <NSURLSessionTaskDelegate>
@property(nonatomic, copy) NSString *currentVersion;
@property(nonatomic, strong) NSURLSessionConfiguration *configuration;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableArray<YMUpdateCompletion> *completions;
@property(nonatomic, strong) NSMutableArray *releases;
@property(nonatomic, getter=isChecking) BOOL checking;
@end

@implementation YMUpdateChecker

- (instancetype)initWithCurrentVersion:(NSString *)currentVersion {
    return [self initWithCurrentVersion:currentVersion sessionConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
}

- (instancetype)initWithCurrentVersion:(NSString *)currentVersion sessionConfiguration:(NSURLSessionConfiguration *)configuration {
    if ((self = [super init])) {
        _currentVersion = [currentVersion copy];
        _configuration = [configuration copy];
        _configuration.URLCache = nil;
        _configuration.HTTPCookieStorage = nil;
        _configuration.URLCredentialStorage = nil;
        _configuration.HTTPShouldSetCookies = NO;
        _configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _configuration.timeoutIntervalForRequest = 15;
        _configuration.timeoutIntervalForResource = 20;
        _configuration.HTTPAdditionalHeaders = @{};
        _completions = [NSMutableArray array];
    }
    return self;
}

+ (YMUpdateResult *)resultForReleases:(id)releases currentVersion:(NSString *)currentVersion error:(NSError **)error {
    NSDictionary *current = YMParseVersion(currentVersion);
    if (!current) {
        if (error) *error = YMUpdateError(YMUpdateErrorInvalidVersion, @"无法识别当前应用的版本号，请前往 GitHub 检查版本。");
        return nil;
    }
    if (![releases isKindOfClass:NSArray.class]) {
        if (error) *error = YMUpdateError(YMUpdateErrorInvalidResponse, @"GitHub 返回的版本数据格式异常，暂时无法判断是否有更新。");
        return nil;
    }
    NSDictionary *latest = nil, *latestRelease = nil;
    for (id release in releases) {
        if (![release isKindOfClass:NSDictionary.class] || !YMBoolean(release[@"draft"])) {
            if (error) *error = YMUpdateError(YMUpdateErrorInvalidResponse, @"GitHub 返回的版本数据不完整，暂时无法判断是否有更新。");
            return nil;
        }
        if ([release[@"draft"] boolValue]) continue;
        NSDictionary *parsed = YMParseVersion(release[@"tag_name"]);
        if (!parsed || !YMBoolean(release[@"prerelease"])) {
            if (error) *error = YMUpdateError(YMUpdateErrorInvalidResponse, @"GitHub 上有无法识别的公开版本，暂时无法判断是否有更新。");
            return nil;
        }
        if (!latest || YMCompareVersion(parsed, latest) == NSOrderedDescending) {
            latest = parsed;
            latestRelease = release;
        }
    }
    if (!latest) {
        if (error) *error = YMUpdateError(YMUpdateErrorNoComparableRelease, @"GitHub 上暂时没有可比较的公开版本，请稍后再试。");
        return nil;
    }
    YMUpdateResult *result = [YMUpdateResult new];
    result.currentVersion = current[@"version"];
    result.latestVersion = latest[@"version"];
    result.status = YMCompareVersion(latest, current) == NSOrderedDescending ? YMUpdateStatusAvailable : YMUpdateStatusUpToDate;
    // Tags have already passed the ASCII SemVer grammar. Ignore all API URLs.
    NSString *tag = [latestRelease[@"tag_name"] stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
    result.releaseURL = [NSURL URLWithString:[@"https://github.com/chekusu/yomado/releases/tag/" stringByAppendingString:tag]];
    result.prerelease = [latestRelease[@"prerelease"] boolValue] || [latest[@"pre"] count] > 0;
    return result;
}

- (void)finishWithResult:(YMUpdateResult *)result error:(NSError *)error {
    NSAssert(NSThread.isMainThread, @"Update checker state belongs to the main thread");
    self.checking = NO;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.releases = nil;
    NSArray<YMUpdateCompletion> *callbacks = [self.completions copy];
    [self.completions removeAllObjects];
    for (YMUpdateCompletion callback in callbacks) callback(result, error);
}

- (void)checkWithCompletion:(YMUpdateCompletion)completion {
    NSAssert(NSThread.isMainThread, @"Call the update checker from the main thread");
    [self.completions addObject:[completion copy]];
    if (self.checking) return;
    self.checking = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YMParseVersion(self.currentVersion)) {
            [self finishWithResult:nil error:YMUpdateError(YMUpdateErrorInvalidVersion, @"无法识别当前应用的版本号，请前往 GitHub 检查版本。")];
            return;
        }
        self.releases = [NSMutableArray array];
        self.session = [NSURLSession sessionWithConfiguration:self.configuration delegate:self delegateQueue:nil];
        [self requestPage:1];
    });
}

- (void)requestPage:(NSUInteger)page {
    NSURL *URL = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/chekusu/yomado/releases?per_page=100&page=%lu", (unsigned long)page]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [request setValue:@"yomado-update-check" forHTTPHeaderField:@"User-Agent"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (networkError) {
                NSString *message = networkError.code == NSURLErrorTimedOut ? @"检查更新超时，请稍后再试。" : @"暂时无法连接 GitHub，请检查网络后再试。";
                [self finishWithResult:nil error:YMUpdateError(YMUpdateErrorNetwork, message)];
                return;
            }
            NSHTTPURLResponse *HTTP = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (!HTTP || HTTP.statusCode != 200) {
                BOOL limited = HTTP.statusCode == 403 || HTTP.statusCode == 429;
                NSString *message = limited ? @"GitHub 暂时限制了更新查询，请稍后再试，或直接打开 GitHub 发布页。" : @"GitHub 暂时无法提供版本信息，请稍后再试。";
                [self finishWithResult:nil error:YMUpdateError(limited ? YMUpdateErrorRateLimited : YMUpdateErrorHTTP, message)];
                return;
            }
            NSError *JSONError = nil;
            id releases = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError] : nil;
            if (JSONError || ![releases isKindOfClass:NSArray.class] || [releases count] > 100) {
                [self finishWithResult:nil error:YMUpdateError(YMUpdateErrorInvalidResponse, @"GitHub 返回的版本数据格式异常，暂时无法判断是否有更新。")];
                return;
            }
            [self.releases addObjectsFromArray:releases];
            NSString *link = [HTTP valueForHTTPHeaderField:@"Link"];
            // Never follow an API-provided URL. Pagination stays at the fixed
            // official endpoint. A bounded traversal fails rather than guessing.
            BOOL more = link.length > 0 && [link rangeOfString:@"rel=\"next\""].location != NSNotFound;
            if (more) {
                if (page >= 10) {
                    [self finishWithResult:nil error:YMUpdateError(YMUpdateErrorInvalidResponse, @"公开版本列表过长，暂时无法完整检查，请前往 GitHub 查看。")];
                } else {
                    [self requestPage:page + 1];
                }
                return;
            }
            NSError *policyError = nil;
            YMUpdateResult *result = [YMUpdateChecker resultForReleases:self.releases currentVersion:self.currentVersion error:&policyError];
            [self finishWithResult:result error:policyError];
        });
    }] resume];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    completionHandler(nil);
}

@end
