//
//  Drone3GInstallerWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-25.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Drone3GProgressView.h"

@interface Drone3GInstallerWindowController : NSWindowController <NSWindowDelegate> {    
    NSInteger state;
    BOOL animating;
}

@property (assign) IBOutlet Drone3GProgressView* progressView;

@property (assign) IBOutlet NSProgressIndicator* spinner;
@property (assign) IBOutlet NSProgressIndicator* progressBar;

@property (assign) IBOutlet NSButton* nextButton;
@property (assign) IBOutlet NSButton* backButton;

@property (assign) IBOutlet NSView* textContainer;
@property (assign) IBOutlet NSTextView* textView;
@property (assign) IBOutlet NSScrollView* scrollView;

@property (assign) IBOutlet NSTextView* licenseTextView;
@property (assign) IBOutlet NSScrollView* licenseScrollView;

@property (assign) IBOutlet NSTextField* infoLabel;

@property (assign) IBOutlet NSView* introItemsView;
@property (assign) IBOutlet NSView* detailsSubView;
@property (assign) IBOutlet NSView* connectView;
@property (assign) IBOutlet NSView* loginView;
@property (assign) IBOutlet NSView* installView;
@property (assign) IBOutlet NSView* finishView;

+ (id)sharedInstaller;

- (IBAction)next:(id)sender;
- (IBAction)goBack:(id)sender;

- (IBAction)showLoginHelp:(id)sender;
- (IBAction)showConnectionHelp:(id)sender;

@end
