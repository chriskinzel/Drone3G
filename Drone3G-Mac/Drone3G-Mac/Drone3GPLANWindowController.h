//
//  Drone3GPLANWindowController.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-30.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface Drone3GPLANWindowController : NSWindowController {
    BOOL gotHeading;
    float lastHeading;
    
    BOOL gotPos;
    double lastLat;
    double lastLon;
}

@property (assign) IBOutlet WebView* mapView;

@property (assign) IBOutlet NSTextField* loadingLabel;
@property (assign) IBOutlet NSProgressIndicator* spinner;

- (void)updateDroneLocation:(double)lat longitude:(double)lon;
- (void)updateDroneHeading:(float)angle;

- (void)setHomeLocation:(double)lat longitude:(double)lon;

@end
