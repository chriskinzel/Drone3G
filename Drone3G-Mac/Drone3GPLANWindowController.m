//
//  Drone3GPLANWindowController.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-30.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GPLANWindowController.h"
#import "drone_main.h"

@implementation Drone3GPLANWindowController

@synthesize mapView;
@synthesize loadingLabel;
@synthesize spinner;

#pragma mark -
#pragma mark Initialization
#pragma mark -

+ (id)sharedFlightMap {
    static Drone3GPLANWindowController* sharedFlightMap = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedFlightMap = [[self alloc] init];
    });
    
    return sharedFlightMap;
}

- (id)init {
    // TODO: Uncomment
    //self = [super initWithWindowNibName:@"FlightPlanner"];
    self = [super init];
    if(self) {
        gotPos = NO;
        gotHeading = NO;
        
        // TODO: Uncomment
        // Loads the map view right away
        //[[self window] setIsVisible:NO];
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


// TODO: Uncomment
/*- (void)awakeFromNib {
    [spinner startAnimation:nil];
    [self reloadWebView];
    
    [mapView setPolicyDelegate:self];
}*/

- (void)reloadWebView {
    NSString* URLString = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"http://www.apple.com"] encoding:NSUTF8StringEncoding error:nil];
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
    // TODO: Remove
    return;
    
    if([[self window] isVisible] && ([[NSApplication sharedApplication] currentEvent].modifierFlags & NSCommandKeyMask) ) { // Alternates visibillity for hot keys
        [[self window] performClose:nil];
        return;
    }
    
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

// Handles Javascript Obj-C bridge as I could not get the standard way to work, this is also 10x easier
- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    NSString* urlString = [[request URL] absoluteString];
    
    // Javascript calling Objective-C method
    if([urlString hasPrefix:@"objc:"]) {
        [listener ignore];
        
        const char* url_string = [[urlString stringByReplacingOccurrencesOfString:@"objc:" withString:@""] cStringUsingEncoding:NSUTF8StringEncoding];
        double lat = strtod(url_string, NULL);
        
        char* lon_string = strstr(url_string, ",");
        if(lon_string != NULL) {
            double lon = strtod(lon_string+1, NULL);
            drone3g_home_location_changed_callback(lat, lon);
        }
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
    // TODO: Remove
    return;
    
    [[mapView windowScriptObject] callWebScriptMethod:cmd withArguments:args];
}

- (void)updateDroneLocation:(double)lat longitude:(double)lon {
    // TODO: Remove
    return;
    
    lastLat = lat;
    lastLon = lon;
    gotPos = YES;
    
    if(![self.window isVisible]) {
        return;
    }
    
    [self sendMapCommand:@"moveCurrentLocation" withArguments:@[[NSNumber numberWithDouble:lat], [NSNumber numberWithDouble:lon]]];
}

- (void)updateDroneHeading:(float)angle {
    // TODO: Remove
    return;
    
    lastHeading = angle;
    gotHeading = YES;
    
    if(![self.window isVisible]) {
        return;
    }
    
    [self sendMapCommand:@"setHeading" withArguments:@[[NSNumber numberWithFloat:angle]]];
}

- (void)setHomeLocation:(double)lat longitude:(double)lon {
    // TODO: Remove
    return;
    
    [self sendMapCommand:@"setHomeLocation" withArguments:@[[NSNumber numberWithDouble:lat], [NSNumber numberWithDouble:lon]]];
}

@end
