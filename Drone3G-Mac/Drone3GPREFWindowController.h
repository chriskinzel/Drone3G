//
//  Drone3GPREFWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-14.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

enum {
    DRONE3G_CLMODE_LAND = 0,
    DRONE3G_CLMODE_FLYHOME
};

@class Drone3GAppDelegate;

@interface Drone3GPREFWindowController : NSWindowController <NSWindowDelegate> {
    NSUserDefaults* preferences;
    
    Drone3GAppDelegate* appDelegate;
    NSView* currentView;
    
    BOOL animating;
    
    unsigned int connectionLostMode;
    
    unsigned int landTimeout; // In seconds
    unsigned int flyHomeTimeout; // In seconds
    unsigned int flyHomeAltitude; // In mm
}

@property (assign) IBOutlet NSToolbar* toolbar;
@property (assign) IBOutlet NSView* mainView; // We use a seperate custom view rather than the windows content view since the backing CALayer set on the
                                              // contentView screws up the toolbar

@property (assign) IBOutlet NSTextField* warningLabel;

@property (assign) IBOutlet NSImageView* hudImageView;

@property (assign) IBOutlet NSView* controllerView;
@property (assign) IBOutlet NSView* hudView;
@property (assign) IBOutlet NSView* flyHomeView;
@property (assign) IBOutlet NSView* carrierView;
@property (assign) IBOutlet NSView* loginView;

@property (readonly) unsigned int connectionLostMode;
@property (readonly) unsigned int landTimeout;
@property (readonly) unsigned int flyHomeTimeout;
@property (readonly) unsigned int flyHomeAltitude;

+ (id)sharedPreferencesController;

- (IBAction)switchView:(id)sender;


#pragma mark -
#pragma mark Controller View
#pragma mark -

- (IBAction)showControllerHelp:(id)sender;
- (IBAction)showCarrierHelp:(id)sender;
- (IBAction)showLoginHelp:(id)sender;

- (IBAction)sliderDidChange:(id)sender;
- (IBAction)resetDefaultSliders:(id)sender;

- (IBAction)comboBoxDidChange:(id)sender;
- (IBAction)resetDefaultController:(id)sender;

- (void)saveSensitivities;

#pragma mark -
#pragma mark HUD View
#pragma mark -

- (IBAction)inclinometerStateDidChange:(id)sender;
- (IBAction)colorSelected:(id)sender;
- (IBAction)unitsDidChange:(id)sender;

- (NSString*)altitudeUnits;
- (NSString*)speedUnits;
- (NSString*)distanceUnits;

- (NSColor*)currentHUDColor;
- (BOOL)shouldRenderInclinometer;

#pragma mark -
#pragma mark Fly Home View
#pragma mark -

- (IBAction)modeDidChange:(id)sender;

- (IBAction)landTimeoutDidChange:(id)sender;
- (IBAction)flyHomeTimeoutDidChange:(id)sender;
- (IBAction)flyHomeAltitudeDidChange:(id)sender;

- (void)enableFlyHome;
- (void)disableFlyHome;

#pragma mark -
#pragma mark Carrier View
#pragma mark -

- (IBAction)changeCarrierSettingsMode:(id)sender;
- (IBAction)sync:(id)sender;

#pragma mark -
#pragma mark Login view
#pragma mark -

- (IBAction)sendCredentials:(id)sender;

#pragma mark -
#pragma mark Media Removal Supression 
#pragma mark -

- (void)setMediaRemovalWarning:(BOOL)suppression;
- (BOOL)shouldSuppressMediaRemovalWarning;

@end
