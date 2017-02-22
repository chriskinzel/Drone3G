//
//  Drone3GUninstallerWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-29.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GUninstallerWindowController.h"
#import "drone3g_installer.h"

enum {
    UNINSTALLER_STATE_INTRO = 0,
    UNINSTALLER_STATE_CONNECT,
    UNINSTALLER_STATE_UNINSTALL,
    UNINSTALLER_STATE_FINISH
};

@interface Drone3GUninstallerWindowController ()

@end

@implementation Drone3GUninstallerWindowController

@synthesize infoLabel;
@synthesize progressView;
@synthesize nextButton;
@synthesize backButton;
@synthesize textView;
@synthesize textContainer;
@synthesize uninstallView;
@synthesize connectView;
@synthesize finishView;
@synthesize spinner;
@synthesize progressBar;

static void connection_success_callback() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Drone3GUninstallerWindowController* uninstaller = [Drone3GUninstallerWindowController sharedUninstaller];
        
        [[uninstaller spinner] stopAnimation:nil];
        [[[uninstaller connectView] viewWithTag:1] setHidden:NO];
        [[[uninstaller connectView] viewWithTag:2] setImage:[NSImage imageNamed:@"connected.png"]];
        [[uninstaller infoLabel] setStringValue:@"Connected to drone, ready to uninstall."];
        [[uninstaller nextButton] setEnabled:YES];
    });
}

static void uninstall_complete_callback(int status) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Drone3GUninstallerWindowController* uninstaller = [Drone3GUninstallerWindowController sharedUninstaller];
        
        if(status == DRONE3G_UNINSTALL_SUCCESS) {
            [[uninstaller infoLabel] setStringValue:@"The uninstall has completed successfully."];
            
            [[[uninstaller finishView] viewWithTag:3] setImage:[NSImage imageNamed:@"install_done.png"]];
            [[[uninstaller finishView] viewWithTag:2] setStringValue:@"The uninstall was successful."];
            
            [[[uninstaller finishView] viewWithTag:1] setStringValue:@"Drone3G has been removed from your drone."];
            
            [[NSSound soundNamed:@"burn complete.aif"] play];
        } else {
            [[uninstaller infoLabel] setStringValue:@"An error occured during uninstall."];
            
            [[[uninstaller finishView] viewWithTag:3] setImage:[NSImage imageNamed:NSImageNameCaution]];
            [[[uninstaller finishView] viewWithTag:2] setStringValue:@"The uninstall failed."];
            
            if(status == DRONE3G_UNINSTALL_LOST_CONNECTION) {
                [[[uninstaller finishView] viewWithTag:1] setStringValue:@"Connection to the drone was lost during uninstall.\n\nMake sure your drone is nearby while uninstalling."];
            } else if(status == DRONE3G_UNINSTALL_FAILED) {
                [[[uninstaller finishView] viewWithTag:1] setStringValue:@"An error occured while uninstalling the drone.\n\nTry running the uninstaller again."];
            } else {
                [[[uninstaller finishView] viewWithTag:1] setStringValue:@"It appears that Drone3G is not installed on this drone."];
            }
            
            [[NSSound soundNamed:@"Basso"] play];
        }
        
        [uninstaller next:nil];
    });
}

static void uninstall_progress_update(int progress) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Drone3GUninstallerWindowController* uninstaller = [Drone3GUninstallerWindowController sharedUninstaller];
        
        [[uninstaller progressBar] setIndeterminate:NO];
        [[uninstaller progressBar] setDoubleValue:(double)progress];
        
        if(progress > 0 && progress < 85) {
            [[[uninstaller uninstallView] viewWithTag:1] setStringValue:@"Removing Drone3G..."];
        } else if(progress >= 85 && progress < 100) {
            [[[uninstaller uninstallView] viewWithTag:1] setStringValue:@"Restoring drone to original state..."];
        } else if(progress == 100) {
            [[[uninstaller uninstallView] viewWithTag:1] setStringValue:@"Uninstall Complete."];
        }
    });
}

+ (id)sharedUninstaller {
    static Drone3GUninstallerWindowController* sharedUninstaller = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedUninstaller = [[self alloc] init];
    });
    
    return sharedUninstaller;
}

- (id)init {
    self = [super initWithWindowNibName:@"Uninstaller"];
    if(self) {
        // Loads the window so that it's possible check if it's visible right away
        [[self window] setIsVisible:NO];
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    [self resetUninstaller];
    
    NSString* uninstallIntroPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Resources/Uninstall-intro.rtfd"];
    [textView readRTFDFromFile:uninstallIntroPath];
}

- (void)showWindow:(id)sender {
    [[self window] center];

    if(![[self window] isVisible]) {
        [self resetUninstaller];
    }
    
    [super showWindow:sender];
}

#pragma mark -
#pragma mark IBActions
#pragma mark -

- (IBAction)next:(id)sender {
    state++;
    [self updateUIState];
    
    [progressView setProgressState:state];
}

- (IBAction)goBack:(id)sender {
    state--;
    [self updateUIState];
    
    [progressView setProgressState:state];
}

#pragma mark -
#pragma mark Delegate
#pragma mark -

- (void)windowWillClose:(NSNotification *)notification {
    drone3g_installer_stop_connecting();
}

#pragma mark -
#pragma mark Uninstaller Methods
#pragma mark -

- (void)updateUIState {
    switch (state) {
        case UNINSTALLER_STATE_INTRO:
            [self resetUninstaller];
            break;
            
        case UNINSTALLER_STATE_CONNECT:
            drone3g_installer_connect(DRONE3G_CONNECT_TYPE_UNINSTALL, &connection_success_callback);
            
            [textView setHidden:YES];
            
            [[connectView viewWithTag:1] setHidden:YES];
            
            [infoLabel setTextColor:[NSColor blackColor]];
            [infoLabel setStringValue:@"Waiting for wifi connection to drone..."];
            
            [backButton setEnabled:YES];
            [nextButton setEnabled:NO];
            
            [textContainer addSubview:connectView];
            
            [spinner startAnimation:nil];
            
            break;
            
        case UNINSTALLER_STATE_UNINSTALL:
            [connectView removeFromSuperview];
            
            [[uninstallView viewWithTag:1] setStringValue:@"Preparing Uninstallation..."];
            [[uninstallView viewWithTag:2] setStringValue:@"Do not disconnect or unplug the drone while uninstalling."];
            
            [infoLabel setStringValue:@"Uninstalling Drone3G..."];
            
            [backButton setEnabled:NO];
            [nextButton setEnabled:NO];
            
            [progressBar startAnimation:nil];
            
            [textContainer addSubview:uninstallView];
            
            [[[self window] standardWindowButton:NSWindowCloseButton] setEnabled:NO];
            
            drone3g_installer_uninstall(&uninstall_complete_callback, &uninstall_progress_update);
            
            break;
            
        case UNINSTALLER_STATE_FINISH:
            [uninstallView removeFromSuperview];
            
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

- (void)resetUninstaller {    
    drone3g_installer_stop_connecting();
    
    [[connectView viewWithTag:2] setImage:[NSImage imageNamed:@"wifi_icon.png"]];
    [connectView removeFromSuperview];
    
    [finishView removeFromSuperview];
    [connectView removeFromSuperview];
    [uninstallView removeFromSuperview];
    
    [[connectView viewWithTag:2] setImage:[NSImage imageNamed:@"wifi_icon.png"]];
    
    [infoLabel setTextColor:[NSColor blackColor]];
    [infoLabel setStringValue:@"Welcome to the Drone3G uninstaller"];
    
    [textView setHidden:NO];
    
    [backButton setEnabled:NO];
    [nextButton setEnabled:YES];
    [nextButton setTitle:@"Continue"];
    [nextButton setKeyEquivalent:@""];
    [[self window] setDefaultButtonCell:nil];
    
    state = UNINSTALLER_STATE_INTRO;
    
    [textContainer setWantsLayer:YES];
    [[textContainer layer] setBackgroundColor:[[[NSColor whiteColor] colorWithAlphaComponent:0.4f] CGColor]];
    
    [progressView resetProgress];
    
    [progressBar setIndeterminate:YES];
}

@end
