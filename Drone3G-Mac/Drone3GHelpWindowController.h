//
//  Drone3GHelpWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2015-01-07.
//  Copyright (c) 2015 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

enum {
    DRONE3G_HELP_CONTROLLER = 0,
    DRONE3G_HELP_PFWD,
    DRONE3G_HELP_CSETS,
    DRONE3G_HELP_PROXY,
    DRONE3G_HELP_USB,
    DRONE3G_HELP_MEDIA,
    DRONE3G_HELP_LOGIN,
    DRONE3G_HELP_CONNECTION
};

@interface Drone3GHelpWindowController : NSWindowController

@property (assign) IBOutlet NSToolbar* toolbar;

@property (assign) IBOutlet NSTextView* textView;
@property (assign) IBOutlet NSImageView* splashImage;

+ (id)sharedHelpController;

- (IBAction)showHelp:(id)sender;
- (void)switchHelp:(NSInteger)helpID;

@end
