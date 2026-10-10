#ifndef YOMADO_DIAGNOSTIC_PRIVACY_H
#define YOMADO_DIAGNOSTIC_PRIVACY_H

#import <Foundation/Foundation.h>

// Create a separate JSON-compatible tree without physical device serials.
// Runtime recovery metadata and the caller's original objects are untouched.
static inline id YMRedactedDiagnostics(id object) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;
        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
        for (id key in dictionary) {
            if ([key isKindOfClass:[NSString class]] && [key isEqualToString:@"serialNumber"]) continue;
            result[key] = YMRedactedDiagnostics(dictionary[key]);
        }
        return [result copy];
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = object;
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
        for (id value in array) [result addObject:YMRedactedDiagnostics(value)];
        return [result copy];
    }
    return object;
}

#endif
