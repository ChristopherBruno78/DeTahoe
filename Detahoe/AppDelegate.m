//
//  AppDelegate.m
//  Detahoe
 


#import "AppDelegate.h"
#import "IconUnboxer.h"
#import "LaunchOSInstaller.h"
#import "LinkTextField.h"
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <errno.h>



// Preference keys.
static NSString * const kPrefCornerRadiusStyle   = @"cornerRadiusStyle";    // "sequoia" | "tahoe"
static NSString * const kPrefSidebarStyle        = @"sidebarStyle";         // "sequoia" | "tahoe"
static NSString * const kPrefMenuIcons           = @"menuIcons";            // BOOL
static NSString * const kPrefWindowResizeEnlarge = @"windowResizeEnlarge";  // BOOL

// Style values.
static NSString * const kStyleSequoia = @"sequoia";
static NSString * const kStyleTahoe   = @"tahoe";

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;

// Style pop-ups: item 0 = Sequoia, item 1 = Tahoe.
@property (weak) IBOutlet NSPopUpButton *cornerRadiusPopUp;
@property (weak) IBOutlet NSPopUpButton *sidebarPopUp;

@property (weak) IBOutlet NSSwitch *menuIconsSwitch;
@property (weak) IBOutlet NSSwitch *windowResizeSwitch;

// Install LaunchOS row — hidden once LaunchOS is installed.
@property (weak) IBOutlet NSTextField *installLaunchOSLabel;
@property (weak) IBOutlet NSButton *installLaunchOSHelpButton;
@property (weak) IBOutlet NSButton *installLaunchOSRunButton;

// Retained during an install to drive the progress alert.
@property (strong) LaunchOSInstaller *launchOSInstaller;
@property (strong) NSAlert *installProgressAlert;
@property (strong) NSProgressIndicator *installProgressBar;
@property (strong) NSTextField *installProgressStatus;

@end

@implementation AppDelegate


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self unboxOwnIcon];  // avoid showing as a gray Tahoe squircle
    [self loadPreferencesIntoControls];
    [self linkifyLaunchOSLabel];
    [self updateLaunchOSRowVisibility];
    [self warnIfMissingAppManagementPermission];
}


// Whether we hold App Management permission. Asks TCC directly (works even on a
// fresh machine with no third-party apps); falls back to a filesystem probe if
// the private symbol is unavailable.
- (BOOL)hasAppManagementPermission {
    static int (*preflight)(CFStringRef, CFDictionaryRef) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY);
        if (tcc) {
            preflight = dlsym(tcc, "TCCAccessPreflight");
        }
    });
    if (preflight) {
        // 0 == authorized; 1 == denied; 2 == undetermined. Prompt unless authorized.
        return preflight(CFSTR("kTCCServiceSystemPolicyAppBundles"), NULL) == 0;
    }

    // Fallback: no-op mtime rewrite on a user-owned app in /Applications — EPERM
    // there means the TCC gate is blocking us. Assumes granted if none is found.
    NSString *apps = @"/Applications";
    NSString *ownPath = [NSBundle mainBundle].bundlePath;
    NSArray<NSString *> *entries =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:apps error:NULL];

    for (NSString *entry in entries) {
        if (![entry hasSuffix:@".app"]) {
            continue;
        }
        NSString *path = [apps stringByAppendingPathComponent:entry];
        if ([path isEqualToString:ownPath]) {
            continue;
        }
        NSString *infoPlist = [path stringByAppendingPathComponent:@"Contents/Info.plist"];
        const char *fsPath = infoPlist.fileSystemRepresentation;

        struct stat st;
        if (stat(fsPath, &st) != 0) {
            continue;
        }
        // User-owned only, so a failure means TCC, not POSIX.
        if (st.st_uid != getuid()) {
            continue;
        }

        struct timeval times[2];
        times[0].tv_sec = st.st_atimespec.tv_sec; times[0].tv_usec = 0;
        times[1].tv_sec = st.st_mtimespec.tv_sec; times[1].tv_usec = 0;  // unchanged
        if (utimes(fsPath, times) == 0) {
            return YES;
        }
        if (errno == EPERM || errno == EACCES) {
            return NO;
        }
        // Other errors inconclusive — try the next.
    }
    return YES;
}

// If App Management is missing, ask TCC to prompt for it. The native request also
// registers DeTahoe in the App Management list (it isn't there until requested),
// so if the user declines we can then send them to a pane that actually shows us.
- (void)warnIfMissingAppManagementPermission {
    if ([self hasAppManagementPermission]) {
        return;
    }

    // TCCAccessRequest isn't public — resolve it at runtime.
    static void (*request)(CFStringRef, CFDictionaryRef, void (^)(BOOL)) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY);
        if (tcc) {
            request = dlsym(tcc, "TCCAccessRequest");
        }
    });

    if (request) {
        __weak typeof(self) weakSelf = self;
        request(CFSTR("kTCCServiceSystemPolicyAppBundles"), NULL, ^(BOOL granted) {
            if (granted) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showAppManagementInstructionsAlert];
            });
        });
        return;
    }

    // Fallback if the symbol is unavailable: just show the instructions.
    [self showAppManagementInstructionsAlert];
}

// Explains how to grant App Management, with a button to the Settings pane.
- (void)showAppManagementInstructionsAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"App Management Permission Needed";
    alert.informativeText =
        @"DeTahoe needs App Management permission to modify other apps — unboxing "
         "their icons and installing Launchpad. Without it, those changes silently "
         "fail.\n\n"
         "To grant it:\n"
         "1. Open System Settings ▸ Privacy & Security ▸ App Management.\n"
         "2. Turn on DeTahoe.\n"
         "3. Relaunch DeTahoe.";
    [alert addButtonWithTitle:@"Open Settings"];
    [alert addButtonWithTitle:@"Later"];

    void (^handle)(NSModalResponse) = ^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            NSURL *url = [NSURL URLWithString:
                @"x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"];
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
    };

    if (self.window) {
        [alert beginSheetModalForWindow:self.window completionHandler:handle];
    } else {
        handle([alert runModal]);
    }
}

// Makes "LaunchOS" in the row label a clickable link (LinkTextField owns click
// + cursor, so the label stays non-selectable).
- (void)linkifyLaunchOSLabel {
    LinkTextField *label = (LinkTextField *)self.installLaunchOSLabel;
    if (![label isKindOfClass:[LinkTextField class]]) {
        return;
    }
    NSString *text = label.stringValue;
    NSRange linkRange = [text rangeOfString:@"LaunchOS"];
    if (linkRange.location == NSNotFound) {
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://launchosapp.com"];
    NSMutableAttributedString *attributed =
        [[NSMutableAttributedString alloc] initWithString:text attributes:@{
            NSFontAttributeName: label.font ?: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: [NSColor labelColor],
        }];
    // Link styling: accent color + underline.
    [attributed addAttributes:@{
        NSForegroundColorAttributeName: [NSColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
    } range:linkRange];
    label.attributedStringValue = attributed;

    label.linkURL = url;
    label.linkRange = linkRange;
}

// Installs our .icns as a custom Finder icon on our own bundle each launch,
// beating Tahoe's gray squircle. Loads from the .icns (not applicationIconImage,
// which yields an empty custom icon) at the real, de-translocated path.
- (void)unboxOwnIcon {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundlePath = [self realBundlePath];

    NSString *iconName = [bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ?: @"AppIcon";
    NSString *icnsPath = [bundle pathForResource:iconName.stringByDeletingPathExtension
                                          ofType:@"icns"];
    NSImage *icon = icnsPath ? [[NSImage alloc] initWithContentsOfFile:icnsPath]
                             : [NSApp applicationIconImage];
    if (!bundlePath || !icon) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        // De-quarantine so future launches run in place (no translocation).
        NSTask *unquarantine = [[NSTask alloc] init];
        unquarantine.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xattr"];
        unquarantine.arguments = @[ @"-dr", @"com.apple.quarantine", bundlePath ];
        [unquarantine launchAndReturnError:NULL];
        [unquarantine waitUntilExit];

        BOOL ok = [[NSWorkspace sharedWorkspace] setIcon:icon forFile:bundlePath options:0];
        if (!ok) {
            NSLog(@"Detahoe: failed to unbox own icon at %@", bundlePath);
            return;
        }
        // Refresh just this item — no full Finder relaunch.
        [[NSWorkspace sharedWorkspace] noteFileSystemChanged:bundlePath];
    });
}

// Our real path, resolving App Translocation to reach the on-disk bundle.
- (NSString *)realBundlePath {
    NSURL *bundleURL = [NSBundle mainBundle].bundleURL;

    // SecTranslocate* aren't public — resolve at runtime.
    static Boolean (*isTranslocated)(CFURLRef, bool *, CFErrorRef *) = NULL;
    static CFURLRef (*originalPath)(CFURLRef, CFErrorRef *) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (security) {
            isTranslocated = dlsym(security, "SecTranslocateIsTranslocatedURL");
            originalPath   = dlsym(security, "SecTranslocateCreateOriginalPathForURL");
        }
    });

    if (isTranslocated && originalPath) {
        bool translocated = false;
        if (isTranslocated((__bridge CFURLRef)bundleURL, &translocated, NULL) && translocated) {
            CFURLRef original = originalPath((__bridge CFURLRef)bundleURL, NULL);
            if (original) {
                return [(__bridge_transfer NSURL *)original path];
            }
        }
    }
    return bundleURL.path;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

#pragma mark - Preferences <-> controls

// Maps a pop-up's selection to a style string.
- (NSString *)styleForPopUp:(NSPopUpButton *)popUp {
    return popUp.indexOfSelectedItem == 1 ? kStyleTahoe : kStyleSequoia;
}

- (void)selectStyle:(NSString *)style inPopUp:(NSPopUpButton *)popUp {
    [popUp selectItemAtIndex:[style isEqualToString:kStyleTahoe] ? 1 : 0];
}

// Loads only the preferences that already exist, leaving any unset control at
// its xib initial state so the first Apply still registers it as a change.
- (void)loadPreferencesIntoControls {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults objectForKey:kPrefCornerRadiusStyle]) {
        [self selectStyle:[defaults stringForKey:kPrefCornerRadiusStyle] inPopUp:self.cornerRadiusPopUp];
    }
    if ([defaults objectForKey:kPrefSidebarStyle]) {
        [self selectStyle:[defaults stringForKey:kPrefSidebarStyle] inPopUp:self.sidebarPopUp];
    }
    if ([defaults objectForKey:kPrefMenuIcons]) {
        self.menuIconsSwitch.state = [defaults boolForKey:kPrefMenuIcons] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if ([defaults objectForKey:kPrefWindowResizeEnlarge]) {
        self.windowResizeSwitch.state = [defaults boolForKey:kPrefWindowResizeEnlarge] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

#pragma mark - Apply

- (IBAction)apply:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray<NSString *> *changes = [NSMutableArray array];

    BOOL menuIcons    = self.menuIconsSwitch.state    == NSControlStateValueOn;
    BOOL windowResize = self.windowResizeSwitch.state == NSControlStateValueOn;

    NSString *cornerStyle  = [self styleForPopUp:self.cornerRadiusPopUp];
    NSString *sidebarStyle = [self styleForPopUp:self.sidebarPopUp];

    BOOL cornerChanged = [self noteStyleChange:changes label:@"Window Corners"
                                           key:kPrefCornerRadiusStyle newValue:cornerStyle defaults:defaults];
    if (cornerChanged) {
        [self applyCornerRadiusStyle:cornerStyle];
    }
    BOOL sidebarChanged = [self noteStyleChange:changes label:@"Sidebars"
                                            key:kPrefSidebarStyle newValue:sidebarStyle defaults:defaults];
    if (sidebarChanged) {
        [self applySidebarStyle:sidebarStyle];
    }
    BOOL menuIconsChanged = [self noteToggleChange:changes label:@"Hide Superfluous Menu Icons"
                                               key:kPrefMenuIcons newValue:menuIcons defaults:defaults];
    if (menuIconsChanged) {
        [self applyHideMenuIcons:menuIcons];
    }
    BOOL windowResizeChanged = [self noteToggleChange:changes label:@"Enlarge Window Resize Area"
                                                  key:kPrefWindowResizeEnlarge newValue:windowResize defaults:defaults];
    if (windowResizeChanged) {
        [self applyEnlargeResizeArea:windowResize];
    }

    [defaults synchronize];
    [self reportChanges:changes];
}

// Graceful quit; macOS relaunches Finder so it re-reads the appearance defaults.
- (void)relaunchFinder {
    NSArray<NSRunningApplication *> *finders =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"];
    for (NSRunningApplication *finder in finders) {
        [finder terminate];
    }
}

// Restarts the Dock to re-read its prefs. It ignores -terminate, so kill it;
// macOS relaunches it.
- (void)relaunchDock {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/killall"];
    task.arguments = @[ @"Dock" ];
    [task launchAndReturnError:NULL];
}

// Saves a style change if it differs from what's stored; returns YES if changed.
- (BOOL)noteStyleChange:(NSMutableArray<NSString *> *)changes
                  label:(NSString *)label
                    key:(NSString *)key
               newValue:(NSString *)newValue
               defaults:(NSUserDefaults *)defaults {
    NSString *oldValue = [defaults stringForKey:key];
    if ([oldValue isEqualToString:newValue]) {
        return NO;
    }
    [changes addObject:[NSString stringWithFormat:@"%@: %@ → %@",
                        label, oldValue ?: @"Not set", newValue]];
    [defaults setObject:newValue forKey:key];
    return YES;
}

 
- (void)applyCornerRadiusStyle:(NSString *)style {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/defaults"];
    if ([style isEqualToString:kStyleSequoia]) {
        task.arguments = @[ @"write", @"-g", @"NSConvolutionOverride1", @"-float", @"10" ];
    } else {
        // Tahoe: remove override → system default.
        task.arguments = @[ @"delete", @"-g", @"NSConvolutionOverride1" ];
    }
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Detahoe: failed to apply corner radius style: %@", error);
    }
}

 
- (void)applySidebarStyle:(NSString *)style {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/defaults"];
    if ([style isEqualToString:kStyleSequoia]) {
        task.arguments = @[ @"write", @"-g", @"NSSplitViewItemSidebarDefaultsToFloatingAppearance", @"-bool", @"false" ];
    } else {
        // Tahoe: remove override → floating default.
        task.arguments = @[ @"delete", @"-g", @"NSSplitViewItemSidebarDefaultsToFloatingAppearance" ];
    }
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Detahoe: failed to apply sidebar style: %@", error);
    }
}

 
- (BOOL)noteToggleChange:(NSMutableArray<NSString *> *)changes
                   label:(NSString *)label
                     key:(NSString *)key
                newValue:(BOOL)newValue
                defaults:(NSUserDefaults *)defaults {
    // Unset always counts as a change, even though it reads as "on".
    id stored = [defaults objectForKey:key];
    BOOL oldValue = [stored boolValue];
    if (stored != nil && oldValue == newValue) {
        return NO;
    }
    NSString *oldDesc = stored == nil ? @"Not set" : (oldValue ? @"On" : @"Off");
    [changes addObject:[NSString stringWithFormat:@"%@: %@ → %@",
                        label, oldDesc, newValue ? @"On" : @"Off"]];
    [defaults setBool:newValue forKey:key];
    return YES;
}

// Runs `defaults` with the given arguments.
- (void)runDefaultsWithArguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/defaults"];
    task.arguments = arguments;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Detahoe: `defaults %@` failed: %@",
              [arguments componentsJoinedByString:@" "], error);
    }
}

// Hides Tahoe's automatic menu-item icons via NSMenuEnableActionImages. Takes
// effect on app relaunch.
- (void)applyHideMenuIcons:(BOOL)hide {
    if (hide) {
        [self runDefaultsWithArguments:@[ @"write", @"-g", @"NSMenuEnableActionImages", @"-bool", @"false" ]];
    } else {
        [self runDefaultsWithArguments:@[ @"delete", @"-g", @"NSMenuEnableActionImages" ]];
    }
}

// Widens window-resize grab areas via AppleEdgeResize* defaults (corners 30 pt,
// edges 10 pt). Takes effect on app relaunch.
- (void)applyEnlargeResizeArea:(BOOL)enlarge {
    NSArray<NSString *> *cornerKeys = @[
        @"AppleEdgeResizeCornerSize",
        @"AppleEdgeResizeCornerSizeNE", @"AppleEdgeResizeCornerSizeNW",
        @"AppleEdgeResizeCornerSizeSE", @"AppleEdgeResizeCornerSizeSW",
    ];
    NSArray<NSString *> *edgeKeys = @[
        @"AppleEdgeResizeExteriorSize", @"AppleEdgeResizeBorderSize",
    ];

    if (enlarge) {
        for (NSString *key in cornerKeys) {
            [self runDefaultsWithArguments:@[ @"write", @"-g", key, @"-float", @"30" ]];
        }
        for (NSString *key in edgeKeys) {
            [self runDefaultsWithArguments:@[ @"write", @"-g", key, @"-float", @"10" ]];
        }
    } else {
        for (NSString *key in [cornerKeys arrayByAddingObjectsFromArray:edgeKeys]) {
            [self runDefaultsWithArguments:@[ @"delete", @"-g", key ]];
        }
    }
}

#pragma mark - Unbox

- (IBAction)runUnbox:(id)sender {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UnboxSummary *summary = [IconUnboxer unboxInDirectories:@[ @"/Applications" ]];
        [self refreshFinderForApps:summary.unboxed inDirectory:@"/Applications"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reportUnboxSummary:summary];
        });
    });
}

// Nudges Finder to redraw each changed app's icon right away, so the user doesn't
// have to relaunch every app to see it. `names` are app names without ".app".
- (void)refreshFinderForApps:(NSArray<NSString *> *)names inDirectory:(NSString *)dir {
    for (NSString *name in names) {
        NSString *path = [[dir stringByAppendingPathComponent:name]
                          stringByAppendingPathExtension:@"app"];
        [[NSWorkspace sharedWorkspace] noteFileSystemChanged:path];
    }
}

- (void)reportUnboxSummary:(UnboxSummary *)summary {
    [self reportSummary:summary
                 title:@"Unbox Complete"
             doneLabel:@"Unboxed"
            emptyText:@"No apps needed unboxing."];
}


- (IBAction)runUndo:(id)sender {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UnboxSummary *summary = [IconUnboxer undoInDirectories:@[ @"/Applications" ]];
        [self refreshFinderForApps:summary.unboxed inDirectory:@"/Applications"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reportSummary:summary
                         title:@"Reversion Complete"
                     doneLabel:@"Restored"
                    emptyText:@"No unboxed apps to restore."];
        });
    });
}

 
- (void)reportSummary:(UnboxSummary *)summary
                title:(NSString *)title
            doneLabel:(NSString *)doneLabel
            emptyText:(NSString *)emptyText {
    NSMutableArray<NSString *> *sections = [NSMutableArray array];

    if (summary.unboxed.count > 0) {
        [sections addObject:[NSString stringWithFormat:@"%@ (%lu):\n• %@",
            doneLabel, (unsigned long)summary.unboxed.count,
            [summary.unboxed componentsJoinedByString:@"\n• "]]];
    }
    if (summary.appStoreSkipped.count > 0) {
        [sections addObject:[NSString stringWithFormat:
            @"Skipped — Mac App Store installed (%lu):\n• %@",
            (unsigned long)summary.appStoreSkipped.count,
            [summary.appStoreSkipped componentsJoinedByString:@"\n• "]]];
    }

    // Finder refreshes now; a running app's own Dock icon updates on relaunch.
    if (summary.unboxed.count > 0) {
        [sections addObject:@"Any app that's currently running updates its icon when you relaunch it."];
    }

    NSString *details = sections.count > 0
        ? [sections componentsJoinedByString:@"\n\n"]
        : emptyText;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    [alert addButtonWithTitle:@"OK"];

    // Wide accessory view for roomier text.
    const CGFloat width = 320.0;
    NSTextField *body = [NSTextField wrappingLabelWithString:details];
    body.selectable = YES;
    body.preferredMaxLayoutWidth = width;
    NSSize fit = [body sizeThatFits:NSMakeSize(width, CGFLOAT_MAX)];
    body.frame = NSMakeRect(0, 0, width, fit.height);
    alert.accessoryView = body;

    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Install LaunchOS

// Install-only; the option is hidden once LaunchOS is present.
- (BOOL)isLaunchOSInstalled {
    return [LaunchOSInstaller isInstalled];
}

 
- (void)updateLaunchOSRowVisibility {
    BOOL installed = [self isLaunchOSInstalled];
    self.installLaunchOSLabel.hidden      = installed;
    self.installLaunchOSHelpButton.hidden = installed;
    self.installLaunchOSRunButton.hidden  = installed;
}
 
- (IBAction)runInstallLaunchOS:(id)sender {
    if ([self isLaunchOSInstalled]) {
        return;  // Install only; never uninstall.
    }

    [self presentInstallProgressAlert];

    __weak typeof(self) weakSelf = self;
    self.launchOSInstaller = [[LaunchOSInstaller alloc] init];
    [self.launchOSInstaller installWithProgress:^(double fraction, NSString *status) {
        weakSelf.installProgressBar.doubleValue = fraction;
        weakSelf.installProgressStatus.stringValue = status;
    } completion:^(BOOL success, NSError *error) {
        [weakSelf dismissInstallProgressAlertWithSuccess:success error:error];
    }];
}
 
- (void)presentInstallProgressAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Installing LaunchOS";
    alert.informativeText = @"Downloading and installing LaunchOS. This may take a moment.";

    // No dismiss button — the sheet closes itself when done.
    alert.buttons.firstObject.hidden = YES;

    const CGFloat width = 320.0;

    NSProgressIndicator *bar =
        [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 22, width, 20)];
    bar.style = NSProgressIndicatorStyleBar;
    bar.indeterminate = NO;
    bar.minValue = 0.0;
    bar.maxValue = 1.0;
    bar.doubleValue = 0.0;

    NSTextField *status = [NSTextField labelWithString:@"Preparing…"];
    status.frame = NSMakeRect(0, 0, width, 16);
    status.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    status.textColor = [NSColor secondaryLabelColor];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 42)];
    [accessory addSubview:bar];
    [accessory addSubview:status];
    alert.accessoryView = accessory;

    self.installProgressAlert  = alert;
    self.installProgressBar    = bar;
    self.installProgressStatus = status;

    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

// Closes the progress sheet and reports the result.
- (void)dismissInstallProgressAlertWithSuccess:(BOOL)success error:(NSError *)error {
    if (self.installProgressAlert) {
        [self.window endSheet:self.installProgressAlert.window];
    }
    self.installProgressAlert  = nil;
    self.installProgressBar    = nil;
    self.installProgressStatus = nil;
    self.launchOSInstaller     = nil;

    [self updateLaunchOSRowVisibility];

    NSAlert *result = [[NSAlert alloc] init];
    if (success) {
        result.messageText = @"LaunchOS Installed";
        result.informativeText =
            @"The Dock needs to restart for the new Launchpad tile to appear.";
        // Offer a Dock restart rather than forcing it.
        [result addButtonWithTitle:@"Restart Dock"];
        [result addButtonWithTitle:@"OK"];
        [result beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response == NSAlertFirstButtonReturn) {
                [self relaunchDock];
            }
        }];
        return;
    }

    result.alertStyle = NSAlertStyleWarning;
    result.messageText = @"Installation Failed";
    result.informativeText = error.localizedDescription
        ?: @"LaunchOS could not be installed.";
    [result addButtonWithTitle:@"OK"];
    [result beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)reportChanges:(NSArray<NSString *> *)changes {
    // Nothing changed → stay silent.
    if (changes.count == 0) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Applied Changes";
    alert.informativeText = [NSString stringWithFormat:
        @"%@\n\nApps pick up these changes when they're relaunched.",
        [changes componentsJoinedByString:@"\n"]];
    // Offer a Finder restart rather than forcing it.
    [alert addButtonWithTitle:@"Restart Finder"];
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [self relaunchFinder];
        }
    }];
}

@end
