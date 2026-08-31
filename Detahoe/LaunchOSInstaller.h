//
//  LaunchOSInstaller.h
//  Detahoe
//
//  Downloads and installs LaunchOS (a Launchpad replacement for macOS Tahoe),
//  gives it the classic Sequoia Launchpad icon, and pins it to the Dock in place
//  of Tahoe's "Apps" button. This is a native Objective-C port of the former
//  install-launchos.sh shell script, so progress can be reported to the UI.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Reports installation progress on the main thread.
//   fraction — overall progress in [0, 1] (download is the bulk of it).
//   status   — a short, user-facing description of the current step.
typedef void (^LaunchOSInstallProgress)(double fraction, NSString *status);

// Called once on the main thread when installation finishes.
//   error — nil on success, otherwise describes what failed.
typedef void (^LaunchOSInstallCompletion)(BOOL success, NSError *_Nullable error);

@interface LaunchOSInstaller : NSObject

// LaunchOS installs as /Applications/Launchpad.app (bundle id below). We can't
// uninstall it, so callers use this to hide the install option once present.
+ (BOOL)isInstalled;

// Downloads the LaunchOS DMG, installs it to /Applications, applies the classic
// Launchpad icon, and pins it to the Dock. All heavy work runs off the main
// thread; both blocks are invoked on the main thread. Retain the returned
// instance until completion fires.
- (void)installWithProgress:(nullable LaunchOSInstallProgress)progress
                 completion:(nullable LaunchOSInstallCompletion)completion;

@end

NS_ASSUME_NONNULL_END
