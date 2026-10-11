#import <Foundation/Foundation.h>
#import "UpdateChecker.h"

static NSUInteger checks, failures;
static void Check(BOOL condition, NSString *description) {
    ++checks;
    if (condition) return;
    ++failures;
    fprintf(stderr, "FAIL: %s\n", description.UTF8String);
}

static NSDictionary *Release(NSString *tag, BOOL experimental) {
    return @{@"tag_name": tag, @"draft": @NO, @"prerelease": @(experimental),
             @"html_url": @"https://not-the-official-repository.invalid/phishing"};
}

static YMUpdateResult *Result(id releases, NSString *current) {
    NSError *error = nil;
    YMUpdateResult *result = [YMUpdateChecker resultForReleases:releases currentVersion:current error:&error];
    Check(result != nil && error == nil, [NSString stringWithFormat:@"valid releases compare against %@", current]);
    return result;
}

static void ExpectPolicyError(id releases, NSString *current, YMUpdateErrorCode code, NSString *name) {
    NSError *error = nil;
    YMUpdateResult *result = [YMUpdateChecker resultForReleases:releases currentVersion:current error:&error];
    Check(result == nil && [error.domain isEqualToString:YMUpdateErrorDomain] && error.code == code && error.localizedDescription.length > 0, name);
}

static void PolicyTests(void) {
    YMUpdateResult *result = Result(@[Release(@"v0.3.1", YES)], @"0.3.1");
    Check(result.status == YMUpdateStatusUpToDate && result.isPrerelease, @"current experimental release is recognized");
    Check([result.releaseURL.absoluteString isEqualToString:@"https://github.com/chekusu/yomado/releases/tag/v0.3.1"], @"release URL is constructed, never accepted from API");
    result = Result(@[Release(@"v0.3.9", NO), Release(@"v0.3.10", YES), Release(@"v0.3.2", YES)], @"0.3.9");
    Check(result.status == YMUpdateStatusAvailable && [result.latestVersion isEqualToString:@"0.3.10"], @"numeric ordering selects .10 over .9, regardless of API ordering");
    result = Result(@[Release(@"v0.4.0", YES), Release(@"v0.3.99", NO)], @"0.3.1");
    Check([result.latestVersion isEqualToString:@"0.4.0"] && result.isPrerelease, @"published experimental releases are included");
    result = Result(@[Release(@"v0.3.1", YES)], @"0.4.0");
    Check(result.status == YMUpdateStatusUpToDate && [result.currentVersion isEqualToString:@"0.4.0"], @"newer local build is never offered a downgrade");
    NSMutableDictionary *draft = [Release(@"not-semver-secret-draft", NO) mutableCopy];
    draft[@"draft"] = @YES;
    result = Result(@[draft, Release(@"v0.3.1", YES)], @"0.3.1");
    Check(result.status == YMUpdateStatusUpToDate, @"drafts are excluded before parsing tags");
    NSArray *preVersions = @[@"1.0.0-alpha", @"1.0.0-alpha.1", @"1.0.0-alpha.beta", @"1.0.0-beta", @"1.0.0-beta.2", @"1.0.0-beta.11", @"1.0.0-rc.1", @"1.0.0"];
    for (NSUInteger i = 1; i < preVersions.count; ++i) {
        result = Result(@[Release(preVersions[i], NO)], preVersions[i - 1]);
        Check(result.status == YMUpdateStatusAvailable, @"SemVer prerelease precedence follows numeric/text/stable rules");
    }
    result = Result(@[Release(@"v1.2.3+build.9", NO)], @"1.2.3+build.10");
    Check(result.status == YMUpdateStatusUpToDate, @"build metadata does not affect version precedence");
    Check([result.releaseURL.absoluteString hasSuffix:@"v1.2.3%2Bbuild.9"], @"build metadata is encoded within the release tag path");
    result = Result(@[Release(@"999999999999999999999999.0.0", NO)], @"999999999999999999999998.0.0");
    Check(result.status == YMUpdateStatusAvailable, @"large numeric components do not overflow");
    NSArray *invalid = @[@"", @"1.2", @"01.2.3", @"1.2.03", @"1.2.3-01", @"1.2.3-alpha..1", @"1.2.3+", @"1.2.3/../../other", @"1.2.3\n", @"vV1.2.3", @"release-1.2.3", @"１.2.3"];
    for (NSString *version in invalid) {
        ExpectPolicyError(@[Release(@"v0.3.1", YES)], version, YMUpdateErrorInvalidVersion, @"invalid current version fails closed");
        ExpectPolicyError(@[Release(version, YES), Release(@"v0.3.1", YES)], @"0.3.1", YMUpdateErrorInvalidResponse, @"unrecognized public tag cannot silently report up to date");
    }
    ExpectPolicyError(@[], @"0.3.1", YMUpdateErrorNoComparableRelease, @"empty release list is unknown, not current");
    ExpectPolicyError(@[draft], @"0.3.1", YMUpdateErrorNoComparableRelease, @"all drafts leave no comparable release");
    ExpectPolicyError(@{@"message": @"error"}, @"0.3.1", YMUpdateErrorInvalidResponse, @"API error object is not a release list");
    ExpectPolicyError(@[NSNull.null], @"0.3.1", YMUpdateErrorInvalidResponse, @"unexpected array member fails clearly");
    for (NSString *key in @[@"draft", @"prerelease"]) {
        NSMutableDictionary *malformed = [Release(@"v0.3.1", YES) mutableCopy];
        [malformed removeObjectForKey:key];
        ExpectPolicyError(@[malformed], @"0.3.1", YMUpdateErrorInvalidResponse, @"missing required boolean is invalid");
        malformed[key] = @"false";
        ExpectPolicyError(@[malformed], @"0.3.1", YMUpdateErrorInvalidResponse, @"string is not a JSON boolean");
        malformed[key] = @2;
        ExpectPolicyError(@[malformed], @"0.3.1", YMUpdateErrorInvalidResponse, @"number is not a JSON boolean");
    }
}

// No real networking. NSURLSession uses the exact production request builder
// and callbacks, while this protocol supplies deterministic GitHub responses.
static NSArray<NSDictionary *> *mockPages;
static NSMutableArray<NSURLRequest *> *mockRequests;
@interface YMUpdateMockProtocol : NSURLProtocol
@end
@implementation YMUpdateMockProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { (void)request; return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSDictionary *fixture;
    @synchronized(YMUpdateMockProtocol.class) {
        [mockRequests addObject:self.request];
        NSUInteger index = mockRequests.count - 1;
        fixture = mockPages[MIN(index, mockPages.count - 1)];
    }
    if (fixture[@"error"]) {
        [self.client URLProtocol:self didFailWithError:fixture[@"error"]];
        return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:[fixture[@"status"] integerValue] HTTPVersion:@"HTTP/1.1" headerFields:fixture[@"headers"]];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:fixture[@"body"]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static NSDictionary *Page(NSInteger status, id JSON, NSDictionary *headers) {
    NSData *body = [JSON isKindOfClass:NSData.class] ? JSON : [NSJSONSerialization dataWithJSONObject:JSON options:0 error:NULL];
    return @{@"status": @(status), @"body": body, @"headers": headers ?: @{}};
}

static void SetPages(NSArray *pages) {
    @synchronized(YMUpdateMockProtocol.class) {
        mockPages = pages;
        mockRequests = [NSMutableArray array];
    }
}

static NSArray<NSURLRequest *> *Requests(void) {
    @synchronized(YMUpdateMockProtocol.class) { return [mockRequests copy]; }
}

static YMUpdateChecker *Checker(NSString *current) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[YMUpdateMockProtocol.class];
    configuration.HTTPAdditionalHeaders = @{@"Authorization": @"must-not-be-sent", @"Cookie": @"must-not-be-sent"};
    return [[YMUpdateChecker alloc] initWithCurrentVersion:current sessionConfiguration:configuration];
}

static void WaitFor(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    Check(finished(), @"asynchronous check completes within fixture deadline");
}

static void ExpectNetworkError(NSDictionary *page, YMUpdateErrorCode code, NSString *name) {
    SetPages(@[page]);
    YMUpdateChecker *checker = Checker(@"0.3.1");
    __block BOOL done = NO;
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(NSThread.isMainThread && !checker.isChecking, @"error completion resets state on main queue");
        Check(!result && [error.domain isEqualToString:YMUpdateErrorDomain] && error.code == code, name);
        done = YES;
    }];
    Check(!done && checker.isChecking, @"network check returns before completion");
    WaitFor(^BOOL { return done; });
}

static void NetworkTests(void) {
    SetPages(@[Page(200, @[Release(@"v0.3.10", YES)], nil)]);
    YMUpdateChecker *checker = Checker(@"0.3.9");
    __block NSUInteger callbacks = 0;
    YMUpdateCompletion completion = ^(YMUpdateResult *result, NSError *error) {
        Check(NSThread.isMainThread && !checker.isChecking, @"success completion runs on main with settled state");
        Check(result.status == YMUpdateStatusAvailable && !error && [result.latestVersion isEqualToString:@"0.3.10"], @"network success applies version policy");
        ++callbacks;
    };
    [checker checkWithCompletion:completion];
    [checker checkWithCompletion:completion];
    Check(callbacks == 0 && checker.isChecking, @"duplicate clicks remain asynchronous");
    WaitFor(^BOOL { return callbacks == 2; });
    NSArray *requests = Requests();
    Check(requests.count == 1, @"duplicate checks coalesce into one HTTP request");
    NSURLRequest *request = requests.firstObject;
    Check([request.URL.absoluteString isEqualToString:@"https://api.github.com/repos/chekusu/yomado/releases?per_page=100&page=1"] && [request.HTTPMethod isEqualToString:@"GET"], @"only fixed official releases endpoint is queried");
    Check(![request valueForHTTPHeaderField:@"Authorization"] && ![request valueForHTTPHeaderField:@"Cookie"] && request.HTTPBody == nil && !request.HTTPShouldHandleCookies, @"query carries no credentials, cookies, or body");
    Check([[request valueForHTTPHeaderField:@"User-Agent"] isEqualToString:@"yomado-update-check"] && request.timeoutInterval == 15, @"request identifies only the product and has a bounded timeout");

    SetPages(@[Page(200, @[Release(@"v0.3.9", NO)], nil)]);
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(result.status == YMUpdateStatusUpToDate && !error && NSThread.isMainThread, @"a completed checker can be reused for another independent request");
        ++callbacks;
    }];
    WaitFor(^BOOL { return callbacks == 3; });
    Check(Requests().count == 1, @"second check creates one fresh request");
}

static void AdditionalNetworkTests(void) {
    SetPages(@[Page(200, @[Release(@"v0.3.9", NO)], @{@"Link": @"<https://elsewhere.invalid/steal>; rel=\"next\""}),
               Page(200, @[Release(@"v0.3.10", YES)], nil)]);
    __block BOOL done = NO;
    YMUpdateChecker *checker = Checker(@"0.3.9");
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(result.status == YMUpdateStatusAvailable && [result.latestVersion isEqualToString:@"0.3.10"] && !error, @"all pages are considered when selecting the newest version");
        done = YES;
    }];
    WaitFor(^BOOL { return done; });
    NSArray *requests = Requests();
    Check(requests.count == 2 && [[requests.lastObject URL].absoluteString isEqualToString:@"https://api.github.com/repos/chekusu/yomado/releases?per_page=100&page=2"], @"untrusted Link URL is not followed; next official page is constructed");

    for (NSNumber *status in @[@403, @429, @500, @503, @302]) {
        NSInteger value = status.integerValue;
        ExpectNetworkError(Page(value, @{@"message": @"untrusted server text"}, @{@"Location": @"https://elsewhere.invalid/"}),
            value == 403 || value == 429 ? YMUpdateErrorRateLimited : YMUpdateErrorHTTP,
            @"HTTP failures and redirects never report up to date");
    }
    ExpectNetworkError(Page(200, [@"not-json" dataUsingEncoding:NSUTF8StringEncoding], nil), YMUpdateErrorInvalidResponse, @"bad JSON is a format error");
    ExpectNetworkError(Page(200, @{@"message": @"unexpected"}, nil), YMUpdateErrorInvalidResponse, @"unexpected top-level JSON is a format error");
    ExpectNetworkError(Page(200, @[], nil), YMUpdateErrorNoComparableRelease, @"empty successful response is not latest");
    ExpectNetworkError(@{@"error": [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]}, YMUpdateErrorNetwork, @"timeout is recoverable network error");
    ExpectNetworkError(@{@"error": [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]}, YMUpdateErrorNetwork, @"offline is recoverable network error");

    SetPages(@[@{@"error": [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]}]);
    done = NO;
    checker = Checker(@"0.3.1");
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(result == nil && error.code == YMUpdateErrorNetwork, @"retry fixture first encounters a network failure");
        done = YES;
    }];
    WaitFor(^BOOL { return done; });
    SetPages(@[Page(200, @[Release(@"v0.3.1", YES)], nil)]);
    done = NO;
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(result.status == YMUpdateStatusUpToDate && error == nil, @"same checker succeeds after a failed request without stale error or session");
        done = YES;
    }];
    WaitFor(^BOOL { return done; });

    SetPages(@[Page(200, @[Release(@"v0.3.1", YES)], @{@"Link": @"<https://api.github.com/next>; rel=\"next\""})]);
    done = NO;
    checker = Checker(@"0.3.1");
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(result == nil && error.code == YMUpdateErrorInvalidResponse, @"incomplete oversized pagination fails instead of guessing");
        done = YES;
    }];
    WaitFor(^BOOL { return done; });
    Check(Requests().count == 10, @"pagination is bounded to ten official pages");

    SetPages(@[Page(200, @[Release(@"v0.3.1", YES)], nil)]);
    checker = Checker(@"local-development");
    done = NO;
    [checker checkWithCompletion:^(YMUpdateResult *result, NSError *error) {
        Check(result == nil && error.code == YMUpdateErrorInvalidVersion && NSThread.isMainThread, @"invalid local version completes clearly on main");
        done = YES;
    }];
    Check(!done && checker.isChecking, @"even local-validation failure is asynchronous");
    WaitFor(^BOOL { return done; });
    Check(Requests().count == 0, @"invalid local version makes no network request");
}

int main(void) {
    @autoreleasepool {
        PolicyTests();
        NetworkTests();
        AdditionalNetworkTests();
        printf("%lu update checks, %lu failures; no live network, displays, or GUI accessed.\n", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
