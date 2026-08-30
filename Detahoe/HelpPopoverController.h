//
//  HelpPopoverController.h
//  Detahoe
 

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

 
@interface HelpPopoverController : NSViewController {
    NSString * _helpText;
}

 
@property (copy) IBInspectable NSString *helpText;

 
@property IBInspectable CGFloat width;
 
- (IBAction)showHelp:(id)sender;

@end

NS_ASSUME_NONNULL_END
