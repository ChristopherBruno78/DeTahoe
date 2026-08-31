//
//  LaunchOSInstaller.m
//  Detahoe
//

#import "LaunchOSInstaller.h"
#import <AppKit/AppKit.h>

// --- config -----------------------------------------------------------------
static NSString * const kDMGURL   = @"https://static.remixdesign.app/launchos/LaunchOS-2.3.0-443.dmg";
// Install as "Launchpad.app" so the Dock label reads "Launchpad", matching the
// classic look.
static NSString * const kAppName  = @"Launchpad.app";
static NSString * const kAppPath  = @"/Applications/Launchpad.app";
static NSString * const kBundleID = @"app.remixdesign.LaunchOS";

static NSString * const kErrorDomain = @"DetahoeLaunchOSInstaller";

// The download is the long part, so it owns most of the progress bar; the local
// install steps share the remainder.
static const double kDownloadShare = 0.80;

@interface LaunchOSInstaller () <NSURLSessionDownloadDelegate>

@property (copy)   LaunchOSInstallProgress   progressBlock;
@property (copy)   LaunchOSInstallCompletion completionBlock;
@property (strong) NSURLSession *session;
@property (strong) NSString *mountPoint;   // set once the DMG is mounted
// Retains the installer for the duration of the async install so the caller
// doesn't have to.
@property (strong) LaunchOSInstaller *selfRef;

@end

@implementation LaunchOSInstaller

+ (BOOL)isInstalled {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kAppPath]) {
        return YES;
    }
    NSURL *found = [[NSWorkspace sharedWorkspace]
        URLForApplicationWithBundleIdentifier:kBundleID];
    return found != nil;
}

- (void)installWithProgress:(LaunchOSInstallProgress)progress
                 completion:(LaunchOSInstallCompletion)completion {
    self.progressBlock   = progress;
    self.completionBlock = completion;
    self.selfRef         = self;

    [self reportProgress:0.0 status:@"Preparing…"];

    NSURL *url = [NSURL URLWithString:kDMGURL];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    // Delegate callbacks run on this private queue; we hop to main for UI.
    self.session = [NSURLSession sessionWithConfiguration:config
                                                 delegate:self
                                            delegateQueue:nil];
    [[self.session downloadTaskWithURL:url] resume];
}

#pragma mark - Progress / completion helpers

- (void)reportProgress:(double)fraction status:(NSString *)status {
    LaunchOSInstallProgress block = self.progressBlock;
    if (!block) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        block(fraction, status);
    });
}

- (void)finishWithError:(NSError *)error {
    [self.session finishTasksAndInvalidate];
    LaunchOSInstallCompletion block = self.completionBlock;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) {
            block(error == nil, error);
        }
        // Release the self-retain after the callback has run.
        self.selfRef = nil;
    });
}

- (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:kErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0) {
        [self reportProgress:0.0 status:@"Downloading LaunchOS…"];
        return;
    }
    double ratio = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
    NSString *status = [NSString stringWithFormat:@"Downloading LaunchOS… %.0f%%", ratio * 100.0];
    [self reportProgress:ratio * kDownloadShare status:status];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    // The temp file at `location` is deleted when this method returns, so move it
    // somewhere stable first.
    NSString *dmgPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"detahoe-launchos.dmg"];
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dmgPath error:NULL];
    if (![[NSFileManager defaultManager] moveItemAtURL:location
                                                 toURL:[NSURL fileURLWithPath:dmgPath]
                                                 error:&error]) {
        [self finishWithError:error];
        return;
    }
    // Run the local install steps off the delegate queue.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self runInstallStepsWithDMGPath:dmgPath];
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    // Only surface transport errors here; success flows through the download
    // delegate above.
    if (error) {
        [self finishWithError:error];
    }
}

#pragma mark - Local install steps

// Mirrors install-launchos.sh: mount, copy into /Applications, apply the classic
// icon, and pin to the Dock. Runs on a background queue.
- (void)runInstallStepsWithDMGPath:(NSString *)dmgPath {
    NSError *error = nil;

    // --- 1. mount ----------------------------------------------------------
    [self reportProgress:0.85 status:@"Mounting disk image…"];
    NSString *mountPoint = [self mountDMGAtPath:dmgPath error:&error];
    if (!mountPoint) {
        [self cleanupDMGAtPath:dmgPath];
        [self finishWithError:error ?: [self errorWithMessage:@"Could not mount the LaunchOS disk image."]];
        return;
    }
    self.mountPoint = mountPoint;

    // --- 2. install --------------------------------------------------------
    [self reportProgress:0.88 status:@"Installing to Applications…"];
    NSString *srcApp = [self appInDirectory:mountPoint];
    if (!srcApp) {
        [self detachMountPoint:mountPoint];
        [self cleanupDMGAtPath:dmgPath];
        [self finishWithError:[self errorWithMessage:@"No app was found inside the LaunchOS disk image."]];
        return;
    }

    [[NSFileManager defaultManager] removeItemAtPath:kAppPath error:NULL];
    if ([self runTool:@"/usr/bin/ditto" arguments:@[ srcApp, kAppPath ]] != 0) {
        [self detachMountPoint:mountPoint];
        [self cleanupDMGAtPath:dmgPath];
        [self finishWithError:[self errorWithMessage:@"Failed to copy LaunchOS into /Applications."]];
        return;
    }
    // Clear quarantine so the app opens without a Gatekeeper prompt.
    [self runTool:@"/usr/bin/xattr" arguments:@[ @"-dr", @"com.apple.quarantine", kAppPath ]];

    [self detachMountPoint:mountPoint];
    self.mountPoint = nil;
    [self cleanupDMGAtPath:dmgPath];

    // --- 3. apply the classic Sequoia icon ---------------------------------
    // The legacy .icns bundled inside the app itself. NSWorkspace.setIcon runs
    // in-process here (no swift subprocess needed), writing it as a custom Finder
    // icon so the old Launchpad look wins over the live Liquid Glass icon.
    [self reportProgress:0.94 status:@"Applying Launchpad icon…"];
    NSString *iconPath = [kAppPath stringByAppendingPathComponent:@"Contents/Resources/AppIcon.icns"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
        if (icon) {
            [[NSWorkspace sharedWorkspace] setIcon:icon forFile:kAppPath options:0];
        }
    }

    // --- 4. put it in the Dock, replacing the "Apps" button ----------------
    [self reportProgress:0.98 status:@"Updating the Dock…"];
    [self pinToDock];

    [self reportProgress:1.0 status:@"Done."];
    [self finishWithError:nil];
}

// Mounts the DMG and returns its /Volumes mount point, or nil on failure.
// hdiutil's -plist output is parsed rather than its human-readable table, which
// is empty under -quiet and breaks on volume names with spaces.
- (NSString *)mountDMGAtPath:(NSString *)dmgPath error:(NSError **)error {
    NSData *output = nil;
    int status = [self runTool:@"/usr/bin/hdiutil"
                     arguments:@[ @"attach", dmgPath, @"-nobrowse", @"-noverify", @"-plist" ]
                        output:&output];
    if (status != 0 || output.length == 0) {
        return nil;
    }
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:output
                                                                   options:0
                                                                    format:NULL
                                                                     error:error];
    for (NSDictionary *entity in plist[@"system-entities"]) {
        NSString *mount = entity[@"mount-point"];
        if (mount.length > 0) {
            return mount;
        }
    }
    return nil;
}

// Returns the first .app at the top level of `dir`, or nil.
- (NSString *)appInDirectory:(NSString *)dir {
    NSArray<NSString *> *contents =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *name in contents) {
        if ([name.pathExtension isEqualToString:@"app"]) {
            return [dir stringByAppendingPathComponent:name];
        }
    }
    return nil;
}

- (void)detachMountPoint:(NSString *)mountPoint {
    if (mountPoint.length > 0) {
        [self runTool:@"/usr/bin/hdiutil" arguments:@[ @"detach", mountPoint, @"-quiet" ]];
    }
}

- (void)cleanupDMGAtPath:(NSString *)dmgPath {
    [[NSFileManager defaultManager] removeItemAtPath:dmgPath error:NULL];
}

// Removes Tahoe's built-in "Apps"/Launchpad tile plus any prior LaunchOS entries,
// then inserts LaunchOS as the first persistent app so it sits right next to the
// Finder icon — exactly where Tahoe's "Apps" button used to be. Edits the Dock
// plist directly (as the script did) and relaunches the Dock to pick it up.
- (void)pinToDock {
    // Read/write through cfprefsd (the preferences API), not the plist file
    // directly — a direct file write is clobbered by cfprefsd's cache, so the
    // relaunched Dock would never see it.
    NSUserDefaults *dock = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.dock"];
    if (!dock) {
        return;
    }

    NSMutableArray *apps = [[dock arrayForKey:@"persistent-apps"] mutableCopy] ?: [NSMutableArray array];

    // Drop the native Apps tile and any duplicate LaunchOS/Launchpad entries.
    NSMutableIndexSet *doomed = [NSMutableIndexSet indexSet];
    [apps enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger i, BOOL *stop) {
        NSDictionary *tileData = entry[@"tile-data"];
        NSString *label = tileData[@"file-label"];
        NSString *url   = tileData[@"file-data"][@"_CFURLString"];
        NSString *tile  = entry[@"tile-type"];
        BOOL matches =
            [label isEqualToString:@"Launchpad"] || [label isEqualToString:@"LaunchOS"] ||
            [label isEqualToString:@"Apps"] ||
            [url containsString:@"/Launchpad.app"] || [url containsString:@"/LaunchOS.app"] ||
            [tile isEqualToString:@"launchpad-tile"] || [tile isEqualToString:@"apps-tile"];
        if (matches) {
            [doomed addIndex:i];
        }
    }];
    [apps removeObjectsAtIndexes:doomed];

    NSDictionary *tile = @{
        @"tile-type": @"file-tile",
        @"tile-data": @{
            @"file-label": [kAppName stringByDeletingPathExtension],
            @"file-data": @{
                @"_CFURLStringType": @15,
                @"_CFURLString": [NSString stringWithFormat:@"file://%@/", kAppPath],
            },
        },
    };
    [apps insertObject:tile atIndex:0];

    [dock setObject:apps forKey:@"persistent-apps"];
    [dock synchronize];

    [self runTool:@"/usr/bin/killall" arguments:@[ @"Dock" ]];
}

#pragma mark - Subprocess helpers

- (int)runTool:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    return [self runTool:path arguments:arguments output:NULL];
}

// Runs a tool to completion. If `output` is non-NULL, its stdout is captured
// there. Returns the termination status (or -1 if the tool couldn't launch).
- (int)runTool:(NSString *)path
     arguments:(NSArray<NSString *> *)arguments
        output:(NSData **)output {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;

    NSPipe *pipe = output ? [NSPipe pipe] : nil;
    if (pipe) {
        task.standardOutput = pipe;
    }

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Detahoe: failed to launch %@: %@", path, error);
        return -1;
    }

    // Read before waiting so a large output can't deadlock on a full pipe.
    NSData *data = pipe ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
    [task waitUntilExit];
    if (output) {
        *output = data;
    }
    return task.terminationStatus;
}

@end
