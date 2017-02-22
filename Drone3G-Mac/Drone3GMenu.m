//
//  Drone3GMenu.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-24.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GMenu.h"
#import "Drone3GAppDelegate.h"

@implementation Drone3GMenu

@synthesize didTransistionOut;
@synthesize menuState;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        didTransistionOut = NO;
        menuState = DRONE3G_MENU_STATE_MAIN;
    }
    return self;
}

- (void)awakeFromNib {
    // Yosemite seems to have changed the color profile making the main splash image look to dark
    NSDictionary* systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString* systemVersion = [systemVersionDictionary objectForKey:@"ProductVersion"];
    
    if([[[systemVersion componentsSeparatedByString:@"."] objectAtIndex:1] isEqualToString:@"10"]) { // Check for OS X Yosemite
        NSImage* yoseImage = [NSImage imageNamed:@"main_yose.png"];
        [[self viewWithTag:1] setImage:yoseImage];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

- (void)mouseDown:(NSEvent *)theEvent {
    dragPoint = [theEvent locationInWindow];
    lastPoint = dragPoint;
    maxSpeed = 0.0f;
    
    [[(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] window] makeKeyAndOrderFront:nil];
}

- (void)mouseDragged:(NSEvent *)theEvent {
    if(!didTransistionOut) {
        return;
    }
    
    BOOL moreThanOneJump = (menuState == DRONE3G_MENU_STATE_FLYING);
    
    NSPoint mouseLocation = [theEvent locationInWindow];
    float delta = dragPoint.x - mouseLocation.x;
    
    float speed = fabsf(mouseLocation.x - lastPoint.x);
    if(speed > maxSpeed) {
        maxSpeed = speed;
    }
    
    if(delta > [self window].frame.size.width/6 && maxSpeed > 50.0f) {
        [(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] menuWillAnimateIn];
        menuState = DRONE3G_MENU_STATE_MAIN;
        
        [[NSSound soundNamed:@"back.mp3"] play];
        
        NSView* imageView = [self viewWithTag:1];
        BOOL animateBackground = [imageView isHidden];
        if(animateBackground) {
            [imageView setHidden:NO];
        }
        
        BOOL animateTitle = [[[(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] connectionLabel] stringValue] isEqualToString:@"Connection lost awaiting reconnection..."];
        [[self viewWithTag:2] setHidden:NO];
        
        for(NSView* subview in [self subviews]) {
            if([[subview identifier] isEqualToString:@"HUD"] || (!animateBackground && [subview tag] == 1) || (!animateTitle && [subview tag] == 2) ) {
                continue;
            }
            
            [NSAnimationContext beginGrouping];
            [[NSAnimationContext currentContext] setDuration:1.2f];
            
            [[subview animator] setFrameOrigin:NSMakePoint(subview.frame.origin.x - [subview window].frame.size.width * ( (moreThanOneJump && [subview tag] != 1 && [subview tag] != 2) ? 2.0f : 1.0f), subview.frame.origin.y)];
            
            [NSAnimationContext endGrouping];
        }
        
        didTransistionOut = NO;
    }
    
    lastPoint = mouseLocation;
}

- (void)animateOut {
    int end_index = 3;
    
    BOOL dontMoveTitle = (![[[(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] connectionLabel] stringValue] isEqualToString:@"Connection lost awaiting reconnection..."] || menuState == DRONE3G_MENU_STATE_MAIN);
    if(dontMoveTitle) {
        end_index = 2;
    }
    
    for(NSView* subview in [self subviews]) {
        if([subview tag] == 1 || ([subview tag] == 2 && dontMoveTitle) || [[subview identifier] isEqualToString:@"HUD"]) {
            continue;
        }
        
        // Make sure console is in correct position
        if([[subview identifier] rangeOfString:@"CONSOLE"].location != NSNotFound) {
            [subview setFrameOrigin:NSMakePoint([subview window].frame.size.width/2 - [subview frame].size.width/2, [subview frame].origin.y)];
            continue;
        }
        
        float delay = sqrtf([[subview identifier] intValue])*0.15f + 0.05f;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSAnimationContext beginGrouping];
            [[NSAnimationContext currentContext] setDuration:1.0f];
            
            [[subview animator] setFrameOrigin:NSMakePoint([subview window].frame.size.width + subview.frame.origin.x, subview.frame.origin.y)];
            
            [NSAnimationContext endGrouping];
            
            // Transistion
            if([[subview identifier] intValue] == end_index) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    didTransistionOut = YES;
                    menuState++;
                    
                    [(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] menuDidFinishAnimatingOut];
                });
            }
        });
    }
}

@end
