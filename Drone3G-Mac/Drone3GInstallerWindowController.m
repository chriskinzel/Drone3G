//
//  Drone3GInstallerWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-25.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "Drone3GInstallerWindowController.h"
#import "Drone3GHelpWindowController.h"

#import "drone3g_installer.h"

enum {
    INSTALLER_STATE_INTRO = 0,
    INSTALLER_STATE_LICENSE,
    INSTALLER_STATE_ACCEPT,
    INSTALLER_STATE_CONNECT,
    INSTALLER_STATE_CREDS,
    INSTALLER_STATE_SYNC,
    INSTALLER_STATE_INSTALL,
    INSTALLER_STATE_FINISH
};

@interface Drone3GInstallerWindowController ()

@end

@implementation Drone3GInstallerWindowController

@synthesize infoLabel;
@synthesize progressView;
@synthesize nextButton;
@synthesize backButton;
@synthesize textView;
@synthesize licenseTextView;
@synthesize textContainer;
@synthesize introItemsView;
@synthesize detailsSubView;
@synthesize installView;
@synthesize connectView;
@synthesize loginView;
@synthesize finishView;
@synthesize spinner;
@synthesize progressBar;
@synthesize scrollView;
@synthesize licenseScrollView;

static void connection_success_callback() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Drone3GInstallerWindowController* installer = [Drone3GInstallerWindowController sharedInstaller];
        
        [[installer spinner] stopAnimation:nil];
        [[[installer connectView] viewWithTag:1] setHidden:NO];
        [[[installer connectView] viewWithTag:2] setImage:[NSImage imageNamed:@"connected.png"]];
        [[installer infoLabel] setStringValue:@"Connected to drone, ready to install."];
        [[installer nextButton] setEnabled:YES];
    });
}

static void install_complete_callback(int status) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Drone3GInstallerWindowController* installer = [Drone3GInstallerWindowController sharedInstaller];
        
        if(status == DRONE3G_INSTALL_SUCCESS) {
            [[installer infoLabel] setStringValue:@"The installation has completed successfully."];
            
            [[[installer finishView] viewWithTag:3] setImage:[NSImage imageNamed:@"install_done.png"]];
            [[[installer finishView] viewWithTag:2] setStringValue:@"The installation was successful."];
            
            [[[installer finishView] viewWithTag:1] setStringValue:@"Your drone is now rebooting.\n\nAfter rebooting, plug in your USB modem, reboot again and it will be ready to fly.\n\nYou may need to set your carrier settings manually in preferences."];
            
            [[NSSound soundNamed:@"burn complete.aif"] play];
        } else {
            [[installer infoLabel] setStringValue:@"An error occured during install."];

            [[[installer finishView] viewWithTag:3] setImage:[NSImage imageNamed:NSImageNameCaution]];
            [[[installer finishView] viewWithTag:2] setStringValue:@"The installation failed."];
            
            if(status == DRONE3G_INSTALL_LOST_CONNECTION) {
                [[[installer finishView] viewWithTag:1] setStringValue:@"Connection to the drone was lost during install.\n\nMake sure your drone is nearby and connected while installing."];
            } else if(status == DRONE3G_INSTALL_DRONE_FAILED) {
                [[[installer finishView] viewWithTag:1] setStringValue:@"An error occured while installing the drone.\nPlease reboot your drone and try again."];
            } else if(status == DRONE3G_INSTALL_ALREADY) {
                [[[installer finishView] viewWithTag:1] setStringValue:@"Drone3G is already installed on this drone.\n\nIf you want to reinstall Drone3G first run the uninstaller."];
            }
            
            [[NSSound soundNamed:@"Basso"] play];
        }
        
        [installer next:nil];
    });
}

static void install_progress_update(int progress) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Drone3GInstallerWindowController* installer = [Drone3GInstallerWindowController sharedInstaller];
        
        [[installer progressBar] setIndeterminate:NO];
        [[installer progressBar] setDoubleValue:(double)progress];
        
        if(progress == 0) {
            [[installer progressBar] setIndeterminate:YES];
            [[installer progressBar] startAnimation:nil];
            
            [[[installer installView] viewWithTag:1] setStringValue:@"Installation failed cleaning up..."];
        }
        
        if(progress > 38 && progress < 100) {
            [[[installer installView] viewWithTag:1] setStringValue:@"Uploading Drone3G software..."];
        }
        if(progress == 100) {
            [[[installer installView] viewWithTag:1] setStringValue:@"Installation complete."];
        }
    });
}

+ (id)sharedInstaller {
    static Drone3GInstallerWindowController* sharedInstaller = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedInstaller = [[self alloc] init];
    });
    
    return sharedInstaller;
}

- (id)init {
    self = [super initWithWindowNibName:@"Installer"];
    if(self) {
        // Loads the window so that it's possible check if it's visible right away
        [[self window] setIsVisible:NO];
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    [self resetInstaller];
    
    NSString* eulaPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Resources/Drone3G EULA.rtf"];
    [licenseTextView readRTFDFromFile:eulaPath];
    
    NSString* installIntroPath = [[eulaPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Install-intro.rtfd"];
    [textView readRTFDFromFile:installIntroPath];
    
    [introItemsView removeFromSuperview];
    [[scrollView documentView] addSubview:introItemsView];
    [[scrollView documentView] setFrameSize:NSMakeSize([[scrollView documentView] frame].size.width, [[scrollView documentView] frame].size.height+115)];
    [introItemsView setFrameOrigin:NSMakePoint(introItemsView.frame.origin.x, 420)];
    
    // Get scroll view to post changes to scrolling position so that continue button is only enabled after scrolling to bottom
    [[scrollView contentView] setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(boundsDidChangeNotification:) name:NSViewBoundsDidChangeNotification object:[scrollView contentView]];
}

- (void)showWindow:(id)sender {
    [[self window] center];
    
    if(![[self window] isVisible]) {
        [self resetInstaller];
        [nextButton setEnabled:NO];
    }
    
    [super showWindow:sender];
}

#pragma mark -
#pragma mark Window Animation
#pragma mark -

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
    animating = !flag;
}

- (void)shakeWindow {
    if(animating) {
        return;
    }
    
    static int numberOfShakes = 3;
    static float durationOfShake = 0.5f;
    static float vigourOfShake = 0.05f;
    
    CGRect frame=[self.window frame];
    CAKeyframeAnimation *shakeAnimation = [CAKeyframeAnimation animation];
    
    [shakeAnimation setDelegate:self];
    
    CGMutablePathRef shakePath = CGPathCreateMutable();
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (NSInteger index = 0; index < numberOfShakes; index++){
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake, NSMinY(frame));
    }
    CGPathCloseSubpath(shakePath);
    shakeAnimation.path = shakePath;
    shakeAnimation.duration = durationOfShake;
    
    animating = YES;
    
    [self.window setAnimations:[NSDictionary dictionaryWithObject: shakeAnimation forKey:@"frameOrigin"]];
    [[self.window animator] setFrameOrigin:[self.window frame].origin];
}

#pragma mark -
#pragma mark IBActions
#pragma mark -

- (IBAction)next:(id)sender {
    state++;
    [self updateUIState];
    
    [progressView setProgressState:(state < INSTALLER_STATE_ACCEPT) ? state : ( (state < INSTALLER_STATE_SYNC) ? state-1 : state-2) ];
}

- (IBAction)goBack:(id)sender {
    if(state == INSTALLER_STATE_CONNECT) {
        state = INSTALLER_STATE_ACCEPT;
    }
    
    if(state == INSTALLER_STATE_CREDS) {
        drone3g_installer_stop_connecting();
        [[connectView viewWithTag:2] setImage:[NSImage imageNamed:@"wifi_icon.png"]];
    }
    
    state--;
    [self updateUIState];
    
    [progressView setProgressState:(state < INSTALLER_STATE_ACCEPT) ? state : ( (state < INSTALLER_STATE_SYNC) ? state-1 : state-2) ];
}

#pragma mark -

- (IBAction)showLoginHelp:(id)sender {
    [[Drone3GHelpWindowController sharedHelpController] switchHelp:DRONE3G_HELP_LOGIN];
}

- (IBAction)showConnectionHelp:(id)sender {
    [[Drone3GHelpWindowController sharedHelpController] switchHelp:DRONE3G_HELP_CONNECTION];
}

#pragma mark -
#pragma mark Delegate
#pragma mark -

- (void)windowWillClose:(NSNotification *)notification {
    drone3g_installer_stop_connecting();
}

#pragma mark -
#pragma mark Installer Methods
#pragma mark -

// This makes sure the user has scrolled to the bottom and read the intro text
- (void)boundsDidChangeNotification:(NSNotification*)notification {
    if(state != INSTALLER_STATE_INTRO) {
        return;
    }
    
    // Check if scrolled to bottom
    CGFloat currentPosition  = [[scrollView contentView] bounds].origin.y;
    CGFloat contentHeight    = [textView bounds].size.height;
    CGFloat boundingHeight   = [[scrollView contentView] bounds].size.height;
    
    if(contentHeight - currentPosition <= boundingHeight*1.35f) {
        [nextButton setEnabled:YES];
    }
}

- (void)updateUIState {
    switch (state) {
        case INSTALLER_STATE_INTRO:
            [self resetInstaller];
            [[licenseScrollView contentView] scrollToPoint:NSMakePoint(0, 0)];
            
            break;
            
        case INSTALLER_STATE_LICENSE:
            drone3g_installer_stop_connecting();
            
            [[connectView viewWithTag:2] setImage:[NSImage imageNamed:@"wifi_icon.png"]];
            [connectView removeFromSuperview];
            
            [infoLabel setStringValue:@"Software License Agreement."];
            
            [backButton setEnabled:YES];
            [nextButton setEnabled:YES];
            [nextButton setTitle:@"I Agree"];
            
            [textView setHidden:YES];
            
            [textContainer addSubview:detailsSubView];
           
            break;
            
        case INSTALLER_STATE_ACCEPT:
            [self popAgreeSheet];
            
            break;
            
        case INSTALLER_STATE_CONNECT:
            drone3g_installer_connect(DRONE3G_CONNECT_TYPE_INSTALL, &connection_success_callback);
            
            [[licenseScrollView contentView] scrollToPoint:NSMakePoint(0, 0)];
            
            [[connectView viewWithTag:1] setHidden:YES];
            
            [infoLabel setStringValue:@"Waiting for wifi connection to drone..."];
            
            [nextButton setTitle:@"Continue"];
            [nextButton setEnabled:NO];
            
            [detailsSubView removeFromSuperview];
            
            [textContainer addSubview:connectView];
            
            [spinner startAnimation:nil];
                                                
            break;
            
        case INSTALLER_STATE_CREDS:
            [connectView removeFromSuperview];
            
            [infoLabel setStringValue:@"Choose a username and password for your drone."];
            
            [textContainer addSubview:loginView];
            
            break;
            
        case INSTALLER_STATE_SYNC: {
            // Check to make sure credentials support UTF8 encoding
            NSString* username  = [[loginView viewWithTag:1] stringValue];
            NSString* password  = [[loginView viewWithTag:2] stringValue];
            NSString* droneName = [[loginView viewWithTag:3] stringValue];
            
            if(![username canBeConvertedToEncoding:NSUTF8StringEncoding] || ![password canBeConvertedToEncoding:NSUTF8StringEncoding] || ![droneName canBeConvertedToEncoding:NSUTF8StringEncoding]) {
                [self shakeWindow];
                [[NSSound soundNamed:@"Basso"] play];
                
                state = INSTALLER_STATE_CREDS;
                
                break;
            }
            
            int ret = drone3g_set_credentials_pre_install([username UTF8String], [password UTF8String], [droneName UTF8String]);
            if(ret < 0) {
                [self shakeWindow];
                [[NSSound soundNamed:@"Basso"] play];
                
                state = INSTALLER_STATE_CREDS;
                
                break;
            }
            
            [self next:nil];
            
            break;
        }
            
        case INSTALLER_STATE_INSTALL:
            [loginView removeFromSuperview];
            
            [[installView viewWithTag:1] setStringValue:@"Preparing filesystem..."];
            [[installView viewWithTag:2] setStringValue:@"Do not disconnect or unplug the drone while installing."];
            
            [infoLabel setStringValue:@"Installing Drone3G..."];
            
            [backButton setEnabled:NO];
            [nextButton setEnabled:NO];
            
            [progressBar startAnimation:nil];
            
            [textContainer addSubview:installView];
            
            [[[self window] standardWindowButton:NSWindowCloseButton] setEnabled:NO];
            
            drone3g_installer_install(&install_complete_callback, &install_progress_update);
            
            break;
            
        case INSTALLER_STATE_FINISH:
            [installView removeFromSuperview];
            
            [textView setHidden:YES];
            [textContainer addSubview:finishView];
            
            [nextButton setEnabled:YES];
            [nextButton setTitle:@"Close"];
            [nextButton setKeyEquivalent:@"\r"];
            
            [[[self window] standardWindowButton:NSWindowCloseButton] setEnabled:YES];
            
            break;
            
        default:
            [[self window] close];
            break;
    }
}

- (void)popAgreeSheet {
    [[NSAlert alertWithMessageText:@"To continue installing Drone3G, you must agree to the terms and conditions of this software license agreement." defaultButton:@"I Agree" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"Click Agree to continue or click Cancel to go back."] beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse returnCode){
        if(returnCode == 1) {
            [self next:nil];
        } else {
            state = INSTALLER_STATE_LICENSE;
        }
    }];
}

- (void)resetInstaller {
    drone3g_installer_stop_connecting();
        
    [finishView removeFromSuperview];
    [detailsSubView removeFromSuperview];
    [connectView removeFromSuperview];
    [installView removeFromSuperview];
    [loginView removeFromSuperview];
    
    [[connectView viewWithTag:2] setImage:[NSImage imageNamed:@"wifi_icon.png"]];
    
    [infoLabel setTextColor:[NSColor blackColor]];
    [infoLabel setStringValue:@"Welcome to the Drone3G installer"];
    
    [textView setHidden:NO];
    
    [backButton setEnabled:NO];
    [nextButton setEnabled:YES];
    [nextButton setTitle:@"Continue"];
    [nextButton setKeyEquivalent:@""];
    [[self window] setDefaultButtonCell:nil];
    
    state = INSTALLER_STATE_INTRO;
    
    [textContainer setWantsLayer:YES];
    [[textContainer layer] setBackgroundColor:[[[NSColor whiteColor] colorWithAlphaComponent:0.4f] CGColor]];
    
    [[scrollView contentView] scrollToPoint:NSMakePoint(0, 0)];
    
    [progressView resetProgress];
    
    [progressBar setIndeterminate:YES];
}

@end
