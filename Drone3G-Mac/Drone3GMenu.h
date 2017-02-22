//
//  Drone3GMenu.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-24.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// FIXME: Why is this calling the app delegate directly instead of explicitly ?

enum {
    DRONE3G_MENU_BUTTON_UNINSTALL = 0,
    DRONE3G_MENU_BUTTON_INSTALL,
    DRONE3G_MENU_BUTTON_START,
    DRONE3G_MENU_BUTTON_LOGIN = 4,
    DRONE3G_MENU_BUTTON_PROXY
};

enum {
    DRONE3G_MENU_STATE_MAIN = 0,
    DRONE3G_MENU_STATE_LOGIN,
    DRONE3G_MENU_STATE_FLYING
};

@interface Drone3GMenu : NSView {
    NSUInteger menuState;

    NSPoint dragPoint;
    NSPoint lastPoint;
    
    float maxSpeed;
    
    BOOL didTransistionOut;
}

@property (readonly) BOOL didTransistionOut;
@property (readonly) NSUInteger menuState;

- (void)animateOut;

@end
