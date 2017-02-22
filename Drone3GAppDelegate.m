//
//  AppDelegate.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "NSFileManager+Additions.h"

#import "Drone3GAppDelegate.h"
#import "Drone3GMDCalculator.h"
#import "Drone3GHelpWindowController.h"

#import "drone_main.h"
#import "drone_com.h"

#import <QuartzCore/QuartzCore.h>
#import <sys/time.h>

#define DRONE3G_BATTERY_WARNING 0
#define DRONE3G_BATTERY_EMERGENCY 1

@implementation Drone3GAppDelegate

const char* application_bundle_path() {
    return [[[NSBundle mainBundle] bundlePath] UTF8String];
}

@synthesize batteryAnimationsAreRunning;
@synthesize warningLabelIsAnimating;
@synthesize alertSpeaker;
@synthesize joystickDidConnect;

#pragma mark -
#pragma mark Callbacks
#pragma mark -

static const char** grab_login_creds() {
    const char** creds = malloc(sizeof(char*)*3);
    
    Drone3GLoginView* loginView = [(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] loginView];
    
    creds[0] = [[loginView getUsername] cStringUsingEncoding:NSUTF8StringEncoding];
    creds[1] = [[loginView getPassword] cStringUsingEncoding:NSUTF8StringEncoding];
    creds[2] = [[loginView getDroneName] cStringUsingEncoding:NSUTF8StringEncoding];
    
    return creds;
}

static int can_accept_drone() {
    return ([[(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] mainView] didTransistionOut] == YES && [[(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] mainView] menuState] == DRONE3G_MENU_STATE_FLYING);
}

static void new_proxy_message(const char* line) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextView* console = [(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] proxyLogView];
        
        NSDate* currentDate = [NSDate date];
        NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
        
        [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
        
        NSString* dateString = [dateFormatter stringFromDate:currentDate];
        NSString* lineString = [NSString stringWithFormat:@"%@ --- %s\n", dateString, line];
        
        NSAttributedString* text = [[NSAttributedString alloc] initWithString:lineString attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor greenColor], NSForegroundColorAttributeName, [console font], NSFontAttributeName, nil]];
        
        [[console textStorage] appendAttributedString:text];
        
        // Scroll to added text if at bottom
        NSScrollView* scrollView = (NSScrollView*)[[console superview] superview];
        CGFloat currentPosition  = [[scrollView contentView] bounds].origin.y;
        CGFloat contentHeight    = [console bounds].size.height;
        CGFloat boundingHeight   = [[scrollView contentView] bounds].size.height;
        
        if(contentHeight - currentPosition <= boundingHeight*1.2f) {
            [console scrollRangeToVisible:NSMakeRange([[console string] length], 0)];
        }
    });
}

#pragma mark -
#pragma mark Delegate Methods
#pragma mark -

- (void)awakeFromNib {
    controllerFlashTimer = NULL;
    batteryFlashTimer = NULL;
    warningStopTimer = NULL;
    labelFlashTimer = NULL;
    recordFlashTimer = NULL;
    
    warningLabelIsAnimating = NO;
    showHUDCalled = NO;
    joystickDidConnect = NO;
    
    // Set callbacks
    drone3g_can_accept_callback = &can_accept_drone;
    drone3g_get_login_info = &grab_login_creds;
    drone3g_proxy_log_post_callback = &new_proxy_message;
    
    // Load magnetic declination calculator
// FIXME: MD CALCULATOR DISABLED UNTIL MAP IS DONE
    //[Drone3GMDCalculator sharedCalculator];
    
    // Setup transparent child window for UI overlay on OpenGL view
    CGRect wRect = _window.frame;
    CGRect cRect = [_mainView frame];
    CGRect rect = CGRectMake(wRect.origin.x-2, wRect.origin.y-3, cRect.size.width+5, cRect.size.height+3);
    
    overlayWindow = [[Drone3GWindow alloc] initWithContentRect:rect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    overlayWindow.backgroundColor = [NSColor clearColor];
    [overlayWindow setOpaque:NO];
    overlayWindow.alphaValue = 1.0f;
    
    [_HUDView setHidden:YES];
    
    [_loginView setHidden:YES];
    [_loginView setFrameOrigin:NSMakePoint(-[_loginView frame].size.width, [_loginView frame].origin.y)];
    [overlayWindow setIgnoresMouseEvents:NO];
    
    [_mainView addSubview:_HUDView];
    [_mainView addSubview:_loginView];
        
    [overlayWindow setContentView:_mainView];
    [_window addChildWindow:overlayWindow ordered:NSWindowAbove];
    [_window orderWindow:NSWindowAbove relativeTo:[_window windowNumber]];
    
    [overlayWindow makeKeyAndOrderFront:nil]; // If this isn't called the menu buttons don't work
    [_window makeKeyAndOrderFront:nil]; // We call this after so that esc still exits fullscreen
    
    // DONE UI SETUP
    
    [_spinnerView startAnimation];
    
    alertSpeaker = [[NSSpeechSynthesizer alloc] initWithVoice:@"com.apple.speech.synthesis.voice.Alex"];
    [alertSpeaker setRate:240.0f];
    [alertSpeaker setDelegate:self];
    
    [_sliderMenuItem setView:_bitrateSlider];
    [_bitrateMenuItem setView:_bitrateLabel];
    [_sensitivityMenuItem setView:_sensitivityView];
    
    drone3GDatWindowController = [Drone3GDATWindowController sharedDataUsageWindowController];
    drone3GPlanWindowController = [Drone3GPLANWindowController sharedFlightMap];
    drone3GPrefWindowController = [Drone3GPREFWindowController sharedPreferencesController];
    drone3GPhotosWindowController = [Drone3GPhotosWindowController sharedPhotoWindowController];
    drone3GInstaller = [Drone3GInstallerWindowController sharedInstaller];
    drone3GUninstaller = [Drone3GUninstallerWindowController sharedUninstaller];
    drone3GHelp = [Drone3GHelpWindowController sharedHelpController];
    
    beep = [NSSound soundNamed:@"beep_a.mp3"];
    [beep setLoops:NO];
    
    // Sometimes NSSound lags on first play so this gets that out of the way (cache issue probably)
    [beep play];
    [beep stop];
    
    [_controllerImageView setFrameOrigin:_signalIconImageView.frame.origin];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(adjustHUD:) name:NSWindowDidResizeNotification object:nil];
    [_window setDelegate:(id<NSWindowDelegate>)self];
    
    // Set HUD color
    NSColor* hudColor = [drone3GPrefWindowController currentHUDColor];
    [self changeHUDColor:hudColor];
    
    // Set inclinometer visibillity
    [_HUDView setRendersInclinometer:[drone3GPrefWindowController shouldRenderInclinometer]];
    
    [_gpsLabel setFrameOrigin:NSMakePoint(_signalLevelImageView.frame.origin.x + _signalLevelImageView.frame.size.width, _signalLevelImageView.frame.origin.y)];
    
    // If directory for photos doesn't exist create it
    NSString* photoDirectory = [NSString stringWithFormat:@"%@/Photos", [NSFileManager applicationStoragePath]];
    if([[NSFileManager defaultManager] fileExistsAtPath:photoDirectory] == NO) {
        [[NSFileManager defaultManager] createDirectoryAtPath:photoDirectory withIntermediateDirectories:NO attributes:nil error:nil];
    }
    // Same for video directory
    NSString* videoDirectory = [NSString stringWithFormat:@"%@/Videos", [NSFileManager applicationStoragePath]];
    if([[NSFileManager defaultManager] fileExistsAtPath:videoDirectory] == NO) {
        [[NSFileManager defaultManager] createDirectoryAtPath:videoDirectory withIntermediateDirectories:NO attributes:nil error:nil];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    drone3g_init();
}

- (NSModalResponse)setupAndRunCloseAlert:(drone3g_termination_status_info)terminationInfo {
    NSString* messageText = @"The drone is still flying.";
    NSString* defaultButton = @"No, don't quit";
    NSString* alternateButton = @"Yes, I want to exit";
    NSString* info = @"If you quit now the drone will default to the behavior you've set when the connection is lost in the \"Flying Home\" section of Drone3G preferences.\n\n Are you sure you want to quit?\n";
    
    if( (terminationInfo & DRONE3G_TERMINATION_TRANSCODING) && (terminationInfo & DRONE3G_TERMINATION_FLYING) ) {
        messageText = @"The drone is still flying and there are videos that are still transcoding.";
        info = @"If you quit now the drone will default to the behavior you've set when the connection is lost in the \"Flying Home\" section of Drone3G preferences.\n\nAll video transcoding will have to restart from the beginning next time you open Drone3G.\n\nYou can see the progress of transcoding operations in the Photo & Videos window.\n\nAre you sure you want to quit?\n";
    } else if(terminationInfo & DRONE3G_TERMINATION_TRANSCODING) {
        messageText = @"Drone3G is still transcoding videos.";
        info = @"If you quit now all video transcoding operations will have to restart from the beginning next time you open Drone3G.\n\nYou can see the progress of transcoding operations in the Photo & Videos window.\n\n Are you sure you want to quit?\n";
    }
    
    if( (terminationInfo & DRONE3G_TERMINATION_INSTALLING) | (terminationInfo & DRONE3G_TERMINATION_UNINSTALLING) ) {
        messageText = [NSString stringWithFormat:@"The %@ hasn't finished yet.", (terminationInfo & DRONE3G_TERMINATION_INSTALLING) ? @"installation" : @"uninstall"];
        
        defaultButton = @"Ok";
        alternateButton = nil;
        
        info = [NSString stringWithFormat:@"Quiting while %@ can potentially harm the drone, please wait until the %@ finishes.", (terminationInfo & DRONE3G_TERMINATION_INSTALLING) ? @"installing" : @"uninstalling", (terminationInfo & DRONE3G_TERMINATION_INSTALLING) ? @"install" : @"uninstall"];
    }
    
    [self performSelectorInBackground:@selector(playCloseSound) withObject:nil];
    NSAlert* alert = [NSAlert alertWithMessageText:messageText defaultButton:defaultButton alternateButton:alternateButton otherButton:nil informativeTextWithFormat:@"%@", info];
    [alert setAlertStyle:NSCriticalAlertStyle];
    
    return [alert runModal];
}

- (BOOL)windowShouldClose:(id)sender {
    [[NSApplication sharedApplication] terminate:nil];
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    drone3g_termination_status_info terminationInfo = drone3g_allow_termination();
    
    if(terminationInfo == DRONE3G_TERMINATION_EXIT) {
        [[NSColorPanel sharedColorPanel] orderOut:nil];
        
        return YES;
    } else {
        NSInteger buttonRet = [self setupAndRunCloseAlert:terminationInfo];
        
        if(buttonRet == NSAlertDefaultReturn) {
            return NO;
        } else {
            [[NSColorPanel sharedColorPanel] orderOut:nil];
            
            return YES;
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"initial_launch"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    drone3g_exit(0);
}

#pragma mark -
#pragma mark IBActions
#pragma mark -

- (void)menuButtonPushed:(int)identifier {
    switch (identifier) {
        case DRONE3G_MENU_BUTTON_START:
            if(actingAsProxy) {
                [_connectionLabel setStringValue:@"Awaiting connection to drone..."];
            }
            
            [_mainView animateOut];
            
            break;
            
        case DRONE3G_MENU_BUTTON_LOGIN:
            actingAsProxy = NO;
            
            // Check if login credentials can be converted to a C string
            if([[_loginView getUsername] canBeConvertedToEncoding:NSUTF8StringEncoding] && [[_loginView getPassword] canBeConvertedToEncoding:NSUTF8StringEncoding] && [[_loginView getDroneName] canBeConvertedToEncoding:NSUTF8StringEncoding]) {
                [_mainView animateOut];
            } else {
                [_loginView shakeWindow];
            }
            
            drone3g_set_proxy_mode(([_proxyCheckBox isChecked]) ? DRONE3G_PROXY_MODE_CLIENT : DRONE3G_PROXY_MODE_NONE);
            
            break;
            
        case DRONE3G_MENU_BUTTON_PROXY: {
            drone3g_set_proxy_mode(DRONE3G_PROXY_MODE_SERVER);
            actingAsProxy = YES;
            
            // The purpose of changing this string is so that the Drone3G title will animate out when proxying,
            // the Drone3G main menu animator decides whether or not to animate the title based on the text
            // in the connection label
            [_connectionLabel setStringValue:@"Connection lost awaiting reconnection..."];
            
            [_mainView animateOut];
            
            break;
        }
            
        case DRONE3G_MENU_BUTTON_INSTALL:
            if(![[drone3GUninstaller window] isVisible]) {
                [drone3GInstaller showWindow:nil];
            }
            
            break;
            
        case DRONE3G_MENU_BUTTON_UNINSTALL:
            if(![[drone3GInstaller window] isVisible]) {
                [drone3GUninstaller showWindow:nil];
            }
            
            break;
            
        default:
            break;
    }
}

- (void)menuWillAnimateIn {
    if([_mainView menuState] == DRONE3G_MENU_STATE_FLYING) {
        [_loginView setHidden:YES];
    }
    if(actingAsProxy) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[_proxyLogView animator] setHidden:YES];
        });
    }
    
    [_loginView disableEditing];
    
    drone3g_disconnect();
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.8f];
    
    [[_HUDView animator] setHidden:YES];
    
    [NSAnimationContext endGrouping];
}

- (void)menuDidFinishAnimatingOut {
    if([_mainView menuState] == DRONE3G_MENU_STATE_LOGIN) {
        [_loginView enableEditing];
        [_loginView setHidden:NO];
        
        return;
    }
    
    [_window makeKeyAndOrderFront:nil];
    
    static BOOL helpOnce = NO;
    if(!actingAsProxy) {
        [NSAnimationContext beginGrouping];
        [[NSAnimationContext currentContext] setDuration:1.3f];
        
        static BOOL once = NO;
        if(!once) {
            [[NSAnimationContext currentContext] setCompletionHandler:^{
                drone3g_start();
            }];
            
            once = YES;
        } else {
            if(showHUDCalled) {
                NSView* imageView = [_mainView viewWithTag:1];
                NSPoint origin = [imageView frame].origin;
                
                [imageView setHidden:YES];
                [imageView setFrameOrigin:NSMakePoint(origin.x + [imageView window].frame.size.width, origin.y)];
            }
        }
        
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"initial_launch"] && !helpOnce) {
            helpOnce = YES;
            [_tipLabel setHidden:YES];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[[_HUDView viewWithTag:18] animator] setHidden:YES];
                [[_tipLabel animator] setHidden:NO];
                
                [[Drone3GTipGenerator sharedTipGenerator] generateTipsAtInterval:12.0f forLabel:_tipLabel];
            });
        } else {
            [[_HUDView viewWithTag:18] setHidden:YES];
        }
        
        [[Drone3GTipGenerator sharedTipGenerator] generateTipsAtInterval:12.0f forLabel:_tipLabel];
        [[_HUDView animator] setHidden:NO];
        
        [NSAnimationContext endGrouping];
    } else {
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"initial_launch"] && !helpOnce) {
            helpOnce = YES;
            
            new_proxy_message("Click, then click again and hold while swiping your finger to the left to go back\n");
        }
        [_proxyLogView setString:@""]; // Clear old log
        [[_proxyLogView animator] setHidden:NO];
        
        drone3g_start_proxy();
    }
}

#pragma mark -

- (IBAction)showProxyHelp:(id)sender {
    [drone3GHelp switchHelp:DRONE3G_HELP_PROXY];
}

- (IBAction)changeRecordingMode:(id)sender {
    [(NSMenuItem*)sender setState:([(NSMenuItem*)sender state] == NSOnState) ? NSOffState : NSOnState];
    drone3g_set_recording_mode( ([(NSMenuItem*)sender state] == NSOnState) );
}

- (IBAction)showPhotos:(id)sender {
    [drone3GPhotosWindowController showWindow:nil];
}

- (IBAction)showExportHelp:(id)sender {
    [drone3GHelp switchHelp:DRONE3G_HELP_MEDIA];
}

- (IBAction)openPreferences:(id)sender {
    [drone3GPrefWindowController showWindow:nil];
}

- (IBAction)checkDataUsage:(id)sender {
    [drone3GDatWindowController showWindow:nil];
}

- (IBAction)openFlightPlanner:(id)sender {
    [drone3GPlanWindowController showWindow:nil];
}

- (IBAction)openHelp:(id)sender {
    [drone3GHelp showWindow:nil];
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
    float multiplier;
    NSString* units;
    
    switch ([sender tag]) {
        case 1:
            multiplier = 30.0f;
            units = @"˚";
            
            break;
        case 3:
            multiplier = 350.0f;
            units = @"˚/s";
            
            break;
        default:
            multiplier = 2000.0f;
            units = @"mm/s";
            
            break;
    }
    
    [[_sensitivityView viewWithTag:[sender tag]+1] setStringValue:[NSString stringWithFormat:( ([sender tag] == 1) ? @"%.1f%@" : @"%.0f%@" ), [sender floatValue], units]];
    
    // Create dummy slider to send to preferences window controller
    NSSlider* slider = [[NSSlider alloc] init];
    [slider setMinValue:0.0f];
    [slider setMaxValue:2000.0f];
    [slider setFloatValue:[sender floatValue]];
    [slider setTag:([sender tag]+1)/2];
    [slider setToolTip:@"UPDATE"];
    
    [drone3GPrefWindowController sliderDidChange:slider];
    
    NSEvent* event = [[NSApplication sharedApplication] currentEvent];
    if(event.type == NSLeftMouseUp) {
        float* drone3g_sensitivities = drone3g_get_sensitivities_array();
        
        drone3g_lock_sensitivities_array();
        drone3g_sensitivities[([sender tag]-1)/2] = [sender floatValue]/multiplier;
        drone3g_unlock_sensitivities_array();
        
        [drone3GPrefWindowController saveSensitivities];
    }
}

- (IBAction)restoreDefaultSensitivities:(id)sender {
    [drone3GPrefWindowController resetDefaultSliders:sender];
    
    float* drone3g_sensitivities = drone3g_get_sensitivities_array();
    
    drone3g_lock_sensitivities_array();
    drone3g_sensitivities[0] = 0.25f;
    drone3g_sensitivities[1] = 0.23f;
    drone3g_sensitivities[2] = 0.60f;
    drone3g_sensitivities[3] = 0.45f;
    drone3g_unlock_sensitivities_array();
    
    for(int i=0;i<4;i++) {
        float multiplier;
        NSString* units;
        
        switch (i) {
            case 0:
                multiplier = 30.0f;
                units = @"˚";
                
                break;
            case 1:
                multiplier = 350.0f;
                units = @"˚/s";
                
                break;
            default:
                multiplier = 2000.0f;
                units = @"mm/s";
                
                break;
        }
        
        [[_sensitivityView viewWithTag:i*2+1] setFloatValue:drone3g_sensitivities[i]*multiplier];
        [[_sensitivityView viewWithTag:i*2+2] setStringValue:[NSString stringWithFormat:( (i == 0) ? @"%.1f%@" : @"%.0f%@" ), drone3g_sensitivities[i]*multiplier, units]];
    }
    
    [drone3GPrefWindowController saveSensitivities];
}

- (IBAction)showControllerHelp:(id)sender {
    [drone3GHelp switchHelp:DRONE3G_HELP_CONTROLLER];
}

#pragma mark -
#pragma mark UI Handling
#pragma mark -

- (void)adjustHUD:(NSNotification*)notification {
    float scaleX = _window.frame.size.width / [NSScreen mainScreen].frame.size.width;
    float scaleY = _window.frame.size.height / [NSScreen mainScreen].frame.size.height;
    float scale = sqrtf(scaleX*scaleX + scaleY*scaleY) * 1.52f;
    
    // Adjust child window
    CGRect wRect = self.window.frame;
    CGRect cRect = [[self.window contentView] frame];
    CGRect rect = CGRectMake(wRect.origin.x-scaleX*2, wRect.origin.y-scaleY*3, cRect.size.width+scaleX*5, cRect.size.height+scaleY*3);
    
    [overlayWindow setFrame:rect display:YES];
        
    [_spinnerView setFrameSize:NSMakeSize(54.0f*scaleX*2, 50.0f*scaleY*2.12f)];
    
    [_loginView adjustFontSize:scale];
    
    // Hide the title bar in OS X Yosemite since the HUD will be on top of it
    if([_window styleMask] & NSFullScreenWindowMask) {
        NSArray* windows = [NSApp windows];
        for(NSWindow* window in windows) {
            if([NSStringFromClass([window class]) isEqualToString:@"NSToolbarFullScreenWindow"]) {
                [[window contentView] setHidden:YES];
            }
        }
    }
    
    [_connectionLabel setFont:[NSFont systemFontOfSize:22*scale]];
    [_tipLabel setFont:[NSFont systemFontOfSize:12*scale]];
    [[_HUDView viewWithTag:18] setFont:[NSFont systemFontOfSize:16*scale]];
    [_warningLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_batteryLabel setFont:[NSFont systemFontOfSize:11*scale]];
    [_altitudeLabel setFont:[NSFont systemFontOfSize:17*scale]];
    [_timeFlyingLabel setFont:[NSFont systemFontOfSize:20*scale]];
    [_velocityLabel setFont:[NSFont systemFontOfSize:15*scale]];
    [_gpsLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_distanceLabel setFont:[NSFont systemFontOfSize:11*scale]];
    [_windSpeedLabel setFont:[NSFont systemFontOfSize:10*scale]];
    
    [_proxyLogView setFont:[NSFont systemFontOfSize:11*scale]];
    
    [_angleLabel setFont:[NSFont systemFontOfSize:18*scale]];
    [_directionLabel setFont:[NSFont systemFontOfSize:18*scale]];
    
    [_homeAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_northLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_northAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_eastLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_eastAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_westLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_westAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_southLabel setFont:[NSFont systemFontOfSize:13*scale]];
    [_southAngleLabel setFont:[NSFont systemFontOfSize:13*scale]];
    
    [overlayWindow viewsNeedDisplay];
}

- (void)changeInclinometerState:(BOOL)visibillity {
    [_HUDView setRendersInclinometer:visibillity];
}

- (void)updateInclinometer:(float)pitch roll:(float)roll {
    [_HUDView updateInclinometer:pitch roll:roll];
}

- (void)changeHUDColor:(NSColor*)hudColor {
    CIColor* color = [CIColor colorWithCGColor:[hudColor CGColor]];
    CIFilter* filter = [CIFilter filterWithName:@"CIFalseColor"];
    [filter setDefaults];
    [filter setValue:color forKey:@"inputColor1"];
    
    [[_controllerImageView layer] setFilters:@[filter]];
    [[_signalIconImageView layer] setFilters:@[filter]];
    [[_signalLevelImageView layer] setFilters:@[filter]];
    
    [_HUDView updateInclinometerColor:hudColor];
    
    [_distanceLabel  setTextColor:hudColor];
    [_altitudeLabel setTextColor:hudColor];
    [_timeFlyingLabel setTextColor:hudColor];
    [_velocityLabel setTextColor:hudColor];
    [_windSpeedLabel setTextColor:hudColor];
    
    [_homeAngleLabel setTextColor:hudColor];
    [_northLabel setTextColor:hudColor];
    [_northAngleLabel setTextColor:hudColor];
    [_eastLabel setTextColor:hudColor];
    [_eastAngleLabel setTextColor:hudColor];
    [_southLabel setTextColor:hudColor];
    [_southAngleLabel setTextColor:hudColor];
    [_westLabel setTextColor:hudColor];
    [_westAngleLabel setTextColor:hudColor];
}

- (void)showHUD {
    showHUDCalled = YES;
    
    float x = _signalIconImageView.frame.origin.x+_signalIconImageView.frame.size.width+_signalLevelImageView.frame.origin.x+_signalLevelImageView.frame.size.width;
    float y = _signalIconImageView.frame.origin.y-2;
    [[_controllerImageView animator] setFrameOrigin:CGPointMake(x-_controllerImageView.frame.size.width, y)];
    
    if(!_controllerImageView.isHidden) {
        [[_gpsLabel animator] setFrameOrigin:NSMakePoint(_controllerImageView.frame.origin.x + _controllerImageView.frame.size.width+2, _controllerImageView.frame.origin.y+1)];
    }
    
    NSView* titleView = [_mainView viewWithTag:2];
    NSPoint origin = [titleView frame].origin;
    
    [[titleView animator] setHidden:YES];
    [titleView setFrameOrigin:NSMakePoint(origin.x + [titleView window].frame.size.width, origin.y)];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if([_mainView didTransistionOut]) {
            NSView* imageView = [_mainView viewWithTag:1];
            NSPoint origin = [imageView frame].origin;
            
            [[imageView animator] setHidden:YES];
            [imageView setFrameOrigin:NSMakePoint(origin.x + [imageView window].frame.size.width, origin.y)];
        }
    });
    
    [_spinnerView stopAnimation];
    
    [[_connectionLabel animator] setHidden:YES];
    [_connectionLabel setStringValue:@"Connection lost awaiting reconnection..."];
        
    [[_tipLabel animator] setHidden:YES];
    [[_batteryLabel animator] setHidden:NO];
    [[_windSpeedLabel animator] setHidden:NO];
    [[_altitudeLabel animator] setHidden:NO];
    [[_timeFlyingLabel animator] setHidden:NO];
    [[_velocityLabel animator] setHidden:NO];
    [[_batteryImageView animator] setHidden:NO];
    [[_signalIconImageView animator] setHidden:NO];
    [[_signalLevelImageView animator] setHidden:NO];
    
    if(!joystickDidConnect) {
        [[_helpButton animator] setHidden:NO];
    }
}

- (void)showConnectionLabel {
    [_connectionLabel setHidden:NO];
    [_signalLevelImageView setHidden:YES];
    [_spinnerView startAnimation];
    
    [_HUDView setNeedsDisplay:YES]; // Update inclinometer
}

- (void)hideConnectionLabel {
    if(![[_connectionLabel stringValue] isEqualToString:@"Awaiting connection to drone..."]) {
        [[_connectionLabel animator] setHidden:YES];
    }
    
    [[_signalLevelImageView animator] setHidden:NO];
    [_spinnerView stopAnimation];
    
    [_HUDView setNeedsDisplay:YES]; // Update inclinometer
}

- (void)positionHomeImage:(float)psi {
    [_homeImage setHidden:NO];
    
    float width = _window.frame.size.width-175;
    float image_size = _homeImage.frame.size.width;
    
    psi = 360.0f - psi;
    psi -= 38.0f - (_window.frame.size.width - 640.0f) / 1280.0f * 40;
    psi = fmodf(psi+180.0f, 360.0f)-180.0f;
    
    homeAngle = psi;
    float _homeAngle = homeAngle + (_window.frame.size.width - 640.0f) / 1280.0f * 32;
    
    [_homeImage setFrameOrigin:NSMakePoint(-_homeAngle/90.0f*width/2+width/2-image_size/2 + (_northLabel.frame.origin.x - 314 * _window.frame.size.width/640.0f), _homeImage.frame.origin.y)];
    [_homeAngleLabel setFrameOrigin:NSMakePoint(_homeImage.frame.origin.x-image_size/6, _homeAngleLabel.frame.origin.y)];
    
    [_homeAngleLabel setStringValue:[NSString stringWithFormat:@"%.0fº", -((width/2 - _homeImage.frame.origin.x)*2/width*90+ (31 - (_window.frame.size.width - 640.0f) / 1280.0f * 31) ) ]];
    
    // Don't show home angle label if it overlaps any part of the compass
    bool northTest = CGRectIntersectsRect(_northAngleLabel.frame, _homeAngleLabel.frame);
    bool eastTest = CGRectIntersectsRect(_eastAngleLabel.frame, _homeAngleLabel.frame);
    bool southTest = CGRectIntersectsRect(_southAngleLabel.frame, _homeAngleLabel.frame);
    bool westTest = CGRectIntersectsRect(_westAngleLabel.frame, _homeAngleLabel.frame);
    
    if(northTest || eastTest || southTest || westTest) {
        [_homeAngleLabel setHidden:YES];
    } else {
        [_homeAngleLabel setHidden:NO];
    }
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
    float image_size = _homeImage.frame.size.width;
    float letter_size = _northLabel.frame.size.width;
    
    psi -= 38.0f - (_window.frame.size.width - 640.0f) / 1280.0f * 40;
    psi = fmodf(psi+180.0f, 360.0f)-180.0f;
    
    float north_x = -psi/90.0f*width/2+width/2-letter_size/2;
    
    float _homeAngle = homeAngle + (_window.frame.size.width - 640.0f) / 1280.0f * 32;
    [_homeImage setFrameOrigin:NSMakePoint(-_homeAngle/90.0f*width/2+width/2-image_size/2 + (north_x - 314 * _window.frame.size.width/640.0f), _homeImage.frame.origin.y)];
    [_homeAngleLabel setStringValue:[NSString stringWithFormat:@"%.0fº", -((width/2 - _homeImage.frame.origin.x)*2/width*90+ (31 - (_window.frame.size.width - 640.0f) / 1280.0f * 31) ) ]];
    [_homeAngleLabel setFrameOrigin:NSMakePoint(_homeImage.frame.origin.x-image_size/6, _homeAngleLabel.frame.origin.y)];
    
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
    
    
    // Don't show home angle label if it overlaps any part of the compass
    if(![_homeImage isHidden]) {
        bool northTest = CGRectIntersectsRect(_northAngleLabel.frame, _homeAngleLabel.frame);
        bool eastTest = CGRectIntersectsRect(_eastAngleLabel.frame, _homeAngleLabel.frame);
        bool southTest = CGRectIntersectsRect(_southAngleLabel.frame, _homeAngleLabel.frame);
        bool westTest = CGRectIntersectsRect(_westAngleLabel.frame, _homeAngleLabel.frame);
        
        if(northTest || eastTest || southTest || westTest) {
            [_homeAngleLabel setHidden:YES];
        } else {
            [_homeAngleLabel setHidden:NO];
        }
    }
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
    float* drone3g_sensitivities = drone3g_get_sensitivities_array();
    
    for(int i=0;i<4;i++) {
        NSSlider* slider = (NSSlider*)[_sensitivityView viewWithTag:i*2+1];
        
        float multiplier;
        switch (i) {
            case 0:
                multiplier = 30.0f;
                break;
            case 1:
                multiplier = 350.0f;
                break;
            default:
                multiplier = 2000.0f;
                break;
        }
        
        
        [slider setFloatValue:drone3g_sensitivities[i]*multiplier];
        
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
#pragma mark Warning Label Animation
#pragma mark -

- (void)flashWarningLabel {
    labelFlashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/2.0f target:self selector:@selector(changeWarningLabelState) userInfo:nil repeats:YES];
    warningLabelIsAnimating = YES;
}

- (void)stopFlashingWarningLabel {
    warningLabelIsAnimating = NO;
    
    if(labelFlashTimer) {
        [labelFlashTimer invalidate];
    }
    
    [_warningLabel setHidden:YES];
}

- (void)changeWarningLabelState {
    [_warningLabel setHidden:!_warningLabel.isHidden];
}

#pragma mark -
#pragma mark Controller Icon Animations
#pragma mark -

- (void)flashControllerIcon {
    [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:@"warning! controller disconnected" afterDelay:1.0f];
    
    controllerFlashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/3.0f target:self selector:@selector(changeControllerIconState) userInfo:nil repeats:YES];
    
    [self performSelector:@selector(playWarningSound) withObject:nil afterDelay:0.1f];
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
#pragma mark Record Indicator Animation
#pragma mark -

- (void)flashRecordingIndicator {
    recordFlashTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/2.0f target:self selector:@selector(changeRecordIndicatorState) userInfo:nil repeats:YES];
}

- (void)stopFlashingRecordIndicator {
    if(recordFlashTimer != NULL) {
        [recordFlashTimer invalidate];
    }
    
    [_recordingIndicator setHidden:YES];
}

- (void)changeRecordIndicatorState {
    [_recordingIndicator setHidden:!_recordingIndicator.isHidden];
}

#pragma mark -
#pragma mark Battery Animations
#pragma mark -

- (void)speechSynthesizer:(NSSpeechSynthesizer *)sender didFinishSpeaking:(BOOL)finishedSpeaking {
    firstSpeechDonePlaying = YES;
}

- (void)batteryWarning {
    [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:[NSString stringWithFormat:@"warning! Battery halfway point. You have %i percent remaining.", drone3g_get_navdata().battery_percentage] afterDelay:1.5f];
    [self batteryAlert:DRONE3G_BATTERY_WARNING];
}

- (void)batteryEmergency {
    firstSpeechDonePlaying = NO;
    batteryAnimationsAreWaiting = NO;
    batteryAnimationsAreRunning = YES;
    
    [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:[NSString stringWithFormat:@"warning! battery low. %i%% remaining", drone3g_get_navdata().battery_percentage] afterDelay:0.5f];
    
    [self batteryEmergencyWithVoice];
}

- (void)batteryEmergencyWithVoice {
    if(!batteryAnimationsAreRunning) {
        return;
    }
    
    if(!batteryAnimationsAreWaiting && firstSpeechDonePlaying) {
        [alertSpeaker performSelector:@selector(startSpeakingString:) withObject:[NSString stringWithFormat:@"warning! battery low. %i%% remaining", drone3g_get_navdata().battery_percentage] afterDelay:0.5f];
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

