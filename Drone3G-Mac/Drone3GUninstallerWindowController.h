//
//  Drone3GUninstallerWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-29.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Drone3GProgressView.h"

@interface Drone3GUninstallerWindowController : NSWindowController {
    NSInteger state;
}

@property (assign) IBOutlet Drone3GProgressView* progressView;

@property (assign) IBOutlet NSProgressIndicator* spinner;
@property (assign) IBOutlet NSProgressIndicator* progressBar;

@property (assign) IBOutlet NSButton* nextButton;
@property (assign) IBOutlet NSButton* backButton;

@property (assign) IBOutlet NSView* textContainer;
@property (assign) IBOutlet NSTextView* textView;

@property (assign) IBOutlet NSTextField* infoLabel;

@property (assign) IBOutlet NSView* connectView;
@property (assign) IBOutlet NSView* uninstallView;
@property (assign) IBOutlet NSView* finishView;


+ (id)sharedUninstaller;

- (IBAction)next:(id)sender;
- (IBAction)goBack:(id)sender;

@end
