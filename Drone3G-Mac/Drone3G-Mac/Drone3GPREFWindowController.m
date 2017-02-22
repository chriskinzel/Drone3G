//
//  Drone3GPREFWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-14.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GPREFWindowController.h"
#import "Drone3GAppDelegate.h"
#import "drone_main.h"

@implementation Drone3GPREFWindowController

@synthesize toolbar;
@synthesize controllerView;
@synthesize hudView;
@synthesize flyHomeView;
@synthesize mainView;

#pragma mark -
#pragma mark Initialization
#pragma mark -

- (id)init {
    self = [super initWithWindowNibName:@"PreferencesWindow"];
    if(self) {
        appDelegate = (Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate];
        
        // Load preferences
        preferences = [NSUserDefaults standardUserDefaults];
        NSDictionary* controllerDict = [NSDictionary dictionaryWithObjectsAndKeys:@"13", @"land", @"9", @"hover", @"14", @"takeoff", @"3", @"trim", @"12", @"emergency", @"15", @"switch-cam", @"0", @"stick-flip", @"0", @"calib", nil];
        NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:0.25f], @"pitch+roll", [NSNumber numberWithFloat:0.23f], @"yaw", [NSNumber numberWithFloat:0.50f], @"climb", [NSNumber numberWithFloat:0.351f], @"descent", controllerDict, @"ps3", nil];
        [preferences registerDefaults:dict];
        
        loadControllerMap([preferences dictionaryForKey:@"ps3"]);
        
        drone3g_sensitivities[0] = [preferences floatForKey:@"pitch+roll"];
        drone3g_sensitivities[1] = [preferences floatForKey:@"yaw"];
        drone3g_sensitivities[2] = [preferences floatForKey:@"climb"];
        drone3g_sensitivities[3] = [preferences floatForKey:@"descent"];
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
    [self setupControllerView];
    
    [toolbar setSelectedItemIdentifier:@"Controllers"];
    
    [[self window] setContentSize:[controllerView frame].size];
    [mainView setFrameSize:[controllerView frame].size];
    
    [mainView addSubview:controllerView];
    [mainView setWantsLayer:YES];
    
    currentView = controllerView;
}

- (void)showWindow:(id)sender {
    if(controllerView != nil) {
        [self setupControllerView];
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
        
        NSAlert* alert = [NSAlert alertWithMessageText:titleString defaultButton:@"Continue thats fine" alternateButton:@"Go back and fix" otherButton:nil informativeTextWithFormat:@"%@", messageString];
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
    
    return YES;
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
        default:
            return;
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
}

#pragma mark -
#pragma mark Controller View
#pragma mark -

- (void)setupControllerView {
    for(int i=0;i<4;i++) {
        [[controllerView viewWithTag:i+1] setFloatValue:drone3g_sensitivities[i]];
        [[controllerView viewWithTag:i+22] setFloatValue:drone3g_sensitivities[i]];
    }
    
    for(int i=5;i<=21;i++) {
        [[controllerView viewWithTag:i] selectItemAtIndex:0];
        [[controllerView viewWithTag:i] setTextColor:[NSColor darkGrayColor]];
    }
    [[controllerView viewWithTag:26] selectItemAtIndex:0];
    [[controllerView viewWithTag:26] setTextColor:[NSColor darkGrayColor]];
    [[controllerView viewWithTag:27] selectItemAtIndex:0];
    [[controllerView viewWithTag:27] setTextColor:[NSColor darkGrayColor]];
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
    
    [[controllerView viewWithTag:13] selectItemAtIndex:1-drone3g_stick_layout];
    [[controllerView viewWithTag:15] selectItemAtIndex:drone3g_stick_layout];
    
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

- (IBAction)sliderDidChange:(id)sender {
    [[controllerView viewWithTag:[sender tag]] setFloatValue:[sender floatValue]]; // Updates sliders from dummy slider (in menu bar)
    
    NSTextField* label = (NSTextField*)[controllerView viewWithTag:[sender tag]+21];
    [label setFloatValue:[sender floatValue]];
    
    NSEvent* event = [[NSApplication sharedApplication] currentEvent];
    if(event.type == NSLeftMouseUp && ![[sender toolTip] isEqualToString:@"UPDATE"]) { // Doesn't update preferences if updating from menu bar (done elsewhere)
        [self updatePreferences];
    }
}

- (IBAction)resetDefaultSliders:(id)sender {
    for(int i=1;i<=4;i++) {
        NSSlider* slider = (NSSlider*)[controllerView viewWithTag:i];
        NSTextField* label = (NSTextField*)[controllerView viewWithTag:i+21];
        
        float value;
        switch (i) {
            case 1:
                value = 0.25f;
                break;
            case 2:
                value = 0.23f;
                break;
            case 3:
                value = 0.50f;
                break;
            case 4:
                value = 0.351f;
                break;
        }
        
        [slider setFloatValue:value];
        [label setFloatValue:value];
    }
    
    if([sender bezelStyle] == NSSmallSquareBezelStyle) { // So menu bar sensitivities can update
        [self updatePreferences];
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
    
    [self updatePreferences];
}

- (IBAction)resetDefaultController:(id)sender {
    // Tags start at 5 (select) then go around clockwise to 21 (L1) plus 26 and 27 (left and right stick clickers)
    int defaults[17] = {7,4,0,2,5,1,3,6,1,0,0,0,0,0,0,0,0};
    
    for(int i=5;i<=21;i++) {
        NSComboBox* currentBox = (NSComboBox*)[currentView viewWithTag:i];
        [currentBox selectItemAtIndex:defaults[i-5]];
    }
    [[currentView viewWithTag:26] selectItemAtIndex:0];
    [[currentView viewWithTag:27] selectItemAtIndex:0];
    
    [self updatePreferences];
}

- (void)updatePreferences {
    for(int i=0;i<4;i++) {
        drone3g_sensitivities[i] = [[controllerView viewWithTag:i+1] floatValue];
    }
    
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
    
    int stick_item = (int)[[controllerView viewWithTag:13] indexOfSelectedItem];
    if(stick_item == drone3g_stick_layout) {
        [[controllerView viewWithTag:13] setTextColor:[NSColor orangeColor]];
        [[controllerView viewWithTag:15] setTextColor:[NSColor orangeColor]];
        
        drone3g_stick_layout = 1-stick_item;
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
    [preferences setFloat:drone3g_sensitivities[0] forKey:@"pitch+roll"];
    [preferences setFloat:drone3g_sensitivities[1] forKey:@"yaw"];
    [preferences setFloat:drone3g_sensitivities[2] forKey:@"climb"];
    [preferences setFloat:drone3g_sensitivities[3] forKey:@"descent"];
    
    [preferences synchronize];
}

static void loadControllerMap(NSDictionary* prefDict) {
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
    
    drone3g_stick_layout = [[prefDict objectForKey:@"stick-flip"] intValue];
}

static NSDictionary* convertControllerMap() {
    NSMutableDictionary* controllerMap = [NSMutableDictionary dictionary];
    
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
    
    [controllerMap setObject:[NSString stringWithFormat:@"%i", drone3g_stick_layout] forKey:@"stick-flip"];
    
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
            printf("[ERROR] Invalid SDL button index %i\n", button_num);
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
            printf("[ERROR] Invalid tag %i\n", tag);
            return -1;
    }
}

@end
