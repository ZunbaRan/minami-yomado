#import <ApplicationServices/ApplicationServices.h>

// An explicit mismatched identity is stronger evidence than title/geometry.
static inline BOOL YMAllowsWindowIdentityFallback(AXError result, CGWindowID actual) {
    return result != kAXErrorSuccess || actual == kCGNullWindowID;
}
// Admission and restoration use the same physical-origin condition.
static inline BOOL YMRestorableOrigin(CGRect original, CGRect physical) {
    return !CGRectIsNull(original) && !CGRectIsEmpty(original) && CGRectContainsRect(physical, original);
}
