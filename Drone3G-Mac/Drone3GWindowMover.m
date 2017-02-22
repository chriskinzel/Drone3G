//
//  Drone3GWindowMover.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-19.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GWindowMover.h"

@implementation Drone3GWindowMover

@synthesize windowsMoved;

+ (id)sharedWindowMover {
    static Drone3GWindowMover* sharedMover = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedMover = [[self alloc] init];
    });
    
    return sharedMover;
}

- (id)init {
    if(self = [super init]) {
        locationDictionary = [NSMutableDictionary dictionary];
        windowsMoved = NO;
    }
    
    return self;
}

- (void)moveAllWindows {
    // Check for fullscreen
    for(NSWindow* currentWindow in [[NSApplication sharedApplication] windows]) {
        if( ([currentWindow styleMask] & NSFullScreenWindowMask) != 0 && [currentWindow isOnActiveSpace]) {
            return;
        }
    }
    
    [[NSSound soundNamed:@"away.mp3"] play];
    
    [NSAnimationContext beginGrouping];
    
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        windowsMoved = YES;
    }];
    
    for(NSWindow* currentWindow in [[NSApplication sharedApplication] windows]) {
        if(![[currentWindow screen] isEqualTo:[NSScreen mainScreen]] || ![currentWindow isVisible] || ![currentWindow isOnActiveSpace] || [currentWindow parentWindow]) { // Only move windows on main screen that are visible and have no parents
            continue;
        }
        
        [locationDictionary setObject:[NSValue valueWithPoint:currentWindow.frame.origin] forKey:[NSNumber numberWithInteger:currentWindow.windowNumber]];
        
        NSRect windowFrame = currentWindow.frame;
        
        float dist = windowFrame.origin.x+windowFrame.size.width/2 - [NSScreen mainScreen].frame.size.width/2 + ( (arc4random_uniform(2)) ? 0.1f : -0.1f);
        windowFrame.origin.x = [NSScreen mainScreen].frame.size.width * ( (dist >= 0.0f) ? 0.9 : -0.5);

        [[currentWindow animator] setFrame:windowFrame display:YES];
    }
    
    [NSAnimationContext endGrouping];
}

// FIXME: Is there a way to identify which workspace a window is on ? Otherwise it is impossible to tell which windows should move back
//        since the active workspace could change with no reference to the orignal one. Not a huge deal though very minor UI bug.
- (void)restoreAllWindows:(BOOL)flag {
    // Check for fullscreen
    for(NSWindow* currentWindow in [[NSApplication sharedApplication] windows]) {
        if( ([currentWindow styleMask] & NSFullScreenWindowMask) != 0 && [currentWindow isOnActiveSpace] && flag) {
            return;
        }
    }
    
    [[NSSound soundNamed:@"back.mp3"] play];
    
    [NSAnimationContext beginGrouping];
    
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        windowsMoved = NO;
    }];
    
    for(NSWindow* currentWindow in [[NSApplication sharedApplication] windows]) {
        if(![[currentWindow screen] isEqualTo:[NSScreen mainScreen]] || ![currentWindow isVisible] || [currentWindow parentWindow]) { // Only move windows on main screen that are visible and have no parents
            continue;
        }
        
        NSPoint originalPos = [[locationDictionary objectForKey:[NSNumber numberWithInteger:currentWindow.windowNumber]] pointValue];
        
        NSRect windowFrame = currentWindow.frame;
        windowFrame.origin = originalPos;
        
        [[currentWindow animator] setFrame:windowFrame display:YES];
    }
    
    [NSAnimationContext endGrouping];
    
    [locationDictionary removeAllObjects];
}

@end
