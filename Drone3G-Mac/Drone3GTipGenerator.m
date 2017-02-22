//
//  Drone3GTipGenerator.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-08-12.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GTipGenerator.h"
#import "Drone3GPREFWindowController.h"

@implementation Drone3GTipGenerator

+ (id)sharedTipGenerator {
    static Drone3GTipGenerator* sharedGenerator = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedGenerator = [[self alloc] init];
    });
    
    return sharedGenerator;
}

- (id)init {
    if(self = [super init]) {
        currentTipIndex = 0;
        
        tipStrings = @[@"Make sure the USB modem is plugged in before connecting the battery",
                       @"Choppy video ? Try lowering the bitrate under the video quality menu",
                       @"Never fly indoors or around people with Drone3G",
                       @"You should flat trim on a level surface before every flight",
                       @"Don't like the control layout ? Customize it in the in Drone3G preferences",
                       @"If your drone is out of control you can push the \"Lock Hover\" button (R2) to stablize",
                       [NSString stringWithFormat:@"The drones stabillity degrades rapidly in wind speeds above %@", ([[[Drone3GPREFWindowController sharedPreferencesController] speedUnits] isEqualToString:@"km/h"]) ? @"10 km/h" : @"6 mph"],
                       @"Always fly the drone within visible range, it may lose connection at any time",
                       @"Keep an eye on your data usage! Drone3G tracks your data usage under the Data Usage menu",
                       @"You can customize the HUD in Drone3G's preferences",
                       /*@"Drone3G supports TTL serial GPS modules, find out more under the help menu",*/
                       @"Do not use Drone3G with a MicroSD card in your USB modem, it may cause unexpected behavior",
                       @"Drone3G can read the current battery percentage to you, just push up on the D-pad",
                       @"Click, then click again and hold while swiping your finger to the left in this window to go back",
                       @"If you experience any problems with video or navigation data, close and re-open Drone3G",
                       @"Always keep a USB cord nearby when using the PS3 controller in case of disconnection",
                       @"Drone3G changes the standard telnet port of your drone to 6450",
                       @"You can telnet into your drone via 3G using \"telnet localhost 6452\" in a terminal",
                       @"Some carriers have seperate APN's for their LTE networks, these must be manually set",
                       @"In preferences there are instructions on how to connect the PS3 controller to your computer",
                       ];
        
        tipIndices = [NSMutableArray array];
        [tipStrings enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
            [tipIndices addObject:[NSNumber numberWithUnsignedInteger:idx]];
        }];
        
        theLabel = nil;
        timer = nil;
    }
    
    return self;
}

- (void)generateTipsAtInterval:(NSTimeInterval)interval forLabel:(NSTextField*)label {
    theLabel = label;
    
    if(timer != nil) {
        [timer invalidate];
    }
    
    [self randomizeSelection];
    [self generateTip];
    
    timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(generateTip) userInfo:nil repeats:YES];
}

- (void)randomizeSelection {
    for(NSUInteger i=0;i<[tipIndices count];i++) {
        NSUInteger remaining = [tipIndices count] - i;
        NSUInteger index = arc4random_uniform((u_int32_t)remaining) + i;
        
        [tipIndices exchangeObjectAtIndex:i withObjectAtIndex:index];
    }
}

- (void)generateTip {
    [theLabel setStringValue:[tipStrings objectAtIndex:[[tipIndices objectAtIndex:currentTipIndex] unsignedIntegerValue]]];
    
    currentTipIndex++;
    if(currentTipIndex >= [tipStrings count]) {
        currentTipIndex = 0;
        [self randomizeSelection];
    }
}

@end
