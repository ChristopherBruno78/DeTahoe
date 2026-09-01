//
//  LinkTextField.h
//  Detahoe
//
//  NSTextField that shows a pointing-hand cursor over an embedded link and opens
//  it on click — handled directly, so no selectable-field I-beam.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LinkTextField : NSTextField

// Link range and URL — set both after assigning the attributed string.
@property (nonatomic, assign) NSRange linkRange;
@property (nonatomic, strong, nullable) NSURL *linkURL;

@end

NS_ASSUME_NONNULL_END
