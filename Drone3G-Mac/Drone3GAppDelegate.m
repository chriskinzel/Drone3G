//
//  AppDelegate.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GAppDelegate.h"

#import "drone_main.h"
#import "drone_com.h"

#import <pthread.h>
#import <SDL2/SDL.h>
#import <sys/time.h>

#define DRONE3G_BATTERY_WARNING 0
#define DRONE3G_BATTERY_EMERGENCY 1

@implementation Drone3GAppDelegate

@synthesize batteryAnimationsAreRunning;
@synthesize drone3GDatWindowController;
@synthesize drone3GPrefWindowController;
@synthesize drone3GPlanWindowController;

#pragma mark -
#pragma mark Delegate Methods
#pragma mark -

- (void)awakeFromNib {
    controllerFlashTimer = NULL;
    batteryFlashTimer = NULL;
    warningStopTimer = NULL;
    
    alertSpeaker = [[NSSpeechSynthesizer alloc] initWithVoice:@"com.apple.speech.synthesis.voice.Alex"];
    [alertSpeaker setRate:240.0f];
    [alertSpeaker setDelegate:self];
    
    [_sliderMenuItem setView:_bitrateSlider];
    [_bitrateMenuItem setView:_bitrateLabel];
    [_sensitivityMenuItem setView:_sensitivityView];
    
    drone3GDatWindowController = [[Drone3GDATWindowController alloc] init];
    drone3GPrefWindowController = [[Drone3GPREFWindowController alloc] init];
    drone3GPlanWindowController = [[Drone3GPLANWindowController alloc] init];
    
    beep = [NSSound soundNamed:@"beep2.mp3"];
    [beep setLoops:YES];
    
    // Sometimes NSSound lags on first play so this gets that out of the way (cache issue probably)
    [beep play];
    [beep stop];
    
    [_controllerImageView setFrameOrigin:_signalIconImageView.frame.origin];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adjustHUD:) name:NSWindowDidResizeNotification object:nil];
    [_window setDelegate:(id<NSWindowDelegate>)self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    pthread_create(&drone3g_thread, NULL, drone3g_start, NULL);
    //[self performSelectorInBackground:@selector(test) withObject:nil];
}

/*- (void)test {
    sleep(5);
    dispatch_async(dispatch_get_main_queue(), ^{
       [drone3GPlanWindowController setHomeLocation:50.889174 longitude:-114.08280];
    });
    
    double velx = 0.0;
    double vely = 0.0;
    
    float angle = 0.0f;
    float target_angle = 0.0f;
    
    int wait = (arc4random() % 10) + 5;
    
    struct timeval ref;
    gettimeofday(&ref, NULL);
    
    __block struct timeval nav_timer;
    gettimeofday(&nav_timer, NULL);
    
    __block struct timeval gps_timer;
    gettimeofday(&gps_timer, NULL);
    
    while(1) {
        struct timeval current;
        gettimeofday(&current, NULL);
        
        if(fabsf(target_angle - angle) >= 4.0f) {
            float avel = 4.0f * ((target_angle < angle) ? -1.0f : 1.0f);
            avel *= (fabsf(target_angle - angle) > 180.0f) ? -1.0f : 1.0f;
            
            angle += avel;
            
            if(angle > 359.0f) {
                angle = 0.0f;
            }
            if(angle < 0.0f) {
                angle = 359.0f;
            }
        } else {
            if(current.tv_sec - ref.tv_sec >= wait) {
                target_angle = arc4random() % 360;
                wait = (arc4random() % 10) + 5;
                
                gettimeofday(&ref, NULL);
            }
            
            vely += cosf(angle*M_PI/180.0f) / 100000.0f;
            velx += sinf(angle*M_PI/180.0f) / 100000.0f;
        }
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            if((current.tv_usec + current.tv_sec*1000000) - (nav_timer.tv_usec + nav_timer.tv_sec*1000000) >= 66666) {
                gettimeofday(&nav_timer, NULL);
                [drone3GPlanWindowController updateDroneHeading:angle];
            }
            
            if(current.tv_sec - gps_timer.tv_sec >= 0) {
                gettimeofday(&gps_timer, NULL);
                [drone3GPlanWindowController updateDroneLocation:50.889174+vely longitude:-114.08280+velx];
            }
        });
        
        usleep(33333);
    }
}*/

- (BOOL)windowShouldClose:(id)sender {
    if(drone3g_allow_terminate == 1 || drone3g_got_connection == 0) {
        [NSApp terminate:self];
        return YES;
    } else {
        [self performSelectorInBackground:@selector(playCloseSound) withObject:nil];
        NSAlert* alert = [NSAlert alertWithMessageText:@"The drone is still flying." defaultButton:@"No, don't quit" alternateButton:@"Yes, I want to exit" otherButton:nil informativeTextWithFormat:@"If you quit now the drone will default to the behavior you've set when the connection is lost in the \"Flying Home\" section of Drone3G preferences.\n\n Are you sure you want to quit?"];
        [alert setAlertStyle:NSCriticalAlertStyle];
        
        NSInteger buttonRet = [alert runModal];
        
        if(buttonRet == NSAlertDefaultReturn) {
            return NO;
        } else {
            [NSApp terminate:self];
            return YES;
        }
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

- (IBAction)openPreferences:(id)sender {
    [drone3GPrefWindowController showWindow:nil];
}

- (IBAction)checkDataUsage:(id)sender {
    [drone3GDatWindowController showWindow:nil];
}

- (IBAction)openFlightPlanner:(id)sender {
    [drone3GPlanWindowController showWindow:nil];
}

- (IBAction)use720pVideo:(id)sender {
    [_hdMenuItem setState:NSOnState];
    [_sdMenuItem setState:NSOffState];
    
    drone3g_send_command("AT*VIDEO_CODEC=H264_720p\r");
}

- (IBAction)use360pVideo:(id)sender {
    [_sdMenuItem setState:NSOnState];
    [_hdMenuItem setState:NSOffState];
    
    drone3g_send_command("AT*VIDEO_CODEC=H264_360p\r");
}

- (IBAction)changeBitrate:(id)sender {
    [_bitrateLabel setStringValue:[NSString stringWithFormat:@"                Bitrate: %liKbps", (long)[sender integerValue]]];
    
    NSEvent* event = [[NSApplication sharedApplication] currentEvent];
    if(event.type == NSLeftMouseUp) {
        NSString* cmdString = [NSString stringWithFormat:@"AT*CONFIG_IDS= ,\"ad1efdac\",\"992f7f4f\",\"510acf97\"\rAT*CONFIG= ,\"video:max_bitrate\",\"%i\"\r", (int)[sender integerValue]];
        drone3g_send_command([cmdString cStringUsingEncoding:NSUTF8StringEncoding]);
    }
}

- (IBAction)sensitivitySliderDidChange:(id)sender {
    [[_sensitivityView viewWithTag:[sender tag]+1] setFloatValue:[sender floatValue]];
    
    // Create dummy slider to send to preferences window controller
    NSSlider* slider = [[NSSlider alloc] init];
    [slider setFloatValue:[sender floatValue]];
    [slider setTag:([sender tag]+1)/2];
    [slider setToolTip:@"UPDATE"];
    
    [drone3GPrefWindowController sliderDidChange:slider];
    
    NSEvent* event = [[NSApplication sharedApplication] currentEvent];
    if(event.type == NSLeftMouseUp) {
        drone3g_sensitivities[([sender tag]-1)/2] = [sender floatValue];
        [drone3GPrefWindowController saveSensitivities];
    }
}

- (IBAction)restoreDefaultSensitivities:(id)sender {
    [drone3GPrefWindowController resetDefaultSliders:sender];
    
    drone3g_sensitivities[0] = 0.25f;
    drone3g_sensitivities[1] = 0.23f;
    drone3g_sensitivities[2] = 0.50f;
    drone3g_sensitivities[3] = 0.351f;
    
    for(int i=0;i<4;i++) {
        [[_sensitivityView viewWithTag:i*2+1] setFloatValue:drone3g_sensitivities[i]];
        [[_sensitivityView viewWithTag:i*2+2] setFloatValue:drone3g_sensitivities[i]];
    }
    
    [drone3GPrefWindowController saveSensitivities];
}

#pragma mark -
#pragma mark UI Handling
#pragma mark -

- (void)adjustHUD:(NSNotification*)notification {
    float scaleX = _window.frame.size.width / [NSScreen mainScreen].frame.size.width;
    float scaleY = _window.frame.size.height / [NSScreen mainScreen].frame.size.height;
    float scale = sqrtf(scaleX*scaleX + scaleY*scaleY) * 1.52f;
    
    [_connectionLabel setFont:[NSFont systemFontOfSize:17*scale]];
    [_batteryLabel setFont:[NSFont systemFontOfSize:11*scale]];
    [_altitudeLabel setFont:[NSFont systemFontOfSize:17*scale]];
    [_timeFlyingLabel setFont:[NSFont systemFontOfSize:20*scale]];
    [_velocityLabel setFont:[NSFont systemFontOfSize:15*scale]];
    [_gpsLabel setFont:[NSFont systemFontOfSize:13*scale]];
    
    [_angleLabel setFont:[NSFont systemFontOfSize:18*scale]];
    [_directionLabel setFont:[NSFont systemFontOfSize:18*scale]];
    
    [_northLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_northAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_eastLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_eastAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_westLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_westAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_southLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_southAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
}

- (void)showHUD {
    float x = _signalIconImageView.frame.origin.x+_signalIconImageView.frame.size.width+_signalLevelImageView.frame.origin.x+_signalLevelImageView.frame.size.width;
    float y = _signalIconImageView.frame.origin.y-2;
    [[_controllerImageView animator] setFrameOrigin:CGPointMake(x-_controllerImageView.frame.size.width, y)];
    
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

- (void)setCompassAngle:(float)psi {
    [_angleLabel setStringValue:[NSString stringWithFormat:@"%dº", (int)psi]];
    if(psi < 22.5f || psi >= 337.5f) {
        [_directionLabel setStringValue:@"N"];
    } else if(psi >= 22.5f && psi < 67.5f) {
        [_directionLabel setStringValue:@"NE"];
    } else if(psi >= 67.5f && psi < 112.5f) {
        [_directionLabel setStringValue:@"E"];
    } else if(psi >= 112.5f && psi < 157.5f) {
        [_directionLabel setStringValue:@"SE"];
    } else if(psi >= 157.5f && psi < 202.5f) {
        [_directionLabel setStringValue:@"S"];
    } else if(psi >= 202.5f && psi < 247.5f) {
        [_directionLabel setStringValue:@"SW"];
    } else if(psi >= 247.5f && psi < 292.5f) {
        [_directionLabel setStringValue:@"W"];
    } else if(psi >= 292.5f && psi < 337.5f) {
        [_directionLabel setStringValue:@"NW"];
    }
    
    // **********************************************************************
    
    static BOOL once = NO;
    if([_northLabel isHidden] && !once) {
        // [[_directionLabel animator] setHidden:NO];
        // [[_angleLabel animator] setHidden:NO];
        
        [[_northLabel animator] setHidden:NO];
        [[_northAngleLabel animator] setHidden:NO];
        [[_eastLabel animator] setHidden:NO];
        [[_eastAngleLabel animator] setHidden:NO];
        [[_southLabel animator] setHidden:NO];
        [[_southAngleLabel animator] setHidden:NO];
        [[_westLabel animator] setHidden:NO];
        [[_westAngleLabel animator] setHidden:NO];
        
        once = YES;
    }
    
    // This is a fast way to change the compass when the drones compass switches things up
    /*[_northLabel setStringValue:@"E"];
     [_eastLabel setStringValue:@"S"];
     [_southLabel setStringValue:@"W"];
     [_westLabel setStringValue:@"N"];*/
    
    [_northAngleLabel setStringValue:[NSString stringWithFormat:@"%dº", -((int)fmodf(psi+180.0f, 360.0f)-180)]];
    [_eastAngleLabel setStringValue:[NSString stringWithFormat:@"%dº", -((int)fmodf(psi+90.0f, 360.0f)-180)]];
    [_southAngleLabel setStringValue:[NSString stringWithFormat:@"%dº", -((int)psi-180)]];
    [_westAngleLabel setStringValue:[NSString stringWithFormat:@"%dº", -((int)fmodf(psi+270.0f, 360.0f)-180)]];
    
    float letter_y = _northLabel.frame.origin.y;
    float angle_y = _northAngleLabel.frame.origin.y;
    
    float width = _window.frame.size.width-175;
    float letter_size = _northLabel.frame.size.width;
    
    if(_window.styleMask & NSFullScreenWindowMask) {
        psi -= 18.0f;
    } else {
        psi -= 38.0f;
    }
    
    psi = fmodf(psi+180.0f, 360.0f)-180.0f;
    
    float north_x = -psi/90.0f*width/2+width/2-letter_size/2;
    [_northLabel setFrameOrigin:NSMakePoint(north_x, letter_y)];
    [_northAngleLabel setFrameOrigin:NSMakePoint(north_x, angle_y)];
    
    float east_x = -psi/90.0f*width/2+width-letter_size/2;
    [_eastLabel setFrameOrigin:NSMakePoint(east_x, letter_y)];
    [_eastAngleLabel setFrameOrigin:NSMakePoint(east_x, angle_y)];
    
    float south_x = -psi/90.0f*width/2+( (psi < 0.0f) ? -width/2 : width*3/2)-letter_size/2;
    [_southLabel setFrameOrigin:NSMakePoint(south_x, letter_y)];
    [_southAngleLabel setFrameOrigin:NSMakePoint(south_x, angle_y)];
    
    
    float west_x = -psi/90.0f*width/2+( (psi < 0.0f) ? 0 : width*2)-letter_size/2;
    [_westLabel setFrameOrigin:NSMakePoint(west_x, letter_y)];
    [_westAngleLabel setFrameOrigin:NSMakePoint(west_x, angle_y)];
}

- (void)switchCompass {
    BOOL compass1 = !_northLabel.isHidden;
    [[_northLabel animator] setHidden:compass1];
    [[_northAngleLabel animator] setHidden:compass1];
    [[_eastLabel animator] setHidden:compass1];
    [[_eastAngleLabel animator] setHidden:compass1];
    [[_southLabel animator] setHidden:compass1];
    [[_southAngleLabel animator] setHidden:compass1];
    [[_westLabel animator] setHidden:compass1];
    [[_westAngleLabel animator] setHidden:compass1];
    
    BOOL compass2 = !_directionLabel.isHidden;
    [[_directionLabel animator] setHidden:compass2];
    [[_angleLabel animator] setHidden:compass2];
}

- (void)menuWillOpen:(NSMenu *)menu {
    for(int i=0;i<4;i++) {
        NSSlider* slider = (NSSlider*)[_sensitivityView viewWithTag:i*2+1];
        [slider setFloatValue:drone3g_sensitivities[i]];
        
        [self sensitivitySliderDidChange:slider];
    }
}

#pragma mark -
#pragma mark Sounds
#pragma mark -

- (void)playCloseSound {
    usleep(250000);
    [[NSSound soundNamed:@"Sosumi"] play];
}

- (void)playGPSAlertSound {
    usleep(100000);
    [[NSSound soundNamed:@"Glass"] play];
}

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
    [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:@"warning! controller disconnected" afterDelay:1.0f];
    
    controllerFlashTimer = [NSTimer scheduledTimerWithTimeInterval:0.44f target:self selector:@selector(changeControllerIconState) userInfo:nil repeats:YES];
    
    [self performSelector:@selector(playWarningSound) withObject:nil afterDelay:0.1f];
    [self performSelector:@selector(stopWarningSound) withObject:nil afterDelay:5.0f];
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
#pragma mark Battery Animations
#pragma mark -

- (void)speechSynthesizer:(NSSpeechSynthesizer *)sender didFinishSpeaking:(BOOL)finishedSpeaking {
    firstSpeechDonePlaying = YES;
}

- (void)batteryWarning {
    [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:[NSString stringWithFormat:@"warning! You should fly back. You have used half of the battery capacity from when you took off. You have %i percent remaining.", drone3g_get_navdata().battery_percentage] afterDelay:1.5f];
    [self batteryAlert:DRONE3G_BATTERY_WARNING];
}

- (void)batteryEmergency {
    firstSpeechDonePlaying = NO;
    batteryAnimationsAreWaiting = NO;
    batteryAnimationsAreRunning = YES;
    
    [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:[NSString stringWithFormat:@"warning! battery low. %i%% remaining", drone3g_get_navdata().battery_percentage] afterDelay:1.5f];
    
    [self batteryEmergencyWithVoice];
}

- (void)batteryEmergencyWithVoice {
    if(!batteryAnimationsAreRunning) {
        return;
    }
    
    if(!batteryAnimationsAreWaiting && firstSpeechDonePlaying) {
        [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:[NSString stringWithFormat:@"warning! battery low. %i%% remaining", drone3g_get_navdata().battery_percentage] afterDelay:2.0f];
    }

    [self batteryAlert:DRONE3G_BATTERY_EMERGENCY];
}

- (void)batteryAlert:(int)type {
    if(type == DRONE3G_BATTERY_EMERGENCY && batteryAnimationsAreWaiting && batteryAnimationsAreRunning) {
        [self stopBatteryAnimations];
        
        batteryAnimationsAreWaiting = NO;
        batteryAnimationsAreRunning = YES;
        
        [self performSelector:@selector(batteryEmergencyWithVoice) withObject:nil afterDelay:10.0f]; // Battery emergency pauses for 10 seconds between each warning
        
        return;
    }
    
    batteryAnimationsAreRunning = YES;
    batteryAnimationsAreWaiting = YES;
    
    [self playWarningSound];
    batteryFlashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/3.0f target:self selector:@selector(changeBatteryIconState) userInfo:nil repeats:YES];
    
    if(type == DRONE3G_BATTERY_EMERGENCY) {
        [self performSelector:@selector(batteryEmergencyWithVoice) withObject:nil afterDelay:8.0f];
    } else {
        [self performSelector:@selector(stopBatteryAnimations) withObject:nil afterDelay:10.0f];
    }
}

- (void)stopBatteryAnimations {
    [self stopWarningSound];
    
    if(batteryFlashTimer != NULL) {
        [batteryFlashTimer invalidate];
    }
    if(warningStopTimer != NULL) {
        [warningStopTimer invalidate];
    }
    
    batteryAnimationsAreRunning = NO;
    
    [_batteryImageView setHidden:NO];
    [_batteryLabel setHidden:NO];
    
    [alertSpeaker stopSpeakingAtBoundary:NSSpeechSentenceBoundary];
}

- (void)changeBatteryIconState {
    [_batteryImageView setHidden:!_batteryImageView.isHidden];
    [_batteryLabel setHidden:!_batteryLabel.isHidden];
}

@end

