//
//  Drone3GLoginView.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-09-04.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GLoginView : NSView {
    BOOL animating;
}

- (void)enableEditing;
- (void)disableEditing;

- (void)adjustFontSize:(CGFloat)scale;

- (void)shakeWindow;

- (NSString*)getUsername;
- (NSString*)getPassword;
- (NSString*)getDroneName;

@end
