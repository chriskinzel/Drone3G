//
//  Drone3GSelectionBox.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GSelectionBox.h"

@implementation Drone3GSelectionBox

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)awakeFromNib {
    [self setCornerRadius:5.0f];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
}

@end
