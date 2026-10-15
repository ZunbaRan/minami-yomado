#!/usr/bin/env python3
"""Temporary hosted-only diagnostics; never use the result as production acceptance."""
import os
import sys
from pathlib import Path

if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
    raise SystemExit('REFUSED: disposable hosted diagnostic only')
p = Path(sys.argv[1]) / 'app/PanelPresentation.m'
s = p.read_text()
def replace(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
replace('''    dispatch_async(dispatch_get_main_queue(), ^{
        [NSRunLoop.mainRunLoop performInModes:@[NSDefaultRunLoopMode] block:block];
    });''', '''    static NSUInteger traceSequence = 0;
    NSUInteger traceID = ++traceSequence;
    fprintf(stderr, "YMTRACE schedule %lu %.6f mode=%s\\n", (unsigned long)traceID,
            NSProcessInfo.processInfo.systemUptime, NSRunLoop.mainRunLoop.currentMode.UTF8String ?: "nil");
    dispatch_async(dispatch_get_main_queue(), ^{
        fprintf(stderr, "YMTRACE mainqueue %lu %.6f mode=%s\\n", (unsigned long)traceID,
                NSProcessInfo.processInfo.systemUptime, NSRunLoop.mainRunLoop.currentMode.UTF8String ?: "nil");
        [NSRunLoop.mainRunLoop performInModes:@[NSDefaultRunLoopMode] block:^{
            fprintf(stderr, "YMTRACE defaultblock %lu %.6f mode=%s\\n", (unsigned long)traceID,
                    NSProcessInfo.processInfo.systemUptime, NSRunLoop.mainRunLoop.currentMode.UTF8String ?: "nil");
            block();
        }];
    });''')
replace('''    (void)[self.environment requestActivationPolicy:requested];
    NSApplicationActivationPolicy actual = self.environment.activationPolicy;''', '''    BOOL accepted = [self.environment requestActivationPolicy:requested];
    NSApplicationActivationPolicy actual = self.environment.activationPolicy;
    fprintf(stderr, "YMTRACE policy %.6f target=%ld actual=%ld accepted=%d gen=%lu open=%d\\n",
            NSProcessInfo.processInfo.systemUptime, (long)requested, (long)actual, accepted,
            (unsigned long)self.generation, self.panelOpen);''')
replace('''    if (self.invalidated || !self.window) return;
    self.panelOpen = YES;''', '''    fprintf(stderr, "YMTRACE open %.6f gen=%lu previousOpen=%d\\n", NSProcessInfo.processInfo.systemUptime,
            (unsigned long)self.generation, self.panelOpen);
    if (self.invalidated || !self.window) return;
    self.panelOpen = YES;''')
replace('''    if (!self.panelOpen) return YES;
    self.panelOpen = NO;''', '''    fprintf(stderr, "YMTRACE close %.6f gen=%lu previousOpen=%d\\n", NSProcessInfo.processInfo.systemUptime,
            (unsigned long)self.generation, self.panelOpen);
    if (!self.panelOpen) return YES;
    self.panelOpen = NO;''')
replace('    return [NSApp setActivationPolicy:policy];', '    static NSUInteger policySequence = 0;\n    NSUInteger policyID = ++policySequence;\n    fprintf(stderr, "YMTRACE adapter-before %.6f id=%lu target=%ld app=%ld running=%ld active=%d hidden=%d\\n",\n            NSProcessInfo.processInfo.systemUptime, (unsigned long)policyID, (long)policy,\n            (long)NSApp.activationPolicy, (long)NSRunningApplication.currentApplication.activationPolicy,\n            NSApp.active, NSApp.hidden);\n    BOOL result = [NSApp setActivationPolicy:policy];\n    fprintf(stderr, "YMTRACE adapter-after %.6f id=%lu target=%ld app=%ld running=%ld result=%d active=%d hidden=%d\\n",\n            NSProcessInfo.processInfo.systemUptime, (unsigned long)policyID, (long)policy,\n            (long)NSApp.activationPolicy, (long)NSRunningApplication.currentApplication.activationPolicy,\n            result, NSApp.active, NSApp.hidden);\n    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{\n        fprintf(stderr, "YMTRACE adapter-settled %.6f id=%lu target=%ld app=%ld running=%ld active=%d hidden=%d\\n",\n                NSProcessInfo.processInfo.systemUptime, (unsigned long)policyID, (long)policy,\n                (long)NSApp.activationPolicy, (long)NSRunningApplication.currentApplication.activationPolicy,\n                NSApp.active, NSApp.hidden);\n    });\n    return result;')
replace('#import "PanelPresentation.h"', '#import "PanelPresentation.h"\n#import <ApplicationServices/ApplicationServices.h>')
replace('    return result;\n}\n- (void)activateApplication','    if (!result && policy == NSApplicationActivationPolicyAccessory) {\n        ProcessSerialNumber currentProcess = {0, kCurrentProcess};\n        OSStatus status = TransformProcessType(&currentProcess, kProcessTransformToUIElementApplication);\n        fprintf(stderr, "YMTRACE one-shot-transform %.6f id=%lu status=%d app=%ld running=%ld\\n",\n                NSProcessInfo.processInfo.systemUptime, (unsigned long)policyID, (int)status,\n                (long)NSApp.activationPolicy, (long)NSRunningApplication.currentApplication.activationPolicy);\n        return status == noErr;\n    }\n    return result;\n}\n- (void)activateApplication')
p.write_text(s)
print('DIAGNOSTIC BUILD: trace-only changes applied; not unchanged production acceptance.')
