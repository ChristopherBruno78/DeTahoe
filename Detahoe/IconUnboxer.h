//
//  IconUnboxer.h
//  Detahoe
//
//  Objective-C declaration for the Swift IconUnboxer class. Hand-written (rather
//  than relying on the generated Detahoe-Swift.h) because importing SwiftUI
//  anywhere in the module empties that generated header. The Swift class uses
//  @objc(IconUnboxer) so its runtime symbol matches this declaration.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Result of an unbox pass. Implemented in Swift (@objc(UnboxSummary)).
@interface UnboxSummary : NSObject
@property (readonly) NSArray<NSString *> *unboxed;          // apps that were unboxed
@property (readonly) NSArray<NSString *> *appStoreSkipped;  // skipped (protected)
@end

@interface IconUnboxer : NSObject

// Detect boxed-prone icons in the given directories and install each app's own
// icon as a custom Finder icon (unboxing it). Apps macOS protects (SIP / App
// Management — /System, App Store, root-owned) are skipped. Returns a summary.
+ (UnboxSummary *)unboxInDirectories:(NSArray<NSString *> *)dirs;

// Remove the custom Finder icons this tool installed, restoring defaults.
// Returns a summary; `unboxed` holds the apps that were restored.
+ (UnboxSummary *)undoInDirectories:(NSArray<NSString *> *)dirs;

@end

NS_ASSUME_NONNULL_END
