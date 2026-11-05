// Test child only: block AppKit activation while Godot renders its offscreen viewport.
// No game input/state/timing hooks, OS input injection, or global application changes.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void ignore_activate(id self, SEL cmd, BOOL flag) {}
static BOOL ignore_running_activate(id self, SEL cmd, NSApplicationActivationOptions opts) { return NO; }
static IMP original_policy;
static BOOL prohibit_activation(id self, SEL cmd, NSApplicationActivationPolicy policy) {
    return ((BOOL (*)(id, SEL, NSApplicationActivationPolicy))original_policy)(self, cmd, NSApplicationActivationPolicyProhibited);
}
static void ignore_window_activation(id self, SEL cmd, id sender) {}

__attribute__((constructor)) static void background_only(void) {
    @autoreleasepool {
        method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(activateIgnoringOtherApps:)), (IMP)ignore_activate);
        method_setImplementation(class_getInstanceMethod([NSRunningApplication class], @selector(activateWithOptions:)), (IMP)ignore_running_activate);
        // Godot may set its policy again after this constructor. Keep every later
        // request prohibited, including automatic AppKit/window activation.
        Method policy = class_getInstanceMethod([NSApplication class], @selector(setActivationPolicy:));
        original_policy = method_setImplementation(policy, (IMP)prohibit_activation);
        method_setImplementation(class_getInstanceMethod([NSWindow class], @selector(makeKeyAndOrderFront:)), (IMP)ignore_window_activation);
        [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyProhibited];
    }
}
