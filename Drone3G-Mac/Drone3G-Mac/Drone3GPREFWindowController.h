//
//  Drone3GPREFWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-14.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Drone3GAppDelegate;

@interface Drone3GPREFWindowController : NSWindowController <NSWindowDelegate> {
    NSUserDefaults* preferences;
    
    Drone3GAppDelegate* appDelegate;
    NSView* currentView;
}

@property (assign) IBOutlet NSToolbar* toolbar;
@property (assign) IBOutlet NSView* mainView; // We use a seperate custom view rather than the windows content view since the backing CALayer set on the
                                              // contentView screws up the toolbar

@property (assign) IBOutlet NSTextField* warningLabel;

@property (assign) IBOutlet NSView* controllerView;
@property (assign) IBOutlet NSView* hudView;
@property (assign) IBOutlet NSView* flyHomeView;

- (IBAction)switchView:(id)sender;

#pragma mark -
#pragma mark Controller View
#pragma mark -

- (IBAction)sliderDidChange:(id)sender;
- (IBAction)resetDefaultSliders:(id)sender;

- (IBAction)comboBoxDidChange:(id)sender;
- (IBAction)resetDefaultController:(id)sender;

- (void)saveSensitivities;

@end
