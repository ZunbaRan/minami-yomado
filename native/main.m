#import "Common.h"
#import "WorkspaceService.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#include <signal.h>

// One request per connection. Local-only, same-user socket; operations serialize
// independently of client lifetimes. A lost response is never automatically retried.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "usage: YomadoWorkspace <private-state-directory>\n"); return 2; }
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        struct stat st;
        if (lstat(directory.fileSystemRepresentation, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 077)) {
            fprintf(stderr, "State directory must be owned by this user with mode 0700.\n"); return 2;
        }
        NSString *path = [directory stringByAppendingPathComponent:@"service.sock"];
        struct sockaddr_un addr = { .sun_family = AF_UNIX };
        if (strlen(path.fileSystemRepresentation) >= sizeof(addr.sun_path)) { fprintf(stderr, "Socket path too long.\n"); return 2; }
        int lock = open([[directory stringByAppendingPathComponent:@"service.lock"] fileSystemRepresentation], O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
        if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB)) return 0;
        // Only the lock owner may remove an obsolete endpoint.
        unlink(path.fileSystemRepresentation);
        int server = socket(AF_UNIX, SOCK_STREAM, 0);
        strlcpy(addr.sun_path, path.fileSystemRepresentation, sizeof(addr.sun_path));
        umask(0077);
        if (server < 0 || bind(server, (struct sockaddr *)&addr, sizeof(addr)) || listen(server, 16)) { perror("socket"); return 2; }
        signal(SIGPIPE, SIG_IGN);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        YMWorkspaceService *service = [[YMWorkspaceService alloc] initWithDirectory:directory];
        dispatch_queue_t operations = dispatch_queue_create("workspace.operations", DISPATCH_QUEUE_SERIAL);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            for (;;) {
                int client = accept(server, NULL, NULL);
                if (client < 0) continue;
                uid_t peer; gid_t group;
                if (getpeereid(client, &peer, &group) || peer != getuid()) { close(client); continue; }
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    @autoreleasepool {
                        struct timeval timeout = {30, 0};
                        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
                        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
                        NSMutableData *data = [NSMutableData data]; char chunk[4096]; BOOL complete = NO;
                        while (data.length <= 1048576) {
                            ssize_t n = read(client, chunk, sizeof(chunk)); if (n <= 0) break;
                            char *newline = memchr(chunk, '\n', (size_t)n);
                            [data appendBytes:chunk length:newline ? (NSUInteger)(newline-chunk) : (NSUInteger)n];
                            if (newline) { complete = YES; break; }
                        }
                        __block NSDictionary *response;
                        id request = complete && data.length <= 1048576 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                        if (![request isKindOfClass:NSDictionary.class] || ![request[@"method"] isKindOfClass:NSString.class] || ![request[@"arguments"] isKindOfClass:NSDictionary.class]) {
                            response = @{@"error":@{@"code":@"invalid_request", @"message":@"Expected method and arguments object."}};
                        } else dispatch_sync(operations, ^{
                            @autoreleasepool { @try {
                                response = @{@"result":[service handle:request[@"method"] arguments:request[@"arguments"]]};
                            } @catch (NSException *e) {
                                response = @{@"error":@{@"code":e.userInfo[@"code"] ?: @"internal_error", @"message":e.reason ?: @"Unknown error"}};
                            } }
                        });
                        NSMutableData *encoded = [[NSJSONSerialization dataWithJSONObject:response options:0 error:nil] mutableCopy];
                        [encoded appendBytes:"\n" length:1];
                        const char *bytes = encoded.bytes; NSUInteger remaining = encoded.length;
                        while (remaining) { ssize_t n = write(client, bytes, remaining); if (n <= 0) break; bytes += n; remaining -= (NSUInteger)n; }
                        close(client);
                    }
                });
            }
        });
        [NSApp run];
    }
    return 0;
}
