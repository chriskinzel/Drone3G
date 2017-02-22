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
#import "Drone3GPhotosWindowController.h"
#import "Drone3GInstallerWindowController.h"
#import "Drone3GUninstallerWindowController.h"
#import "Drone3GHelpWindowController.h"

#import "Drone3GWindow.h"
#import "Drone3GMenu.h"
#import "Drone3GLoginView.h"
#import "Drone3GHUD.h"
#import "Drone3GProgressIndicator.h"
#import "Drone3GCheckBox.h"

#import "Drone3GTipGenerator.h"

@interface Drone3GAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSSpeechSynthesizerDelegate> {
    Drone3GWindow* overlayWindow;
    
    NSSpeechSynthesizer* alertSpeaker;
    
    Drone3GDATWindowController* drone3GDatWindowController;
    Drone3GPREFWindowController* drone3GPrefWindowController;
    Drone3GPLANWindowController* drone3GPlanWindowController;
    Drone3GPhotosWindowController* drone3GPhotosWindowController;
    Drone3GInstallerWindowController* drone3GInstaller;
    Drone3GUninstallerWindowController* drone3GUninstaller;
    Drone3GHelpWindowController* drone3GHelp;
    
    Drone3GTipGenerator* drone3GTipGenerator;
    
    BOOL batteryAnimationsAreRunning;
    BOOL batteryAnimationsAreWaiting;
    BOOL firstSpeechDonePlaying;
    BOOL warningLabelIsAnimating;
    
    BOOL actingAsProxy;
    BOOL showHUDCalled;
    BOOL joystickDidConnect;
    
    NSTimer* controllerFlashTimer;
    NSTimer* batteryFlashTimer;
    NSTimer* warningStopTimer;
    NSTimer* labelFlashTimer;
    NSTimer* recordFlashTimer;
    
    NSSound* beep;
        
    float homeAngle;
}

@property (strong) NSSpeechSynthesizer* alertSpeaker;

@property (readonly) BOOL batteryAnimationsAreRunning;
@property (readonly) BOOL warningLabelIsAnimating;
@property (assign)   BOOL joystickDidConnect;

@property (assign) IBOutlet NSWindow *window;

@property (assign) IBOutlet Drone3GGLView* drone3GGLView;
@property (assign) IBOutlet Drone3GMenu* mainView;
@property (assign) IBOutlet Drone3GHUD* HUDView;
@property (assign) IBOutlet Drone3GLoginView* loginView;

@property (assign) IBOutlet Drone3GProgressIndicator* spinnerView;
@property (assign) IBOutlet Drone3GCheckBox* proxyCheckBox;

@property (assign) IBOutlet NSTextView* proxyLogView;

@property (assign) IBOutlet NSTextField* connectionLabel;
@property (assign) IBOutlet NSTextField* tipLabel;
@property (assign) IBOutlet NSTextField* warningLabel;
@property (assign) IBOutlet NSTextField* batteryLabel;
@property (assign) IBOutlet NSTextField* altitudeLabel;
@property (assign) IBOutlet NSTextField* velocityLabel;
@property (assign) IBOutlet NSTextField* timeFlyingLabel;
@property (assign) IBOutlet NSTextField* gpsLabel;
@property (assign) IBOutlet NSTextField* distanceLabel;
@property (assign) IBOutlet NSTextField* windSpeedLabel;

@property (assign) IBOutlet NSImageView* batteryImageView;
@property (assign) IBOutlet NSImageView* signalIconImageView;
@property (assign) IBOutlet NSImageView* signalLevelImageView;
@property (assign) IBOutlet NSImageView* controllerImageView;
@property (assign) IBOutlet NSImageView* recordingIndicator;

@property (assign) IBOutlet NSMenuItem* dataUsageMenuItem;
@property (assign) IBOutlet NSMenuItem* flightPlanMenuItem;

@property (assign) IBOutlet NSTextField* directionLabel;
@property (assign) IBOutlet NSTextField* angleLabel;

@property (assign) IBOutlet NSImageView* homeImage;
@property (assign) IBOutlet NSTextField* homeAngleLabel;

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
@property (assign) IBOutlet NSMenuItem* recordMenuItem;
@property (assign) IBOutlet NSTextField* bitrateLabel;
@property (assign) IBOutlet NSView* bitrateSlider;

@property (assign) IBOutlet NSMenuItem* sensitivityMenuItem;
@property (assign) IBOutlet NSView* sensitivityView;

@property (assign) IBOutlet NSButton* helpButton;

- (void)menuButtonPushed:(int)identifier;
- (void)menuDidFinishAnimatingOut;
- (void)menuWillAnimateIn;

- (IBAction)openPreferences:(id)sender;
- (IBAction)checkDataUsage:(id)sender;
- (IBAction)openFlightPlanner:(id)sender;
- (IBAction)openHelp:(id)sender;

- (IBAction)use720pVideo:(id)sender;
- (IBAction)use360pVideo:(id)sender;
- (IBAction)changeBitrate:(id)sender;

- (IBAction)sensitivitySliderDidChange:(id)sender;
- (IBAction)restoreDefaultSensitivities:(id)sender;

- (IBAction)showPhotos:(id)sender;
- (IBAction)changeRecordingMode:(id)sender;

- (IBAction)showExportHelp:(id)sender;
- (IBAction)showProxyHelp:(id)sender;
- (IBAction)showControllerHelp:(id)sender;

- (void)changeInclinometerState:(BOOL)visibillity;
- (void)updateInclinometer:(float)pitch roll:(float)roll;

- (void)changeHUDColor:(NSColor*)color;
- (void)showHUD;
- (void)showConnectionLabel;
- (void)hideConnectionLabel;

- (void)playGPSAlertSound;
- (void)playWarningSound;
- (void)stopWarningSound;

- (void)flashControllerIcon;
- (void)stopFlashingControllerIcon;

- (void)flashRecordingIndicator;
- (void)stopFlashingRecordIndicator;

- (void)batteryWarning;
- (void)batteryEmergency;
- (void)stopBatteryAnimations;

- (void)flashWarningLabel;
- (void)stopFlashingWarningLabel;

- (void)setCompassAngle:(float)psi;
- (void)positionHomeImage:(float)psi;
- (void)switchCompass;

@end
