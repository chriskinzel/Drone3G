//
//  Drone3GPLANWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-30.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GPLANWindowController.h"

@implementation Drone3GPLANWindowController

@synthesize mapView;
@synthesize loadingLabel;
@synthesize spinner;

#pragma mark -
#pragma mark Initialization
#pragma mark -

- (id)init {
    self = [super initWithWindowNibName:@"FlightPlanner"];
    if(self) {
        gotPos = NO;
        gotHeading = NO;
        
        // Loads the map view right away
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
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}*/

- (void)awakeFromNib {
    [spinner startAnimation:nil];
    
    [self reloadWebView];
}

- (void)reloadWebView {
    NSString* URLString = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"http://www.google.com"] encoding:NSUTF8StringEncoding error:nil];
    if(URLString == NULL) { // No internet
        [loadingLabel setStringValue:@"No internet connection..."];
        
        // Try reloading every 5 seconds
        [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(reloadWebView) userInfo:nil repeats:NO];
        return;
    }
    
    [loadingLabel setStringValue:@"Loading map..."];
    
    NSString* filePath = [[NSBundle mainBundle] pathForResource:@"map" ofType:@"html"];
    NSString* htmlString = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    
    [[mapView mainFrame] loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (void)showWindow:(id)sender {
    // Flush queued values
    if(gotHeading) {
        [self sendMapCommand:@"setHeading" withArguments:@[[NSNumber numberWithFloat:lastHeading]]];
        gotHeading = NO;
    }
    if(gotPos) {
        [self sendMapCommand:@"moveCurrentLocation" withArguments:@[[NSNumber numberWithDouble:lastLat], [NSNumber numberWithDouble:lastLon]]];
        gotPos = NO;
    }
    
    [[self window] center];
    [super showWindow:nil];
}

#pragma mark -
#pragma mark Delegates and Notifications
#pragma mark -

- (void)mouseMoved:(NSEvent *)theEvent {
    NSPoint windowLocation = [theEvent locationInWindow];
    NSPoint viewLocation = [mapView convertPoint:windowLocation fromView:nil];
    
    if(!NSPointInRect(viewLocation, [mapView bounds])) {
        [[NSCursor arrowCursor] set];
    }
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    [spinner stopAnimation:nil];
    [spinner setHidden:YES];
    
    [loadingLabel setHidden:YES];
}

#pragma mark -
#pragma mark Work Methods
#pragma mark -

-(void)sendMapCommand:(NSString *)cmd withArguments:(NSArray*)args {
    [[mapView windowScriptObject] callWebScriptMethod:cmd withArguments:args];
}

- (void)updateDroneLocation:(double)lat longitude:(double)lon {
    lastLat = lat;
    lastLon = lon;
    gotPos = YES;
    
    if(![self.window isVisible]) {
        return;
    }
    
    [self sendMapCommand:@"moveCurrentLocation" withArguments:@[[NSNumber numberWithDouble:lat], [NSNumber numberWithDouble:lon]]];
}

- (void)updateDroneHeading:(float)angle {
    lastHeading = angle;
    gotHeading = YES;
    
    if(![self.window isVisible]) {
        return;
    }
    
    [self sendMapCommand:@"setHeading" withArguments:@[[NSNumber numberWithFloat:angle]]];
}

- (void)setHomeLocation:(double)lat longitude:(double)lon {
    [self sendMapCommand:@"setHomeLocation" withArguments:@[[NSNumber numberWithDouble:lat], [NSNumber numberWithDouble:lon]]];
}

@end
