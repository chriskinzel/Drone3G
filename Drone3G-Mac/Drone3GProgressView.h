//
//  Drone3GProgressView.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-25.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GProgressView : NSView {
    NSImage* indicatorImages[3];
    NSInteger currentState;
}

- (void)setProgressState:(NSInteger)state;
- (void)resetProgress;

@end
