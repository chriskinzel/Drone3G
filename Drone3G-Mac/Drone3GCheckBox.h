//
//  Drone3GCheckBox.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-12-26.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GCheckBox : NSView {
    NSSize initialFrameSize;
    int state;
}

- (BOOL)isChecked;

@end
