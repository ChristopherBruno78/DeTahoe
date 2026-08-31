//
//  LinkTextField.h
//  Detahoe
//
//  An NSTextField that shows the pointing-hand cursor over an embedded link and
//  opens it on click. We handle the click ourselves (rather than relying on a
//  selectable text field) so the cursor stays a pointer and never turns into the
//  text-editing I-beam.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LinkTextField : NSTextField

// The range of the receiver's string that is a link, and the URL it opens. Set
// both after assigning the attributed string.
@property (nonatomic, assign) NSRange linkRange;
@property (nonatomic, strong, nullable) NSURL *linkURL;

@end

NS_ASSUME_NONNULL_END
