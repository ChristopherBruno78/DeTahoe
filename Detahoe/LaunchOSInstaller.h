//
//  LaunchOSInstaller.h
//  Detahoe
//
//  Downloads and installs LaunchOS (a Launchpad replacement for Tahoe), selects
//  its classic grid icon, and pins it to the Dock. Reports progress to the UI.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Progress on the main thread: fraction in [0, 1], plus a status string.
typedef void (^LaunchOSInstallProgress)(double fraction, NSString *status);

// Called once on the main thread when done; error is nil on success.
typedef void (^LaunchOSInstallCompletion)(BOOL success, NSError *_Nullable error);

@interface LaunchOSInstaller : NSObject

// YES if LaunchOS is already present (it can't be uninstalled).
+ (BOOL)isInstalled;

// Installs LaunchOS end to end off the main thread; both blocks fire on main.
// Retain the instance until completion fires.
- (void)installWithProgress:(nullable LaunchOSInstallProgress)progress
                 completion:(nullable LaunchOSInstallCompletion)completion;

@end

NS_ASSUME_NONNULL_END
