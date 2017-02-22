//
//  Drone3GProgressView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-25.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GProgressView.h"

@implementation Drone3GProgressView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        indicatorImages[0] = [NSImage imageNamed:@"radio_current.png"];
        indicatorImages[1] = [NSImage imageNamed:@"radio_next.png"];
        indicatorImages[2] = [NSImage imageNamed:@"radio_distant.png"];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

#pragma mark -
#pragma mark Custom Methods
#pragma mark -

- (void)setProgressState:(NSInteger)state {
    for(NSView* subview in [self subviews]) {
        if([[subview identifier] intValue] == state+1) {
            [[subview viewWithTag:1] setImage:indicatorImages[0]];
            [[subview viewWithTag:2] setTextColor:[NSColor blackColor]];
            
            continue;
        }
        
        if([[subview identifier] intValue] == currentState) {
            [[subview viewWithTag:1] setImage:indicatorImages[1]];
            [[subview viewWithTag:2] setTextColor:[NSColor blackColor]];
        }
    }
    
    currentState = state+1;
}

- (void)resetProgress {
    currentState = 1;
    
    for(NSView* subview in [self subviews]) {
        if([[subview identifier] intValue] == 1) {
            [[subview viewWithTag:1] setImage:indicatorImages[0]];
            [[subview viewWithTag:2] setTextColor:[NSColor blackColor]];
            
            continue;
        }
        
        [[subview viewWithTag:1] setImage:indicatorImages[2]];
        [[subview viewWithTag:2] setTextColor:[NSColor disabledControlTextColor]];
    }
}

@end
