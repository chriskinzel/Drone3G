//
//  NSComboBoxExt.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-04-03.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "NSComboBoxExt.h"

@implementation NSComboBoxExt 

// Drops the combo box menu when a touch is detected anywhere inside the view
- (void)mouseDown:(NSEvent *)theEvent {
    CGPoint origin = self.frame.origin;
    NSEvent* spoofedEvent = [NSEvent mouseEventWithType:NSLeftMouseDown location:NSMakePoint(origin.x+98, origin.y+14) modifierFlags:256 timestamp:0 windowNumber:[[self window] windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
    
    [super mouseDown:spoofedEvent];
}

@end
