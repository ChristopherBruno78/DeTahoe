//
//  LinkTextField.m
//  Detahoe
//

#import "LinkTextField.h"

@implementation LinkTextField

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _linkRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}

- (void)setLinkRange:(NSRange)linkRange {
    _linkRange = linkRange;
    [self.window invalidateCursorRectsForView:self];
}

// Rect of the linked substring (single-line, left-aligned): width of the text
// before the link is the x offset.
- (NSRect)linkRect {
    if (self.linkRange.location == NSNotFound ||
        NSMaxRange(self.linkRange) > self.attributedStringValue.length) {
        return NSZeroRect;
    }

    NSAttributedString *full = self.attributedStringValue;
    NSAttributedString *prefix =
        [full attributedSubstringFromRange:NSMakeRange(0, self.linkRange.location)];
    NSAttributedString *link =
        [full attributedSubstringFromRange:self.linkRange];

    CGFloat inset = 2.0;  // NSTextFieldCell's leading inset
    CGFloat x = inset + [prefix size].width;
    CGFloat width = [link size].width;
    return NSMakeRect(x, 0, width, NSHeight(self.bounds));
}

// Pointing-hand cursor over the link — never the I-beam.
- (void)resetCursorRects {
    [super resetCursorRects];
    NSRect rect = [self linkRect];
    if (!NSIsEmptyRect(rect)) {
        [self addCursorRect:rect cursor:[NSCursor pointingHandCursor]];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.linkURL && NSPointInRect(point, [self linkRect])) {
        [[NSWorkspace sharedWorkspace] openURL:self.linkURL];
        return;
    }
    [super mouseDown:event];
}

@end
