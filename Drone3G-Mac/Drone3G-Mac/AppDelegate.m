//
//  AppDelegate.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "AppDelegate.h"
#import "drone_main.h"

#import <pthread.h>
#import <SDL2/SDL.h>
#import <sys/time.h>

@implementation AppDelegate

@synthesize batteryAnimationsAreRunning;
@synthesize drone3GWindowController;

NSTimer* controllerFlashTimer = NULL;
NSTimer* batteryFlashTimer = NULL;
NSTimer* warningStopTimer = NULL;

NSSound* beep;

pthread_t drone3g_thread;

#pragma mark -
#pragma mark Delegate Methods
#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    drone3GWindowController = [[Drone3GWindowController alloc] init];
    
    beep = [NSSound soundNamed:@"beep.mp3"];
    [beep setLoops:YES];
    
    [_batteryLabel setHidden:YES];
    [_altitudeLabel setHidden:YES];
    [_timeFlyingLabel setHidden:YES];
    [_velocityLabel setHidden:YES];
    [_batteryImageView setHidden:YES];
    [_signalIconImageView setHidden:YES];
    [_signalLevelImageView setHidden:YES];
    [_controllerImageView setHidden:YES];
    
    [_controllerImageView setFrameOrigin:_signalIconImageView.frame.origin];
    
    // I like green for now
    [_batteryLabel setTextColor:[NSColor greenColor]];
    [_altitudeLabel setTextColor:[NSColor greenColor]];
    [_timeFlyingLabel setTextColor:[NSColor greenColor]];
    [_velocityLabel setTextColor:[NSColor greenColor]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adjustHUD:) name:NSWindowDidResizeNotification object:nil];
    [_window setDelegate:(id<NSWindowDelegate>)self];
    
    pthread_create(&drone3g_thread, NULL, drone3g_start, NULL);
}

- (BOOL)windowShouldClose:(id)sender {
    if(drone3g_allow_terminate == 1) {
        [NSApp terminate:self];
        return YES;
    } else {
        NSAlert* alert = [NSAlert alertWithMessageText:@"Drone not landed" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"Please land the drone before quitting."];
        [alert runModal];
        
        return NO;
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    pthread_cancel(drone3g_thread);
    drone3g_cleanup(0);
}

#pragma mark -
#pragma mark IBActions
#pragma mark -

- (IBAction)checkDataUsage:(id)sender {
    [drone3GWindowController showWindow:nil];
}

#pragma mark -
#pragma mark UI Handling
#pragma mark -

- (void)adjustHUD:(NSNotification*)notification {
    float scaleX = _window.frame.size.width / 1280.0f;
    float scaleY = _window.frame.size.height / 720.0f;
    float scale = sqrtf(scaleX*scaleX + scaleY*scaleY)*1.38f;
    
    [_connectionLabel setFont:[NSFont systemFontOfSize:17*scale]];
    [_batteryLabel setFont:[NSFont systemFontOfSize:12*scale]];
    [_altitudeLabel setFont:[NSFont systemFontOfSize:17*scale]];
    [_timeFlyingLabel setFont:[NSFont systemFontOfSize:20*scale]];
    [_velocityLabel setFont:[NSFont systemFontOfSize:15*scale]];
}

- (void)showHUD {
    [[_controllerImageView animator] setFrameOrigin:CGPointMake(51, 328)];
    
    [[_connectionLabel animator] setHidden:YES];
    [[_batteryLabel animator] setHidden:NO];
    [[_altitudeLabel animator] setHidden:NO];
    [[_timeFlyingLabel animator] setHidden:NO];
    [[_velocityLabel animator] setHidden:NO];
    [[_batteryImageView animator] setHidden:NO];
    [[_signalIconImageView animator] setHidden:NO];
    [[_signalLevelImageView animator] setHidden:NO];
    
    [_connectionLabel setStringValue:@"Connection lost awaiting reconnection..."];
}

- (void)showConnectionLabel {
    [_connectionLabel setHidden:NO];
    [_signalLevelImageView setHidden:YES];
}

- (void)hideConnectionLabel {
    [[_connectionLabel animator] setHidden:YES];
    [[_signalLevelImageView animator] setHidden:NO];
}

#pragma mark -
#pragma mark Warning Sound
#pragma mark -

- (void)playWarningSound {
    if([beep isPlaying]) {
        return;
    }
    
    [beep play];
}

- (void)stopWarningSound {
    [beep stop];
}

#pragma mark -
#pragma mark Controller Icon Animations
#pragma mark -

- (void)flashControllerIcon {
    controllerFlashTimer = [NSTimer scheduledTimerWithTimeInterval:0.44f target:self selector:@selector(changeControllerIconState) userInfo:nil repeats:YES];
    [self performSelector:@selector(playWarningSound) withObject:nil afterDelay:0.1f];
    [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(stopWarningSound) userInfo:nil repeats:NO];
}

- (void)stopFlashingControllerIcon {
    [self stopWarningSound];
    
    if(controllerFlashTimer != NULL) {
        [controllerFlashTimer invalidate];
    }
}

- (void)changeControllerIconState {
    [_controllerImageView setHidden:!_controllerImageView.isHidden];
}

#pragma mark -
#pragma mark Battery Icon Animations
#pragma mark -

- (void)batteryWarning {
    [self batteryEmergency];
    warningStopTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(stopbatteryAnimations) userInfo:nil repeats:NO];
}

- (void)stopbatteryAnimations {
    [self stopWarningSound];
    
    if(batteryFlashTimer != NULL) {
        [batteryFlashTimer invalidate];
    }
    if(warningStopTimer != NULL) {
        [warningStopTimer invalidate];
    }
    
    batteryAnimationsAreRunning = NO;
}

- (void)batteryEmergency {
    batteryAnimationsAreRunning = YES;
    
    batteryFlashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/2.0f target:self selector:@selector(changeBatteryIconState) userInfo:nil repeats:YES];
    [self playWarningSound];
}

- (void)changeBatteryIconState {
    [_batteryImageView setHidden:!_batteryImageView.isHidden];
    [_batteryLabel setHidden:!_batteryLabel.isHidden];
}

@end
