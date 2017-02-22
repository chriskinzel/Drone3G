//
//  Drone3GPREFWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-14.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import <syslog.h>

#import "Drone3GPREFWindowController.h"
#import "Drone3GHelpWindowController.h"
#import "Drone3GAppDelegate.h"

#import "drone_main.h"
#import "drone3g_installer.h"

@implementation Drone3GPREFWindowController

@synthesize toolbar;
@synthesize controllerView;
@synthesize hudView;
@synthesize flyHomeView;
@synthesize mainView;
@synthesize hudImageView;
@synthesize carrierView;
@synthesize loginView;

@synthesize connectionLostMode;
@synthesize landTimeout;
@synthesize flyHomeTimeout;
@synthesize flyHomeAltitude;

float limits[4] = {30.0f,350.0f,2000.0f,2000.0f};

#pragma mark -
#pragma mark Initialization
#pragma mark -

+ (id)sharedPreferencesController {
    static Drone3GPREFWindowController* sharedController = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedController = [[self alloc] init];
    });
    
    return sharedController;
}

- (id)init {
    self = [super initWithWindowNibName:@"PreferencesWindow"];
    if(self) {
        appDelegate = (Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate];
        
        // Load preferences
        preferences = [NSUserDefaults standardUserDefaults];
       
        NSDictionary* controllerDict = [NSDictionary dictionaryWithObjectsAndKeys:@"13", @"land", @"9", @"hover", @"14", @"takeoff", @"3", @"trim", @"12", @"emergency", @"15", @"switch-cam", @"0", @"stick-flip", @"0", @"calib", @"16", @"flyhome", @"4", @"read-bat", @"6", @"sethome", @"11", @"picture", @"10", @"record", @"7", @"read-ping", nil];
        NSDictionary* hudDict = [NSDictionary dictionaryWithObjectsAndKeys:[NSArchiver archivedDataWithRootObject:[NSColor greenColor]] , @"color", @"ft", @"altitude", @"km/h", @"speed", @"m", @"distance", [NSNumber numberWithBool:YES], @"inc_visible", nil];
        NSDictionary* cLossDict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:25], @"land-timeout", [NSNumber numberWithInt:4572], @"flyhome-altitude", [NSNumber numberWithInt:20], @"flyhome-timeout", nil];
        NSDictionary* carrierDict = [NSDictionary dictionaryWithObjectsAndKeys:@"", @"APN", @"", @"username", @"", @"password", [NSNumber numberWithBool:YES], @"automatic", nil];
        
        NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:0.25f], @"pitch+roll", [NSNumber numberWithFloat:0.23f], @"yaw", [NSNumber numberWithFloat:0.60f], @"climb", [NSNumber numberWithFloat:0.45f], @"descent", controllerDict, @"ps3", hudDict, @"HUD", cLossDict, @"CLoss", carrierDict, @"CARRIER", [NSNumber numberWithBool:YES], @"initial_launch", [NSNumber numberWithBool:NO], @"media_supress", nil];
        
        [preferences registerDefaults:dict];
        
        loadControllerMap([preferences dictionaryForKey:@"ps3"]);
        
        float* sensitivities = drone3g_get_sensitivities_array();
        sensitivities[0] = [preferences floatForKey:@"pitch+roll"];
        sensitivities[1] = [preferences floatForKey:@"yaw"];
        sensitivities[2] = [preferences floatForKey:@"climb"];
        sensitivities[3] = [preferences floatForKey:@"descent"];
        
        // Preloads preferences nib
        [[self window] setIsVisible:NO];
    }
    
    return self;
}

/*- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}*/

/*- (void)windowDidLoad
{
    [super windowDidLoad];
}*/

- (void)awakeFromNib {
    // Pragmatically prevent PS button as being used for flat trim since when this button is pushed to
    // connect the controller it can be registered as a button push and doing a random unexpected flat trim
    // could be devastating to the users drone
    [[controllerView viewWithTag:14] removeItemAtIndex:4];
    
    [self setupControllerView];
    [self setupHUDView];
    [self setupFlyHomeView];
    [self setupCarrierView];
    
    [toolbar setSelectedItemIdentifier:@"Controllers"];
    
    [[self window] setContentSize:[controllerView frame].size];
    [mainView setFrameSize:[controllerView frame].size];
    
    [mainView addSubview:controllerView];
    [mainView setWantsLayer:YES];
    
    currentView = controllerView;
}

- (void)showWindow:(id)sender {
    if([[self window] isVisible] && ([[NSApplication sharedApplication] currentEvent].modifierFlags & NSCommandKeyMask) ) { // Alternates visibillity for hot keys
        [[self window] performClose:nil];
        return;
    }
    
    if(controllerView != nil) {
        [self setupControllerView];
    }
    
    if(currentView == carrierView) {
        [self connectARDrone];
    }
            
    [[self window] center];
    [super showWindow:sender];
}

#pragma mark -
#pragma mark Delegate
#pragma mark -

- (void)playCloseSound {
    usleep(250000);
    [[NSSound soundNamed:@"Bottle"] play];
}

- (BOOL)windowShouldClose:(id)sender {
    NSDictionary* buttonDict = [preferences  dictionaryForKey:@"ps3"];
    
    // Check if landing was set
    BOOL landExists = [(NSString*)[buttonDict objectForKey:@"land"] length] > 0;
    
    // Check if takeoff was set
    BOOL takeoffExists = [(NSString*)[buttonDict objectForKey:@"takeoff"] length] > 0;
    
    if(!takeoffExists || !landExists) {
        [self performSelectorInBackground:@selector(playCloseSound) withObject:nil];
        
        NSString* messageString;
        NSString* titleString;
        if(!takeoffExists && !landExists) {
            titleString = @"You didn't choose any takeoff or landing buttons.";
            messageString = @"Do you want to go back and add them?";
        } else {
            titleString = [NSString stringWithFormat:@"You didn't choose a %@ button.", (takeoffExists) ? @"landing" : @"takeoff"];
            messageString = @"Do you want to go back and add one?";

        }
        
        NSAlert* alert = [NSAlert alertWithMessageText:titleString defaultButton:@"Continue that's fine" alternateButton:@"Go back and fix" otherButton:nil informativeTextWithFormat:@"%@", messageString];
        [alert setAlertStyle:NSCriticalAlertStyle];
        
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse buttonRet){
            if(buttonRet == NSAlertAlternateReturn) {
                NSButton* dummyObject = [[NSButton alloc] init];
                [dummyObject setTag:0];
                
                [toolbar setSelectedItemIdentifier:@"Controllers"];
                [self switchView:dummyObject];
            } else {
                [[self window] close];
            }
        }];
        
        return NO;
    }
    
    // Color panel doesn't close by itself
    [[NSColorPanel sharedColorPanel] orderOut:nil];
    
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    [[NSColorPanel sharedColorPanel] performClose:nil];
    
    drone3g_installer_status status = drone3g_installer_get_status() >> 2;
    if(!(status & DRONE3G_INSTALLER_STATUS_INSTALLING) && !(status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
        drone3g_installer_stop_connecting();
    }
}

#pragma mark -
#pragma mark Preferences Interface
#pragma mark -

- (NSRect)frameForContentView:(NSView*)view {
    
    NSWindow* window = [self window];
    NSRect newFrameRect = [window frameRectForContentRect:[view frame]];
    NSRect oldFrameRect = [window frame];
    NSSize newSize = newFrameRect.size;
    NSSize oldSize = oldFrameRect.size;
    
    float deltaHeight = newSize.height - oldSize.height;
    
    NSRect frame = [window frame];
    frame.size = newSize;
    frame.origin.y -= deltaHeight;
    
    return frame;
}

- (IBAction)switchView:(id)sender {
    NSInteger tag = [sender tag];
    NSView* view;
    
    switch (tag) {
        case 0:
            view = controllerView;
            break;
        case 1:
            view = flyHomeView;
            break;
        case 2:
            view = hudView;
            break;
        case 3:
            view = carrierView;
            [self connectARDrone];
            
            break;
        case 4:
            view = loginView;
            [self connectARDrone];
            
            break;
        default:
            return;
    }
    
    // Close color panel if still open
    if(view != hudView) {
        [[NSColorPanel sharedColorPanel] orderOut:nil];
    }
    
    NSRect newFrame = [self frameForContentView:view];
    
    [NSAnimationContext beginGrouping];
    
    [[mainView animator] replaceSubview:currentView with:view];
    [mainView setFrameSize:newFrame.size];
    [[self.window animator] setFrame:newFrame display:YES];
    
    [NSAnimationContext endGrouping];
    
    currentView = view;
    
    for(int i=5;i<=21;i++) {
        NSComboBox* currentBox = (NSComboBox*)[controllerView viewWithTag:i];
        int selectedItem = (int)[currentBox indexOfSelectedItem];
        
        if(selectedItem == 5) {
            [currentBox setTextColor:[NSColor redColor]];
        } else if(selectedItem == 3) {
            [currentBox setTextColor:[NSColor greenColor]];
        } else if(selectedItem == 1 && i != 13 && i != 15) {
            [currentBox setTextColor:[NSColor blueColor]];
        } else if(selectedItem == 0) {
            [currentBox setTextColor:[NSColor darkGrayColor]];
        } else {
            [currentBox setTextColor:[NSColor blackColor]];
        }
    }
    for(int i=26;i<=27;i++) {
        NSComboBox* currentBox = (NSComboBox*)[controllerView viewWithTag:i];
        int selectedItem = (int)[currentBox indexOfSelectedItem];
        
        if(selectedItem == 5) {
            [currentBox setTextColor:[NSColor redColor]];
        } else if(selectedItem == 3) {
            [currentBox setTextColor:[NSColor greenColor]];
        } else if(selectedItem == 1 && i != 13 && i != 15) {
            [currentBox setTextColor:[NSColor blueColor]];
        } else if(selectedItem == 0) {
            [currentBox setTextColor:[NSColor darkGrayColor]];
        } else {
            [currentBox setTextColor:[NSColor blackColor]];
        }
    }
    
    [[controllerView viewWithTag:13] setTextColor:[NSColor colorWithCalibratedRed:0.76f green:0.0f blue:0.07f alpha:1.0f]];
    [[controllerView viewWithTag:15] setTextColor:[NSColor colorWithCalibratedRed:0.76f green:0.0f blue:0.07f alpha:1.0f]];
    
    // Set proper units in fly home view
    BOOL inFeet = [[self altitudeUnits] isEqualToString:@"ft"];
    if(inFeet) {
        [[flyHomeView viewWithTag:5] setFrameOrigin:NSMakePoint(499, 235)];
        [[flyHomeView viewWithTag:6] setFrameOrigin:NSMakePoint(542, 232)];
        
        int alt = rint(flyHomeAltitude / 304.8);
        
        [[flyHomeView viewWithTag:4] setMinValue:15];
        [[flyHomeView viewWithTag:4] setMaxValue:400];
        [[flyHomeView viewWithTag:4] setIntValue:alt];
        [[flyHomeView viewWithTag:3] setStringValue:[NSString stringWithFormat:@"%d", alt]];
    } else {
        [[flyHomeView viewWithTag:5] setFrameOrigin:NSMakePoint(519, 235)];
        [[flyHomeView viewWithTag:6] setFrameOrigin:NSMakePoint(562, 232)];
        
        int alt = rint(flyHomeAltitude / 1000.0);
        
        [[flyHomeView viewWithTag:4] setMinValue:5];
        [[flyHomeView viewWithTag:4] setMaxValue:121];
        [[flyHomeView viewWithTag:4] setIntValue:alt];
        [[flyHomeView viewWithTag:3] setStringValue:[NSString stringWithFormat:@"%d", alt]];
    }
    
    NSString* flyHomeString = [[[flyHomeView viewWithTag:7] cellAtRow:1 column:0] title];
    flyHomeString = [flyHomeString stringByReplacingOccurrencesOfString:(inFeet) ? @"meters" : @"feet"  withString:(inFeet) ? @"feet" : @"meters"];
    
    [[[flyHomeView viewWithTag:7] cellAtRow:1 column:0] setTitle:flyHomeString];
}

#pragma mark -
#pragma mark Controller View
#pragma mark -

- (void)setupControllerView {
    float* drone3g_sensitivities = drone3g_get_sensitivities_array();
    
    for(int i=0;i<4;i++) {
        [[controllerView viewWithTag:i+1] setFloatValue:drone3g_sensitivities[i]*limits[i]];
        
        if(i == 0) {
            [[controllerView viewWithTag:i+22] setStringValue:[NSString stringWithFormat:@"%.1f˚", drone3g_sensitivities[i]*limits[i]]];
        } else if(i == 1) {
            [[controllerView viewWithTag:i+22] setStringValue:[NSString stringWithFormat:@"%.0f˚/s", drone3g_sensitivities[i]*limits[i]]];
        } else {
            [[controllerView viewWithTag:i+22] setStringValue:[NSString stringWithFormat:@"%.0fmm/s", drone3g_sensitivities[i]*limits[i]]];
        }
    }

    for(int i=5;i<=21;i++) {
        [[controllerView viewWithTag:i] selectItemAtIndex:0];
        [[controllerView viewWithTag:i] setTextColor:[NSColor darkGrayColor]];
    }
    [[controllerView viewWithTag:26] selectItemAtIndex:0];
    [[controllerView viewWithTag:26] setTextColor:[NSColor darkGrayColor]];
    [[controllerView viewWithTag:27] selectItemAtIndex:0];
    [[controllerView viewWithTag:27] setTextColor:[NSColor darkGrayColor]];

    drone3g_button_map* drone3g_button_mapping = drone3g_get_button_mapping();
    
    for(int i=0;i<DRONE3G_NUM_FUNCTIONS;i++) {
        for(int j=0;j<drone3g_button_mapping[i].num_of_buttons;j++) {
            int tag = convertSDLButtonToTag(drone3g_button_mapping[i].buttons[j]);
            NSComboBox* currentBox = (NSComboBox*)[controllerView viewWithTag:tag];
            [currentBox selectItemAtIndex:i+1];
            
            if(i == 0) {
                [currentBox setTextColor:[NSColor blueColor]];
            } else if(i == 2) {
                [currentBox setTextColor:[NSColor greenColor]];
            } else if(i == 4) {
                [currentBox setTextColor:[NSColor redColor]];
            } else {
                [currentBox setTextColor:[NSColor blackColor]];
            }
        }
    }

    [[controllerView viewWithTag:13] selectItemAtIndex:1-drone3g_get_stick_layout()];
    [[controllerView viewWithTag:15] selectItemAtIndex:drone3g_get_stick_layout()];
    
    [[controllerView viewWithTag:13] setTextColor:[NSColor colorWithCalibratedRed:0.76f green:0.0f blue:0.07f alpha:1.0f]];
    [[controllerView viewWithTag:15] setTextColor:[NSColor colorWithCalibratedRed:0.76f green:0.0f blue:0.07f alpha:1.0f]];
    
    // Check if landing was set
    BOOL landExists = [(NSString*)[[preferences dictionaryForKey:@"ps3"] objectForKey:@"land"] length] > 0;
    
    // Check if takeoff was set
    BOOL takeoffExists = [(NSString*)[[preferences dictionaryForKey:@"ps3"] objectForKey:@"takeoff"] length] > 0;
    
    if(!landExists && !takeoffExists) {
        [_warningLabel setHidden:NO];
        [_warningLabel setStringValue:@"No takeoff and landing buttons!"];
        
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystickW.png"]];
    } else if(!landExists) {
        [_warningLabel setHidden:NO];
        [_warningLabel setStringValue:@"No landing button!"];
        
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystickW.png"]];
    } else if(!takeoffExists) {
        [_warningLabel setHidden:NO];
        [_warningLabel setStringValue:@"No takeoff button!"];
        
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystickW.png"]];
    } else {
        [_warningLabel setHidden:YES];
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystick.png"]];
    }
}

- (IBAction)showControllerHelp:(id)sender {
    [[Drone3GHelpWindowController sharedHelpController] switchHelp:DRONE3G_HELP_CONTROLLER];
}

- (IBAction)sliderDidChange:(id)sender {
    [[controllerView viewWithTag:[sender tag]] setFloatValue:[sender floatValue]]; // Updates sliders from dummy slider (in menu bar)
    
    NSTextField* label = (NSTextField*)[controllerView viewWithTag:[sender tag]+21];
    if([sender tag]+21 == 22) {
        [label setStringValue:[NSString stringWithFormat:@"%.1f˚", [sender floatValue]]];
    } else if([sender tag]+21 == 23) {
        [label setStringValue:[NSString stringWithFormat:@"%.0f˚/s", [sender floatValue]]];
    } else {
        [label setStringValue:[NSString stringWithFormat:@"%.0fmm/s", [sender floatValue]]];
    }
    
    NSEvent* event = [[NSApplication sharedApplication] currentEvent];
    if(event.type == NSLeftMouseUp && ![[sender toolTip] isEqualToString:@"UPDATE"]) { // Doesn't update preferences if updating from menu bar (done elsewhere)
        [self updateControllerPreferences];
    }
}

- (IBAction)resetDefaultSliders:(id)sender {
    for(int i=1;i<=4;i++) {
        NSSlider* slider = (NSSlider*)[controllerView viewWithTag:i];
        NSTextField* label = (NSTextField*)[controllerView viewWithTag:i+21];
        
        float value;
        switch (i) {
            case 1:
                value = 0.25f*30.0f;
                [label setStringValue:[NSString stringWithFormat:@"%.1f˚", value]];
                break;
            case 2:
                value = 0.23f*350;
                [label setStringValue:[NSString stringWithFormat:@"%.0f˚/s", value]];
                break;
            case 3:
                value = 0.60f*2000;
                [label setStringValue:[NSString stringWithFormat:@"%.0fmm/s", value]];
                break;
            case 4:
                value = 0.45f*2000;
                [label setStringValue:[NSString stringWithFormat:@"%.0fmm/s", value]];
                break;
        }
        
        [slider setFloatValue:value];
    }
    
    if([sender bezelStyle] == NSSmallSquareBezelStyle) { // So menu bar sensitivities can update
        [self updateControllerPreferences];
    }
}

- (IBAction)comboBoxDidChange:(id)sender {
    // Tags start at 5 (select) then go around clockwise to 21 (L1)
    NSInteger tag = [sender tag];
    NSComboBox* changedBox = (NSComboBox*)[currentView viewWithTag:tag];
    
    // Two sticks cannot have the same function
    if(tag == 15) {
        NSComboBox* rightStickBox = (NSComboBox*)[currentView viewWithTag:13];
        [rightStickBox selectItemAtIndex:1-[changedBox indexOfSelectedItem]];
    }
    if(tag == 13) {
        NSComboBox* leftStickBox = (NSComboBox*)[currentView viewWithTag:15];
        [leftStickBox selectItemAtIndex:1-[changedBox indexOfSelectedItem]];
    }
    
    [self updateControllerPreferences];
}

- (IBAction)resetDefaultController:(id)sender {
    // Tags start at 5 (select) then go around clockwise to 21 (L1) plus 26 and 27 (left and right stick clickers)
    int defaults[17] = {7,4,11,2,5,1,3,6,1,8,0,0,10,13,9,0,12};
    
    for(int i=5;i<=21;i++) {
        NSComboBox* currentBox = (NSComboBox*)[currentView viewWithTag:i];
        [currentBox selectItemAtIndex:defaults[i-5]];
    }
    [[currentView viewWithTag:26] selectItemAtIndex:0];
    [[currentView viewWithTag:27] selectItemAtIndex:0];
    
    [self updateControllerPreferences];
}

- (void)updateControllerPreferences {
    float* drone3g_sensitivities = drone3g_get_sensitivities_array();
    
    drone3g_lock_sensitivities_array();
    for(int i=0;i<4;i++) {
        drone3g_sensitivities[i] = [[controllerView viewWithTag:i+1] floatValue] / limits[i];
    }
    drone3g_unlock_sensitivities_array();
    
    drone3g_button_map* drone3g_button_mapping = drone3g_get_button_mapping();
    
    drone3g_lock_button_map();
    for(int i=5;i<=27;i++) {
        if(i == 13 || i == 15 || (i > 21 && i < 26) ) {
            continue;
        }
        
        NSComboBox* currentBox = (NSComboBox*)[controllerView viewWithTag:i];
        
        int sdl_button = convertTagToSDLButton(i);
        int index = 0;
        
        for(int j=0;j<DRONE3G_NUM_FUNCTIONS;j++) {
            for(int k=0;k<drone3g_button_mapping[j].num_of_buttons;k++) {
                if(sdl_button == drone3g_button_mapping[j].buttons[k]) {
                    index = j+1;
                    break;
                }
            }
            
            if(index != 0) {
                break;
            }
        }
        
        if(index != [currentBox indexOfSelectedItem]) {
            int selectedItem = (int)[currentBox indexOfSelectedItem];
            if(selectedItem == 5) {
                [currentBox setTextColor:[NSColor redColor]];
            } else if(selectedItem == 3) {
                [currentBox setTextColor:[NSColor greenColor]];
            } else if(selectedItem == 1 && i != 13 && i != 15) {
                [currentBox setTextColor:[NSColor blueColor]];
            } else {
                [currentBox setTextColor:[NSColor orangeColor]];
            }
            
            if(index == 0) { // Changed from None
                // Just add button index to function
                int function = (int)[currentBox indexOfSelectedItem]-1;
                
                drone3g_button_mapping[function].buttons[drone3g_button_mapping[function].num_of_buttons] = sdl_button;
                drone3g_button_mapping[function].num_of_buttons++;
            } else { // Changed from something to something else or None
                // Remove index
                index--;
                
                int state = 0;
                for(int j=0;j<drone3g_button_mapping[index].num_of_buttons;j++) {
                    if(state == 0) { // Scan for button index
                        if(drone3g_button_mapping[index].buttons[j] == sdl_button) {
                            // Switch to shifting to the left mode
                            state = 1;
                            j--;
                            
                            drone3g_button_mapping[index].num_of_buttons--;
                            
                            continue;
                        }
                    } else {
                        // Shift everything leftwards
                        drone3g_button_mapping[index].buttons[j] = drone3g_button_mapping[index].buttons[j+1];
                    }
                }
                
                // Then add it to the newly specified function or do nothing if None was the target function
                int function = (int)[currentBox indexOfSelectedItem]-1;
                if(function >= 0) {
                    drone3g_button_mapping[function].buttons[drone3g_button_mapping[function].num_of_buttons] = sdl_button;
                    drone3g_button_mapping[function].num_of_buttons++;
                }
            }
        }
    }
    drone3g_unlock_button_map();
    
    int stick_item = (int)[[controllerView viewWithTag:13] indexOfSelectedItem];
    if(stick_item == drone3g_get_stick_layout()) {
        [[controllerView viewWithTag:13] setTextColor:[NSColor orangeColor]];
        [[controllerView viewWithTag:15] setTextColor:[NSColor orangeColor]];
        
        drone3g_set_stick_layout(1-stick_item);
    }
    
    
    NSDictionary* controllerMap = convertControllerMap();
    [preferences setObject:controllerMap forKey:@"ps3"];
    
    // Check if landing was set
    BOOL landExists = [(NSString*)[controllerMap objectForKey:@"land"] length] > 0;
    
    // Check if takeoff was set
    BOOL takeoffExists = [(NSString*)[controllerMap objectForKey:@"takeoff"] length] > 0;
    
    if(!landExists && !takeoffExists) {
        [_warningLabel setHidden:NO];
        [_warningLabel setStringValue:@"No takeoff and landing buttons!"];
        
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystickW.png"]];
    } else if(!landExists) {
        [_warningLabel setHidden:NO];
        [_warningLabel setStringValue:@"No landing button!"];
        
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystickW.png"]];
    } else if(!takeoffExists) {
        [_warningLabel setHidden:NO];
        [_warningLabel setStringValue:@"No takeoff button!"];
        
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystickW.png"]];
    } else {
        [_warningLabel setHidden:YES];
        [[[toolbar visibleItems] objectAtIndex:1] setImage:[NSImage imageNamed:@"joystick.png"]];
    }
    
    
    [self saveSensitivities];
}

- (void)saveSensitivities {
    float* drone3g_sensitivities = drone3g_get_sensitivities_array();
    
    drone3g_lock_sensitivities_array();
    
    [preferences setFloat:drone3g_sensitivities[0] forKey:@"pitch+roll"];
    [preferences setFloat:drone3g_sensitivities[1] forKey:@"yaw"];
    [preferences setFloat:drone3g_sensitivities[2] forKey:@"climb"];
    [preferences setFloat:drone3g_sensitivities[3] forKey:@"descent"];
    
    drone3g_unlock_sensitivities_array();
    
    [preferences synchronize];
}

static void loadControllerMap(NSDictionary* prefDict) {
    drone3g_button_map* drone3g_button_mapping = drone3g_get_button_mapping();
    
    drone3g_lock_button_map();
    for(int i=0;i<DRONE3G_NUM_FUNCTIONS;i++) {
        NSArray* buttonArray = [[prefDict objectForKey:convertIndexToKey(i)] componentsSeparatedByString:@","];
        if(buttonArray == nil) {
            drone3g_button_mapping[i].num_of_buttons = 0;
            continue;
        }
        
        for(int j=0;j<[buttonArray count];j++) {
            drone3g_button_mapping[i].buttons[j] = [[buttonArray objectAtIndex:j] intValue];
        }
        
        drone3g_button_mapping[i].num_of_buttons = (int)[buttonArray count];
    }
    drone3g_unlock_button_map();
    
    drone3g_set_stick_layout([[prefDict objectForKey:@"stick-flip"] intValue]);
}

static NSDictionary* convertControllerMap() {
    NSMutableDictionary* controllerMap = [NSMutableDictionary dictionary];
    drone3g_button_map* drone3g_button_mapping = drone3g_get_button_mapping();
    
    for(int i=0;i<DRONE3G_NUM_FUNCTIONS;i++) {
        if(drone3g_button_mapping[i].num_of_buttons == 0) {
            continue;
        }
        
        NSNumber* buttons[drone3g_button_mapping[i].num_of_buttons];
        
        for(int j=0;j<drone3g_button_mapping[i].num_of_buttons;j++) {
            buttons[j] = [NSNumber numberWithInt:drone3g_button_mapping[i].buttons[j]];
        }
        
        NSArray* buttonArray = [NSArray arrayWithObjects:buttons count:drone3g_button_mapping[i].num_of_buttons];
        NSString* buttonString = [buttonArray componentsJoinedByString:@","];
        
        [controllerMap setObject:buttonString forKey:convertIndexToKey(i)];
    }
    
    [controllerMap setObject:[NSString stringWithFormat:@"%i", drone3g_get_stick_layout()] forKey:@"stick-flip"];
    
    return controllerMap;
}

static NSString* convertIndexToKey(int index) {
    switch (index) {
        case 0:
            return @"land";
        case 1:
            return @"hover";
        case 2:
            return @"takeoff";
        case 3:
            return @"trim";
        case 4:
            return @"emergency";
        case 5:
            return @"switch-cam";
        case 6:
            return @"calib";
        case 7:
            return @"flyhome";
        case 8:
            return @"read-bat";
        case 9:
            return @"sethome";
        case 10:
            return @"picture";
        case 11:
            return @"record";
        case 12:
            return @"read-ping";
            
        default:
            return @"";
    }
}

static int convertSDLButtonToTag(int button_num) {
    switch (button_num) {
        case 0:
            return 5;
        case 1:
            return 26;
        case 2:
            return 27;
        case 3:
            return 6;
        case 4:
            return 19;
        case 5:
            return 16;
        case 6:
            return 17;
        case 7:
            return 18;
        case 8:
            return 20;
        case 9:
            return 8;
        case 10:
            return 21;
        case 11:
            return 7;
        case 12:
            return 9;
        case 13:
            return 10;
        case 14:
            return 11;
        case 15:
            return 12;
        case 16:
            return 14;
            
        default:
            printf("Invalid SDL button index %i\n", button_num);
            syslog(LOG_ERR, "Invalid SDL button index %i\n", button_num);
            return -1;
    }
}

static int convertTagToSDLButton(int tag) {
    switch (tag) {
        case 5:
            return 0;
        case 6:
            return 3;
        case 7:
            return 11;
        case 8:
            return 9;
        case 9:
            return 12;
        case 10:
            return 13;
        case 11:
            return 14;
        case 12:
            return 15;
        case 14:
            return 16;
        case 16:
            return 5;
        case 17:
            return 6;
        case 18:
            return 7;
        case 19:
            return 4;
        case 20:
            return 8;
        case 21:
            return 10;
        case 26:
            return 1;
        case 27:
            return 2;
            
        default:
            syslog(LOG_ERR, "Invalid tag %i\n", tag);
            return -1;
    }
}

#pragma mark -
#pragma mark HUD View
#pragma mark -

- (IBAction)inclinometerStateDidChange:(id)sender {
    NSMutableDictionary* hudDict = [NSMutableDictionary dictionaryWithDictionary:[preferences objectForKey:@"HUD"]];

    BOOL renders = ([sender state] == NSOnState);
    [hudDict setObject:[NSNumber numberWithBool:renders] forKey:@"inc_visible"];
    
    [[hudView viewWithTag:100] setHidden:!renders];
    [appDelegate changeInclinometerState:renders];
    
    [preferences setObject:hudDict forKey:@"HUD"];
    [preferences synchronize];
}

- (IBAction)colorSelected:(id)sender {
    CIColor* color = [CIColor colorWithCGColor:[[sender color] CGColor]];
    
    CIFilter* filter = [CIFilter filterWithName:@"CIFalseColor"];
    [filter setDefaults];
    [filter setValue:color forKey:@"inputColor0"];
    [filter setValue:color forKey:@"inputColor1"];
    
    [[hudImageView layer] setFilters:@[filter]];
    [[[hudView viewWithTag:100] layer] setFilters:@[filter]];
    
    [[hudView viewWithTag:1] setTextColor:[sender color]];
    [[hudView viewWithTag:2] setTextColor:[sender color]];
    [[hudView viewWithTag:10] setTextColor:[sender color]];
    [[hudView viewWithTag:11] setTextColor:[sender color]];
    
    [appDelegate changeHUDColor:[sender color]];
    
    NSMutableDictionary* hudDict = [NSMutableDictionary dictionaryWithDictionary:[preferences objectForKey:@"HUD"]];
    [hudDict setObject:[NSArchiver archivedDataWithRootObject:[sender color]] forKey:@"color"];
    
    [preferences setObject:hudDict forKey:@"HUD"];
    
    [preferences synchronize];
}

- (IBAction)unitsDidChange:(id)sender {
    NSMutableDictionary* hudDict = [NSMutableDictionary dictionaryWithDictionary:[preferences objectForKey:@"HUD"]];
    
    if([sender tag] == 3) {
        NSString* unitString = ([[sender selectedCell] tag] % 2) ? @"m" : @"ft";
        [[hudView viewWithTag:1] setStringValue:unitString];
        
        [hudDict setObject:unitString forKey:@"altitude"];
    } else if([sender tag] == 4) {
        NSString* unitString = ([[sender selectedCell] tag] % 2) ? @"km/h" : @"mph";
        [[hudView viewWithTag:2] setStringValue:unitString];
        [[hudView viewWithTag:10] setStringValue:[NSString stringWithFormat:@"Wind: 0.0 %@", unitString]];
        
        [hudDict setObject:unitString forKey:@"speed"];
    } else {
        NSString* unitString = ([[sender selectedCell] tag] % 2) ? @"m" : @"ft";
        [[hudView viewWithTag:11] setStringValue:[NSString stringWithFormat:@"Distance: 0%@", unitString]];
        
        [hudDict setObject:unitString forKey:@"distance"];
    }
    
    [preferences setObject:hudDict forKey:@"HUD"];
    [preferences synchronize];
}

- (void)setupHUDView {
    NSDictionary* hudDict = [preferences objectForKey:@"HUD"];
    
    // Set HUD color
    NSColor* hudColor = [NSUnarchiver unarchiveObjectWithData:[hudDict objectForKey:@"color"]];
    [[hudView viewWithTag:6] setColor:hudColor];
    
    CIColor* color = [CIColor colorWithCGColor:[hudColor CGColor]];
    CIFilter* filter = [CIFilter filterWithName:@"CIFalseColor"];
    [filter setDefaults];
    [filter setValue:color forKey:@"inputColor0"];
    [filter setValue:color forKey:@"inputColor1"];
    
    [[hudImageView layer] setFilters:@[filter]];
    [[[hudView viewWithTag:100] layer] setFilters:@[filter]];
    
    [[hudView viewWithTag:1] setTextColor:hudColor];
    [[hudView viewWithTag:2] setTextColor:hudColor];
    [[hudView viewWithTag:10] setTextColor:hudColor];
    [[hudView viewWithTag:11] setTextColor:hudColor];
    
    // Set inclinometer checkbox and visibillity
    BOOL isInclinometerVisible = [[hudDict objectForKey:@"inc_visible"] boolValue];
    [[hudView viewWithTag:99] setState:(isInclinometerVisible) ? NSOnState : NSOffState];
    [[hudView viewWithTag:100] setHidden:!isInclinometerVisible];
    
    // Set units
    [[hudView viewWithTag:1] setStringValue:[hudDict objectForKey:@"altitude"]];
    [[hudView viewWithTag:2] setStringValue:[hudDict objectForKey:@"speed"]];
    [[hudView viewWithTag:11] setStringValue:[NSString stringWithFormat:@"Wind: 0.0 %@", [hudDict objectForKey:@"speed"]]];
    [[hudView viewWithTag:11] setStringValue:[NSString stringWithFormat:@"Distance: 0%@", [hudDict objectForKey:@"distance"]]];
    
    BOOL metricAltitude = [[hudDict objectForKey:@"altitude"] isEqualToString:@"m"];
    BOOL metricSpeed = [[hudDict objectForKey:@"speed"] isEqualToString:@"km/h"];
    BOOL metricDistance = [[hudDict objectForKey:@"distance"] isEqualToString:@"m"];
    
    [[hudView viewWithTag:3] selectCellWithTag:8 - metricAltitude];
    [[hudView viewWithTag:4] selectCellWithTag:10 - metricSpeed];
    [[hudView viewWithTag:5] selectCellWithTag:12 - metricDistance];
}

- (NSString*)altitudeUnits {
    return [[preferences objectForKey:@"HUD"] objectForKey:@"altitude"];
}

- (NSString*)speedUnits {
    return [[preferences objectForKey:@"HUD"] objectForKey:@"speed"];
}

- (NSString*)distanceUnits {
    return [[preferences objectForKey:@"HUD"] objectForKey:@"distance"];
}

- (NSColor*)currentHUDColor {
    return [NSUnarchiver unarchiveObjectWithData:[[preferences objectForKey:@"HUD"] objectForKey:@"color"]];
}

- (BOOL)shouldRenderInclinometer {
    return [[[preferences objectForKey:@"HUD"] objectForKey:@"inc_visible"] boolValue];
}

#pragma mark -
#pragma mark Fly Home View
#pragma mark -

- (void)setupFlyHomeView {
    NSDictionary* flyhomeDict = [preferences objectForKey:@"CLoss"];
    
    connectionLostMode = DRONE3G_CLMODE_LAND;
    
    landTimeout = [[flyhomeDict objectForKey:@"land-timeout"] intValue];
    flyHomeTimeout = [[flyhomeDict objectForKey:@"flyhome-timeout"] intValue];
    flyHomeAltitude = [[flyhomeDict objectForKey:@"flyhome-altitude"] intValue];
    
    [[flyHomeView viewWithTag:1] setStringValue:[NSString stringWithFormat:@"%d", landTimeout]];
    [[flyHomeView viewWithTag:2] setIntValue:landTimeout];
    
    [[flyHomeView viewWithTag:5] setStringValue:[NSString stringWithFormat:@"%d", flyHomeTimeout]];
    [[flyHomeView viewWithTag:6] setIntValue:flyHomeTimeout];
    
    // OS X Yosemite uses a different system font which causes the first IMPORTANT: label to be shifted
    // leftwards in previous versions of OS X . This can probably be solved by using auto-layout but
    // since that probably will never be implented in this project this pragmatic check will fix it.
    
    NSDictionary* systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString* systemVersion = [systemVersionDictionary objectForKey:@"ProductVersion"];
    
    if(![[[systemVersion componentsSeparatedByString:@"."] objectAtIndex:1] isEqualToString:@"10"]) { // Check for OS X Yosemite
        NSPoint headerOrigin = [[flyHomeView viewWithTag:101] frame].origin;
        NSSize headerSize = [[flyHomeView viewWithTag:101] frame].size;
        
        NSPoint fixedOrigin = NSMakePoint(headerOrigin.x + 299.0f/694.0f * headerSize.width, headerOrigin.y + 15.0f/54.0f * headerSize.height);
        
        [[flyHomeView viewWithTag:100] setFrameOrigin:fixedOrigin];
    }
}

- (IBAction)modeDidChange:(id)sender {
    connectionLostMode = (int)[[sender selectedCell] tag];
}

- (IBAction)landTimeoutDidChange:(id)sender {
    NSCharacterSet* nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSRange r = [[sender stringValue] rangeOfCharacterFromSet: nonNumbers];
    
    if(r.location != NSNotFound) {
        [sender setStringValue:[[flyHomeView viewWithTag:3-[sender tag]] stringValue]];
        return;
    }
    
    if([sender intValue] > 1000) {
        [sender setStringValue:@"1000"];
    }
    
    [[flyHomeView viewWithTag:3-[sender tag]] setStringValue:[sender stringValue]];
    
    landTimeout = [sender intValue];
    
    [self saveConnectionLossPreferences];
}

- (IBAction)flyHomeTimeoutDidChange:(id)sender {
    NSCharacterSet* nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSRange r = [[sender stringValue] rangeOfCharacterFromSet: nonNumbers];
    
    if(r.location != NSNotFound) {
        [sender setStringValue:[[flyHomeView viewWithTag:11-[sender tag]] stringValue]];
        return;
    }
    
    if([sender intValue] > 1000) {
        [sender setStringValue:@"1000"];
    }
    
    [[flyHomeView viewWithTag:11-[sender tag]] setStringValue:[sender stringValue]];
    
    flyHomeTimeout = [sender intValue];
    
    [self saveConnectionLossPreferences];
}

- (IBAction)flyHomeAltitudeDidChange:(id)sender {
    NSCharacterSet* nonNumbers = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSRange r = [[sender stringValue] rangeOfCharacterFromSet: nonNumbers];
    
    if(r.location != NSNotFound) {
        [sender setStringValue:[[flyHomeView viewWithTag:7-[sender tag]] stringValue]];
        return;
    }
    
    if([sender intValue] > (int)[[flyHomeView viewWithTag:4] maxValue]) {
        [sender setStringValue:[NSString stringWithFormat:@"%i", (int)[[flyHomeView viewWithTag:4] maxValue]]];
    }
    if([sender intValue] < (int)[[flyHomeView viewWithTag:4] minValue]) {
        [sender setStringValue:[NSString stringWithFormat:@"%i", (int)[[flyHomeView viewWithTag:4] minValue]]];
    }
    
    [[flyHomeView viewWithTag:7-[sender tag]] setStringValue:[sender stringValue]];
    
    flyHomeAltitude = [sender intValue] * ( ([[self altitudeUnits] isEqualToString:@"ft"]) ? 304.8 : 1000);
    
    [self saveConnectionLossPreferences];
}

- (void)saveConnectionLossPreferences {
    NSMutableDictionary* flyHomeDict = [NSMutableDictionary dictionaryWithDictionary:[preferences objectForKey:@"CLoss"]];
    
    [flyHomeDict setObject:[NSNumber numberWithInt:landTimeout] forKey:@"land-timeout"];
    [flyHomeDict setObject:[NSNumber numberWithInt:flyHomeTimeout] forKey:@"flyhome-timeout"];
    [flyHomeDict setObject:[NSNumber numberWithInt:flyHomeAltitude] forKey:@"flyhome-altitude"];
    
    [preferences setObject:flyHomeDict forKey:@"CLoss"];
    [preferences synchronize];
    
    drone3g_flyhome_settings_changed_callback(connectionLostMode, landTimeout, flyHomeTimeout, flyHomeAltitude);
}

- (void)enableFlyHome {
    [[[flyHomeView viewWithTag:7] cellAtRow:1 column:0] setEnabled:YES];
}

- (void)disableFlyHome {
    [[[flyHomeView viewWithTag:7] cellAtRow:1 column:0] setEnabled:NO];
}

#pragma mark -
#pragma mark Drone Wifi Communication Functions
#pragma mark -


static void connection_established_callback() {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[[Drone3GPREFWindowController sharedPreferencesController] carrierView] viewWithTag:1] setEnabled:YES];
        [[[[Drone3GPREFWindowController sharedPreferencesController] loginView]   viewWithTag:1] setEnabled:YES];
    });
}

- (void)connectARDrone {
    drone3g_installer_status status = drone3g_installer_get_status() >> 2;
    if(status & DRONE3G_INSTALLER_STATUS_CONNECTED) {
        [[carrierView viewWithTag:1] setEnabled:YES];
        [[loginView viewWithTag:1]   setEnabled:YES];
        
        return;
    }
    
    [[carrierView viewWithTag:1] setEnabled:NO];
    [[loginView viewWithTag:1]   setEnabled:NO];
    
    if(!(status & DRONE3G_INSTALLER_STATUS_INSTALLING) && !(status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
        drone3g_installer_connect(DRONE3G_CONNECT_TYPE_UNINSTALL, &connection_established_callback);
    }
}


#pragma mark -
#pragma mark Carrier View
#pragma mark -

- (IBAction)showCarrierHelp:(id)sender {
    [[Drone3GHelpWindowController sharedHelpController] switchHelp:DRONE3G_HELP_CSETS];
}

- (void)setupCarrierView {
    NSDictionary* carrierDict = [preferences objectForKey:@"CARRIER"];
    
    BOOL automatic = [[carrierDict objectForKey:@"automatic"] boolValue];
    [[carrierView viewWithTag:5] setState:(automatic) ? NSOnState : NSOffState];
    
    if(automatic) {
        [[carrierView viewWithTag:2] setEnabled:NO];
        [[carrierView viewWithTag:3] setEnabled:NO];
        [[carrierView viewWithTag:4] setEnabled:NO];
        
        [[carrierView viewWithTag:6] setTextColor:[NSColor disabledControlTextColor]];
        [[carrierView viewWithTag:7] setTextColor:[NSColor disabledControlTextColor]];
        [[carrierView viewWithTag:8] setTextColor:[NSColor disabledControlTextColor]];
    } else {
        [[carrierView viewWithTag:2] setEnabled:YES];
        [[carrierView viewWithTag:3] setEnabled:YES];
        [[carrierView viewWithTag:4] setEnabled:YES];
        
        [[carrierView viewWithTag:6] setTextColor:[NSColor controlTextColor]];
        [[carrierView viewWithTag:7] setTextColor:[NSColor controlTextColor]];
        [[carrierView viewWithTag:8] setTextColor:[NSColor controlTextColor]];
    }
    
    NSString* apnString = [carrierDict objectForKey:@"APN"];
    NSString* userString = [carrierDict objectForKey:@"username"];
    NSString* passwordString = [carrierDict objectForKey:@"password"];
    
    [[carrierView viewWithTag:2] setStringValue:apnString];
    [[carrierView viewWithTag:3] setStringValue:userString];
    [[carrierView viewWithTag:4] setStringValue:passwordString];
}

- (IBAction)changeCarrierSettingsMode:(id)sender {
    if([sender state] == NSOnState) {
        [[carrierView viewWithTag:2] setEnabled:NO];
        [[carrierView viewWithTag:3] setEnabled:NO];
        [[carrierView viewWithTag:4] setEnabled:NO];
        
        [[carrierView viewWithTag:6] setTextColor:[NSColor disabledControlTextColor]];
        [[carrierView viewWithTag:7] setTextColor:[NSColor disabledControlTextColor]];
        [[carrierView viewWithTag:8] setTextColor:[NSColor disabledControlTextColor]];
    } else {
        [[carrierView viewWithTag:2] setEnabled:YES];
        [[carrierView viewWithTag:3] setEnabled:YES];
        [[carrierView viewWithTag:4] setEnabled:YES];
        
        [[carrierView viewWithTag:6] setTextColor:[NSColor controlTextColor]];
        [[carrierView viewWithTag:7] setTextColor:[NSColor controlTextColor]];
        [[carrierView viewWithTag:8] setTextColor:[NSColor controlTextColor]];
    }
    
    NSMutableDictionary* carrierDict = [NSMutableDictionary dictionaryWithDictionary:[preferences objectForKey:@"CARRIER"]];
    [carrierDict setObject:[NSNumber numberWithBool:([sender state] == NSOnState)] forKey:@"automatic"];
    [preferences setObject:carrierDict forKey:@"CARRIER"];
    
    [preferences synchronize];
}

- (IBAction)sync:(id)sender {
    drone3g_installer_status status = drone3g_installer_get_status() >> 2;

    if((status & DRONE3G_INSTALLER_STATUS_INSTALLING) || (status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
        NSString* mText = [NSString stringWithFormat:@"You can't sync the drone while %s.", (status & DRONE3G_INSTALLER_STATUS_INSTALLING) ? "installing" : "uninstalling"];
        NSAlert* alert = [NSAlert alertWithMessageText:mText defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Wait for the %s to complete before synching your drone.", (status & DRONE3G_INSTALLER_STATUS_INSTALLING) ? "install" : "uninstall"];
        
        [[NSSound soundNamed:@"Basso"] play];
        [alert runModal];
        
        return;
    }
    
    NSString* apnString = [[carrierView viewWithTag:2] stringValue];
    NSString* userString = [[carrierView viewWithTag:3] stringValue];
    NSString* passwordString = [[carrierView viewWithTag:4] stringValue];
    BOOL automatic = ([[carrierView viewWithTag:5] state] == NSOnState);
    
    if(automatic) {
        char apn[64] = {0};
        char username[32] = {0};
        char password[32] = {0};
        
        int ret = drone3g_get_carrier_settings(apn, username, password);
        
        apnString = [NSString stringWithCString:apn encoding:NSUTF8StringEncoding];
        userString = [NSString stringWithCString:username encoding:NSUTF8StringEncoding];
        passwordString = [NSString stringWithCString:password encoding:NSUTF8StringEncoding];
        
        [[carrierView viewWithTag:2] setStringValue:apnString];
        [[carrierView viewWithTag:3] setStringValue:userString];
        [[carrierView viewWithTag:4] setStringValue:passwordString];
        
        NSString* mText = [NSString stringWithFormat:@"Sync %s.", (ret == 0) ? "successful" : "failed"];
        NSAlert* alert = [NSAlert alertWithMessageText:mText defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:(ret == 0) ? @"Your carrier settings have been set." : @"Connection was lost to the drone while syncing carrier settings.\n\nReconnect and try again."];
        
        [[NSSound soundNamed:(ret == 0) ? @"Hero" : @"Basso"] play];
        [alert runModal];
        
        if(ret < 0) {
            status = drone3g_installer_get_status() >> 2;
            if(!(status & DRONE3G_INSTALLER_STATUS_INSTALLING) && !(status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
                drone3g_installer_stop_connecting();
                [self connectARDrone];
            }
            
            return;
        }
    } else {
        int ret = drone3g_set_carrier_settings([apnString UTF8String], [userString UTF8String], [passwordString UTF8String]);
        if(ret < 0) {
            status = drone3g_installer_get_status() >> 2;
            if(!(status & DRONE3G_INSTALLER_STATUS_INSTALLING) && !(status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
                drone3g_installer_stop_connecting();
                [self connectARDrone];
            }
        }
        
        NSString* mText = [NSString stringWithFormat:@"Sync %s.", (ret == 0) ? "successful" : "failed"];
        NSAlert* alert = [NSAlert alertWithMessageText:mText defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:(ret == 0) ? @"Your carrier settings have been set." : @"Connection was lost to the drone while syncing carrier settings.\n\nReconnect and try again."];
        
        [[NSSound soundNamed:(ret == 0) ? @"Hero" : @"Basso"] play];
        [alert runModal];
    }
    
    NSDictionary* carrierDict = [NSDictionary dictionaryWithObjectsAndKeys:apnString, @"APN", userString, @"username", passwordString, @"password", [NSNumber numberWithBool:automatic], @"automatic", nil];
    [preferences setObject:carrierDict forKey:@"CARRIER"];
    
    [preferences synchronize];
}

#pragma mark -
#pragma mark Login Information
#pragma mark -

- (IBAction)showLoginHelp:(id)sender {
    [[Drone3GHelpWindowController sharedHelpController] switchHelp:DRONE3G_HELP_LOGIN];
}

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

- (IBAction)sendCredentials:(id)sender {
    // Check to make sure credentials support UTF8 encoding
    NSString* username  = [[loginView viewWithTag:2] stringValue];
    NSString* password  = [[loginView viewWithTag:3] stringValue];
    NSString* droneName = [[loginView viewWithTag:4] stringValue];
    
    if(![username canBeConvertedToEncoding:NSUTF8StringEncoding] || ![password canBeConvertedToEncoding:NSUTF8StringEncoding] || ![droneName canBeConvertedToEncoding:NSUTF8StringEncoding]) {
        [self shakeWindow];
        [[NSSound soundNamed:@"Basso"] play];
        
        return;
    }
    
    // Make sure user is not doing something dumb while syncing like install or uninstall
    drone3g_installer_status status = drone3g_installer_get_status() >> 2;
    
    if((status & DRONE3G_INSTALLER_STATUS_INSTALLING) || (status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
        NSString* mText = [NSString stringWithFormat:@"You can't sync the drone while %s.", (status & DRONE3G_INSTALLER_STATUS_INSTALLING) ? "installing" : "uninstalling"];
        NSAlert* alert = [NSAlert alertWithMessageText:mText defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Wait for the %s to complete before synching your drone.", (status & DRONE3G_INSTALLER_STATUS_INSTALLING) ? "install" : "uninstall"];
        
        [[NSSound soundNamed:@"Basso"] play];
        [alert runModal];
        
        return;
    }
    
    // Sync credentials to drone
    int ret = drone3g_set_credentials([username UTF8String], [password UTF8String], [droneName UTF8String]);
    if(ret < 0) {
        status = drone3g_installer_get_status() >> 2;
        if(!(status & DRONE3G_INSTALLER_STATUS_INSTALLING) && !(status & DRONE3G_INSTALLER_STATUS_UNINSTALLING)) {
            drone3g_installer_stop_connecting();
            [self connectARDrone];
        }
    }
    
    NSString* mText = [NSString stringWithFormat:@"Sync %s.", (ret == 0) ? "successful" : "failed"];
    NSAlert* alert = [NSAlert alertWithMessageText:mText defaultButton:@"Ok" alternateButton:nil otherButton:nil informativeTextWithFormat:(ret == 0) ? @"Your login information has been set." : @"Connection was lost to the drone while syncing login information.\n\nReconnect and try again."];
    
    [[NSSound soundNamed:(ret == 0) ? @"Hero" : @"Basso"] play];
    [alert runModal];
}

#pragma mark -
#pragma mark Media Removal Suppression
#pragma mark -

- (void)setMediaRemovalWarning:(BOOL)suppression {
    [preferences setObject:[NSNumber numberWithBool:suppression] forKey:@"media_supress"];
    [preferences synchronize];
}

- (BOOL)shouldSuppressMediaRemovalWarning {
    return [[preferences objectForKey:@"media_supress"] boolValue];
}

@end
