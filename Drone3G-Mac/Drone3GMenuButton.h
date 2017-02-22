//
//  Drone3GMenuButton.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-24.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GMenuButton : NSView {
    NSTimer* vibrateTimer;
    
    NSColor* buttonColor;
    
    CGFloat initialFontSize;
    NSSize initialFrameSize;
    
    int state;
}

- (void)setButtonColor:(NSColor*)color;

@end
