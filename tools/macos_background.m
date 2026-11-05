// Test child only: block AppKit activation while Godot renders its offscreen viewport.
// No game input/state/timing hooks, OS input injection, or global application changes.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void ignore_activate(id self, SEL cmd, BOOL flag) {}
static BOOL ignore_running_activate(id self, SEL cmd, NSApplicationActivationOptions opts) { return NO; }

__attribute__((constructor)) static void background_only(void) {
    @autoreleasepool {
        method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(activateIgnoringOtherApps:)), (IMP)ignore_activate);
        method_setImplementation(class_getInstanceMethod([NSRunningApplication class], @selector(activateWithOptions:)), (IMP)ignore_running_activate);
        [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
}
