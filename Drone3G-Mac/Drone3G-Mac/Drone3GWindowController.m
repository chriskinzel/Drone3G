//
//  Drone3GWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2/24/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GWindowController.h"

#import "drone_com.h"
#import <pthread.h>

@implementation Drone3GWindowController

- (id)init {
    self = [super initWithWindowNibName:@"DataUsageWindow"];
    dateString = NULL;
    
    return self;
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    if(dateString != NULL) {
        [_dateLabel setStringValue:dateString];
    }
}

- (void)showWindow:(id)sender {
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

@end
