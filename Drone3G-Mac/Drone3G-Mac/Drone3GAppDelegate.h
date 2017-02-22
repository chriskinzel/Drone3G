//
//  AppDelegate.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "Drone3GGLView.h"
#import "Drone3GDATWindowController.h"
#import "Drone3GPREFWindowController.h"
#import "Drone3GPLANWindowController.h"

@interface Drone3GAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSSpeechSynthesizerDelegate> {
    NSSpeechSynthesizer* alertSpeaker;
    
    Drone3GDATWindowController* drone3GDatWindowController;
    Drone3GPREFWindowController* drone3GPrefWindowController;
    Drone3GPLANWindowController* drone3GPlanWindowController;
    
    BOOL batteryAnimationsAreRunning;
    BOOL batteryAnimationsAreWaiting;
    BOOL firstSpeechDonePlaying;
    
    NSTimer* controllerFlashTimer;
    NSTimer* batteryFlashTimer;
    NSTimer* warningStopTimer;
    
    NSSound* beep;
    
    pthread_t drone3g_thread;
}

@property (strong) Drone3GDATWindowController* drone3GDatWindowController;
@property (strong) Drone3GPREFWindowController* drone3GPrefWindowController;
@property (strong) Drone3GPLANWindowController* drone3GPlanWindowController;

@property (readonly) BOOL batteryAnimationsAreRunning;

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet Drone3GGLView* drone3GGLView;

@property (assign) IBOutlet NSTextField* connectionLabel;
@property (assign) IBOutlet NSTextField* batteryLabel;
@property (assign) IBOutlet NSTextField* altitudeLabel;
@property (assign) IBOutlet NSTextField* velocityLabel;
@property (assign) IBOutlet NSTextField* timeFlyingLabel;
@property (assign) IBOutlet NSTextField* gpsLabel;

@property (assign) IBOutlet NSImageView* batteryImageView;
@property (assign) IBOutlet NSImageView* signalIconImageView;
@property (assign) IBOutlet NSImageView* signalLevelImageView;
@property (assign) IBOutlet NSImageView* controllerImageView;

@property (assign) IBOutlet NSMenuItem* dataUsageMenuItem;
@property (assign) IBOutlet NSMenuItem* flightPlanMenuItem;

@property (assign) IBOutlet NSTextField* directionLabel;
@property (assign) IBOutlet NSTextField* angleLabel;

@property (assign) IBOutlet NSTextField* northLabel;
@property (assign) IBOutlet NSTextField* northAngleLabel;

@property (assign) IBOutlet NSTextField* eastLabel;
@property (assign) IBOutlet NSTextField* eastAngleLabel;

@property (assign) IBOutlet NSTextField* westLabel;
@property (assign) IBOutlet NSTextField* westAngleLabel;

@property (assign) IBOutlet NSTextField* southLabel;
@property (assign) IBOutlet NSTextField* southAngleLabel;

@property (assign) IBOutlet NSMenuItem* sliderMenuItem;
@property (assign) IBOutlet NSMenuItem* bitrateMenuItem;
@property (assign) IBOutlet NSMenuItem* hdMenuItem;
@property (assign) IBOutlet NSMenuItem* sdMenuItem;
@property (assign) IBOutlet NSTextField* bitrateLabel;
@property (assign) IBOutlet NSView* bitrateSlider;

@property (assign) IBOutlet NSMenuItem* sensitivityMenuItem;
@property (assign) IBOutlet NSView* sensitivityView;

- (IBAction)openPreferences:(id)sender;
- (IBAction)checkDataUsage:(id)sender;
- (IBAction)openFlightPlanner:(id)sender;

- (IBAction)use720pVideo:(id)sender;
- (IBAction)use360pVideo:(id)sender;
- (IBAction)changeBitrate:(id)sender;

- (IBAction)sensitivitySliderDidChange:(id)sender;
- (IBAction)restoreDefaultSensitivities:(id)sender;

- (void)showHUD;
- (void)showConnectionLabel;
- (void)hideConnectionLabel;

- (void)playGPSAlertSound;
- (void)playWarningSound;
- (void)stopWarningSound;

- (void)flashControllerIcon;
- (void)stopFlashingControllerIcon;

- (void)batteryWarning;
- (void)batteryEmergency;
- (void)stopBatteryAnimations;

- (void)setCompassAngle:(float)psi;
- (void)switchCompass;

@end
