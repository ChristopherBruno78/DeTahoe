//
//  HelpPopoverController.m
//  Detahoe
 

#import "HelpPopoverController.h"

 
@interface HelpPopoverController ()
@property (strong) NSPopover *popover;
@property (weak) NSTextField *label;
@end

@implementation HelpPopoverController
@synthesize helpText;

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _width = 260.0;
    }
    return self;
}

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _width = 260.0;
    }
    return self;
}

- (void)loadView {
    const CGFloat inset = 12.0;
    CGFloat width = self.width > 0.0 ? self.width : 260.0;

    NSTextField *label = [NSTextField wrappingLabelWithString:self.helpText ?: @""];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    // Text wraps to the configured width; the height sizes to fit.
    CGFloat contentWidth = width - (inset * 2.0);
    label.preferredMaxLayoutWidth = contentWidth;
    self.label = label;

    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:inset],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-inset],
        [label.widthAnchor constraintEqualToConstant:contentWidth],
        [container.trailingAnchor constraintEqualToAnchor:label.trailingAnchor constant:inset],
    ]];

    self.view = container;
}

-(NSString *) helpText {
    return _helpText;
}

- (void)setHelpText:(NSString *)value {
    _helpText = [value copy];
    // Keep the view in sync if it has already been loaded.
    if (self.label) {
        self.label.stringValue = _helpText ?: @"";
    }
}

- (IBAction)showHelp:(id)sender {
    if (self.popover.isShown) {
        [self.popover close];
        return;
    }

    if (!self.popover) {
        self.popover = [[NSPopover alloc] init];
        self.popover.contentViewController = self;
        self.popover.behavior = NSPopoverBehaviorTransient;
    }

    NSView *anchor = [sender isKindOfClass:[NSView class]] ? (NSView *)sender : self.view;
    [self.popover showRelativeToRect:anchor.bounds
                              ofView:anchor
                       preferredEdge:NSMaxYEdge];
}

@end
