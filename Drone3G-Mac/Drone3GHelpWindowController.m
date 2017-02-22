//
//  Drone3GHelpWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2015-01-07.
//  Copyright (c) 2015 Chris Kinzel. All rights reserved.
//

#import "Drone3GHelpWindowController.h"

@interface Drone3GHelpWindowController ()

@end

@implementation Drone3GHelpWindowController

@synthesize textView;
@synthesize splashImage;
@synthesize toolbar;

+ (id)sharedHelpController {
    static Drone3GHelpWindowController* sharedHelp = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedHelp = [[self alloc] init];
    });
    
    return sharedHelp;
}

- (id)init {
    self = [super initWithWindowNibName:@"HelpWindow"];
    if(self) {
        [[self window] setIsVisible:NO];
    }
    
    return self;
}

- (void)showWindow:(id)sender {
    [splashImage setHidden:YES];
    
    NSString* helpTextPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Resources/Drone3G-Help.rtfd"];
    [textView readRTFDFromFile:helpTextPath];
    
    [[self window] center];
    [super showWindow:sender];
}

- (IBAction)showHelp:(id)sender {
    [self switchHelp:[sender tag]-1];
}

- (void)switchHelp:(NSInteger)helpID {
    // Reset scroll position
    NSScrollView* scrollView = (NSScrollView*)[[textView superview] superview];
    [[scrollView contentView] scrollToPoint:NSMakePoint(0, 0)];
    
    NSString* resourcePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Resources/*-Help.rtfd"];
    
    switch (helpID) {
        case DRONE3G_HELP_CONTROLLER:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Controller"];
            [splashImage setHidden:NO];
            
            break;
            
        case DRONE3G_HELP_PFWD:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Forwarding"];
            break;
            
        case DRONE3G_HELP_CSETS:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Carrier"];
            break;
            
        case DRONE3G_HELP_USB:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Modem"];
            break;
            
        case DRONE3G_HELP_LOGIN:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Login"];
            break;
            
        case DRONE3G_HELP_PROXY:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Proxy"];
            break;
            
        case DRONE3G_HELP_MEDIA:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Media"];
            break;
            
        case DRONE3G_HELP_CONNECTION:
            resourcePath = [resourcePath stringByReplacingOccurrencesOfString:@"*" withString:@"Connection"];
            break;
            
        default:
            break;
    }
    
    [textView readRTFDFromFile:resourcePath];
    
    // If this functions is called from externally we may need to show the window
    if(![[self window] isVisible]) {
        // Select the proper toolbar item
        for(NSToolbarItem* item in [toolbar items]) {
            if([item tag]-1 == helpID) {
                [toolbar setSelectedItemIdentifier:[item itemIdentifier]];
                break;
            }
        }
        
        [[self window] center];
        [super showWindow:self];
    }
}

@end
