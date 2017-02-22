//
//  Drone3GWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2/24/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GWindowController : NSWindowController <NSWindowDelegate> {
    NSString* dateString;
}

@property (assign) IBOutlet NSTextField* dataUsedLabel;
@property (assign) IBOutlet NSTextField* dateLabel;
@property (assign) IBOutlet NSTextField* bandwidthDownLabel;
@property (assign) IBOutlet NSTextField* bandwidthUpLabel;

- (void)setDateString:(NSString*)string; // Use this instead of setting the dateLabel directly as the nib may not have loaded yet
- (IBAction)resetUsage:(id)sender;

@end
