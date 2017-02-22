//
//  Drone3GWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2/24/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GDATWindowController.h"

#import "drone_com.h"
#import "drone_main.h"

#import <pthread.h>

@implementation Drone3GDATWindowController

static void latency_callback(int lat_ms) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[Drone3GDATWindowController sharedDataUsageWindowController] latencyLabel] setStringValue:[NSString stringWithFormat:@"%ims", lat_ms]];
    });
}

+ (id)sharedDataUsageWindowController {
    static Drone3GDATWindowController* sharedDataUsage = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedDataUsage = [[self alloc] init];
    });
    
    return sharedDataUsage;
}

- (id)init {
    self = [super initWithWindowNibName:@"DataUsageWindow"];
    if(self) {
        // Init right away
        [[self window] setIsVisible:NO];
        
        dateString = NULL;
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

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    if(dateString != NULL) {
        [_dateLabel setStringValue:dateString];
    }
}

- (void)showWindow:(id)sender {
    if([[self window] isVisible] && ([[NSApplication sharedApplication] currentEvent].modifierFlags & NSCommandKeyMask) ) { // Alternates visibillity for hot keys
        [[self window] performClose:nil];
        return;
    }
    
    [[self window] center];
    [super showWindow:sender];
}

- (void)setDateString:(NSString*)string {
    dateString = [string copy];
    [_dateLabel setStringValue:dateString];
}


- (IBAction)resetUsage:(id)sender {
    NSDateComponents* dateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitDay | NSCalendarUnitMonth fromDate:[NSDate date]];
    drone3g_send_command([[NSString stringWithFormat:@"AT*CLRUSG(%i,%i)\r", (int)[dateComponents month], (int)[dateComponents day]] cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (IBAction)testLatency:(id)sender {
    drone3g_test_latency(&latency_callback);
}

@end
