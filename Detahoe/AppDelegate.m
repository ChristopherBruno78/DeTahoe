//
//  AppDelegate.m
//  Detahoe
 


#import "AppDelegate.h"
#import "IconUnboxer.h"



// Preference keys (one per control, in UI order top-to-bottom).
static NSString * const kPrefCornerRadiusStyle   = @"cornerRadiusStyle";    // "sequoia" | "tahoe"
static NSString * const kPrefSidebarStyle        = @"sidebarStyle";         // "sequoia" | "tahoe"
static NSString * const kPrefMenuIcons           = @"menuIcons";            // BOOL
static NSString * const kPrefWindowResizeEnlarge = @"windowResizeEnlarge";  // BOOL
// Unbox and Install LaunchOS are one-shot actions triggered by Run buttons —
// they have no preference.

// Style values.
static NSString * const kStyleSequoia = @"sequoia";
static NSString * const kStyleTahoe   = @"tahoe";

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;

// Style pop-ups: item 0 = Sequoia, item 1 = Tahoe.
@property (weak) IBOutlet NSPopUpButton *cornerRadiusPopUp;
@property (weak) IBOutlet NSPopUpButton *sidebarPopUp;

// On/off switches.
@property (weak) IBOutlet NSSwitch *menuIconsSwitch;
@property (weak) IBOutlet NSSwitch *windowResizeSwitch;

// The label, help button, and Run button for the Install LaunchOS row, so the
// whole row can be hidden once LaunchOS is already installed.
@property (weak) IBOutlet NSTextField *installLaunchOSLabel;
@property (weak) IBOutlet NSButton *installLaunchOSHelpButton;
@property (weak) IBOutlet NSButton *installLaunchOSRunButton;

@end

@implementation AppDelegate

+ (void)initialize {
    if (self != [AppDelegate class]) {
        return;
    }
    // Defaults mirror the controls' initial state in the xib. Unbox and Install
    // LaunchOS are intentionally left unset (NULL): a NULL field reads as "on"
    // in the control, yet still counts as a change on the first Apply so the
    // action runs then — never at launch.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPrefCornerRadiusStyle:   kStyleSequoia,
        kPrefSidebarStyle:        kStyleSequoia,
        kPrefMenuIcons:           @YES,
        kPrefWindowResizeEnlarge: @YES,
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self loadPreferencesIntoControls];

    // Hide the Install LaunchOS row if it's already installed. Unbox and install
    // run only on Apply, never at launch.
    [self updateLaunchOSRowVisibility];
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

- (void)loadPreferencesIntoControls {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    [self selectStyle:[defaults stringForKey:kPrefCornerRadiusStyle] inPopUp:self.cornerRadiusPopUp];
    [self selectStyle:[defaults stringForKey:kPrefSidebarStyle] inPopUp:self.sidebarPopUp];

    self.menuIconsSwitch.state    = [defaults boolForKey:kPrefMenuIcons]           ? NSControlStateValueOn : NSControlStateValueOff;
    self.windowResizeSwitch.state = [defaults boolForKey:kPrefWindowResizeEnlarge] ? NSControlStateValueOn : NSControlStateValueOff;
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

// Records and saves a style change if the value differs from what's stored.
// Returns YES if the value changed.
- (BOOL)noteStyleChange:(NSMutableArray<NSString *> *)changes
                  label:(NSString *)label
                    key:(NSString *)key
               newValue:(NSString *)newValue
               defaults:(NSUserDefaults *)defaults {
    NSString *oldValue = [defaults stringForKey:key];
    if ([oldValue isEqualToString:newValue]) {
        return NO;
    }
    [changes addObject:[NSString stringWithFormat:@"%@: %@ → %@", label, oldValue, newValue]];
    [defaults setObject:newValue forKey:key];
    return YES;
}

 
- (void)applyCornerRadiusStyle:(NSString *)style {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/defaults"];
    if ([style isEqualToString:kStyleSequoia]) {
        task.arguments = @[ @"write", @"-g", @"NSConvolutionOverride1", @"-float", @"10" ];
    } else {
        // Tahoe: remove the override to restore the system default radius.
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
        // Tahoe: remove the override to restore the floating default.
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
    // A NULL (unset) value always counts as a change, even if it reads as "on".
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

// Runs `defaults` with the given arguments against the global domain.
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

// Mirrors hide-menu-icons.sh: suppresses Tahoe's automatic menu item icons via
// the global NSMenuEnableActionImages default. On = hide (false); Off = restore
// the default. AppKit reads this at app launch, so it takes effect on relaunch.
- (void)applyHideMenuIcons:(BOOL)hide {
    if (hide) {
        [self runDefaultsWithArguments:@[ @"write", @"-g", @"NSMenuEnableActionImages", @"-bool", @"false" ]];
    } else {
        [self runDefaultsWithArguments:@[ @"delete", @"-g", @"NSMenuEnableActionImages" ]];
    }
}

// Mirrors enlarge-resize-area.sh: widens the window-resize grab areas via a
// family of global AppleEdgeResize* defaults. On = Sequoia-like profile
// (corners 30 pt, edges 10 pt); Off = restore Tahoe defaults. Takes effect on
// app relaunch.
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
        // Corner 30, edges 30/3 = 10 (matching the script's default profile).
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

// Run button: unboxes app icons in /Applications via the compiled IconUnboxer.
// NSWorkspace.setIcon must run in the user's GUI session, which it does here
// since this executes inside the app process — so user-writable apps are done
// in-process. Root-owned apps (e.g. Mac App Store) can't be written directly and
// setIcon fails when run as root, so instead we briefly grant the user write via
// an ACL (the only privileged step), retry setIcon in-process, then revoke it.
// No Dock/Finder relaunch: icons refresh when each app is next relaunched.
- (IBAction)runUnbox:(id)sender {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UnboxSummary *summary = [IconUnboxer unboxInDirectories:@[ @"/Applications" ]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reportUnboxSummary:summary];
        });
    });
}

// Shows which apps were unboxed and which were skipped (Mac App Store apps can't
// be modified by third-party tools).
- (void)reportUnboxSummary:(UnboxSummary *)summary {
    [self reportSummary:summary
                 title:@"Unbox Complete"
             doneLabel:@"Unboxed"
            emptyText:@"No apps needed unboxing."];
}

// Undo button: removes the custom Finder icons the unboxer installed, restoring
// each app's default (boxed) icon. Runs off the main thread since it scans every
// bundle. Icons refresh when each app is next relaunched.
- (IBAction)runUndo:(id)sender {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UnboxSummary *summary = [IconUnboxer undoInDirectories:@[ @"/Applications" ]];
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

    NSString *details = sections.count > 0
        ? [sections componentsJoinedByString:@"\n\n"]
        : emptyText;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    [alert addButtonWithTitle:@"OK"];

    // Put the details in a wide accessory view so the alert is roomier than the
    // default narrow width.
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

// LaunchOS installs as /Applications/LaunchPad.app (bundle id below). We can't
// uninstall it, so once it's present the option is hidden entirely.
- (BOOL)isLaunchOSInstalled {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/LaunchPad.app"]) {
        return YES;
    }
    NSURL *found = [[NSWorkspace sharedWorkspace]
        URLForApplicationWithBundleIdentifier:@"app.remixdesign.LaunchOS"];
    return found != nil;
}

// Shows the Install LaunchOS row (label, help button, Run button) only when
// LaunchOS isn't installed yet.
- (void)updateLaunchOSRowVisibility {
    BOOL installed = [self isLaunchOSInstalled];
    self.installLaunchOSLabel.hidden      = installed;
    self.installLaunchOSHelpButton.hidden = installed;
    self.installLaunchOSRunButton.hidden  = installed;
}

// Run button: runs install-launchos.sh, which downloads LaunchOS, installs it to
// /Applications, applies the classic Launchpad icon, and pins it to the Dock.
// The script edits the *user's* Dock preferences, so it must run as the user
// (not via admin escalation). Runs off the main thread since it downloads a DMG.
- (IBAction)runInstallLaunchOS:(id)sender {
    if ([self isLaunchOSInstalled]) {
        return;  // Install only; never uninstall.
    }

    NSURL *resource = [[NSBundle mainBundle] URLForResource:@"install-launchos.sh"
                                              withExtension:@"txt"];
    if (!resource) {
        NSLog(@"Detahoe: install-launchos script resource missing from bundle.");
        return;
    }
    NSURL *scriptURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                        URLByAppendingPathComponent:@"detahoe-install-launchos.sh"];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtURL:scriptURL error:NULL];
    if (![[NSFileManager defaultManager] copyItemAtURL:resource toURL:scriptURL error:&error]) {
        NSLog(@"Detahoe: failed to stage install-launchos script: %@", error);
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[ scriptURL.path ];

    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finishedTask.terminationStatus != 0) {
                NSLog(@"Detahoe: install-launchos exited with status %d",
                      finishedTask.terminationStatus);
            }
            [weakSelf updateLaunchOSRowVisibility];
        });
    };

    if (![task launchAndReturnError:&error]) {
        NSLog(@"Detahoe: failed to run install-launchos: %@", error);
    }
}

- (void)reportChanges:(NSArray<NSString *> *)changes {
    NSAlert *alert = [[NSAlert alloc] init];
    if (changes.count == 0) {
        alert.messageText = @"No Changes";
        alert.informativeText = @"Your settings already match what's applied.";
    } else {
        alert.messageText = @"Applied Changes";
        alert.informativeText = [changes componentsJoinedByString:@"\n"];
    }
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end
