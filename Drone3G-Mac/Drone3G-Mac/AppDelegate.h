//
//  AppDelegate.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Drone3GGLView.h"
#import "Drone3GWindowController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    Drone3GWindowController* drone3GWindowController;
    BOOL batteryAnimationsAreRunning;
}

@property (strong) Drone3GWindowController* drone3GWindowController;

@property (readonly) BOOL batteryAnimationsAreRunning;

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet Drone3GGLView* drone3GGLView;

@property (assign) IBOutlet NSTextField* connectionLabel;
@property (assign) IBOutlet NSTextField* batteryLabel;
@property (assign) IBOutlet NSTextField* altitudeLabel;
@property (assign) IBOutlet NSTextField* velocityLabel;
@property (assign) IBOutlet NSTextField* timeFlyingLabel;

@property (assign) IBOutlet NSImageView* batteryImageView;
@property (assign) IBOutlet NSImageView* signalIconImageView;
@property (assign) IBOutlet NSImageView* signalLevelImageView;
@property (assign) IBOutlet NSImageView* controllerImageView;

@property (assign) IBOutlet NSMenuItem* dataUsageMenuItem;

- (IBAction)checkDataUsage:(id)sender;

- (void)showHUD;
- (void)showConnectionLabel;
- (void)hideConnectionLabel;

- (void)playWarningSound;
- (void)stopWarningSound;

- (void)flashControllerIcon;
- (void)stopFlashingControllerIcon;

- (void)batteryWarning;
- (void)batteryEmergency;
- (void)stopbatteryAnimations;

@end
