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

// This fixes the PS buttons offset indices because of the removal of flat trim
- (void)selectItemAtIndex:(NSInteger)index {
    if([self tag] == 14 && index >= 4) {
        if(index == 4) {
            [NSException raise:@"Invalid function for PS button combo box" format:@"Flat trim(4) is not a valid function"];
            return;
        }
        
        return [super selectItemAtIndex:index-1];
    }
    
    return [super selectItemAtIndex:index];
}

// This fixes the PS buttons offset indices because of the removal of flat trim
- (NSInteger)indexOfSelectedItem {
    NSInteger index = [super indexOfSelectedItem];
    
    if([self tag] == 14 && index > 3) {
        return index+1;
    }
    
    return index;
}

@end
