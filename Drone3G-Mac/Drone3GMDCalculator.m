//
//  Drone3GMDCalculator.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-06-22.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GMDCalculator.h"

@implementation Drone3GMDCalculator

@synthesize isRequestPending;

+ (id)sharedCalculator {
    static Drone3GMDCalculator* sharedCalculator = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedCalculator = [[self alloc] init];
    });
    
    return sharedCalculator;
}

- (id)init {
    if(self = [super init]) {
        loaded = NO;
        isRequestPending = NO;
        
        webView = [[WebView alloc] initWithFrame:NSZeroRect];
        [webView setFrameLoadDelegate:self];
        
        [self reloadWebView];
    }
    
    return self;
}

#pragma mark -
#pragma mark Delegates
#pragma mark -

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if(!loaded) {
        loaded = YES;
        return;
    }
    
    if([[[[[[webView mainFrame] dataSource] request] URL] absoluteString] isEqualToString:@"http://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination"]) {
        isRequestPending = NO;
        
        NSString* data = [webView stringByEvaluatingJavaScriptFromString:@"document.documentElement.textContent"];
        NSArray* fields = [data componentsSeparatedByString:@","];
        if([fields count] < 5) {
            return;
        }
        
        current_callback([[fields objectAtIndex:3] floatValue]);
        
        [webView goBack];
    }
}

// Loads CSV file as plain text
- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    [listener use];
}

#pragma mark -

- (void)reloadWebView {
    NSString* URLString = [NSString stringWithContentsOfURL:[NSURL URLWithString:@"http://www.ngdc.noaa.gov/geomag-web/"] encoding:NSUTF8StringEncoding error:nil];
    if(URLString == NULL) { // No internet
        // Try reloading every 5 seconds
        [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(reloadWebView) userInfo:nil repeats:NO];
        return;
    }
    
    [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.ngdc.noaa.gov/geomag-web/"]]];
    [webView setPolicyDelegate:self];
}

- (void)getMagneticDeclinationForCoordinates:(double)latitude longitude:(double)longitude callback:(void(*)(float))f_callback {
    if(!loaded || f_callback == NULL || [[[[[[webView mainFrame] dataSource] request] URL] absoluteString] isEqualToString:@"http://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination"]) {
        return;
    }
    
    current_callback = f_callback;
    isRequestPending = YES;
    
    // Fill in web page
    [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.getElementById(\"declinationLat1\").value = \"%f\";", fabs(latitude)]];
    [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.getElementsByName('lat1Hemisphere')[0].value = \"%c\";", (latitude < 0.0) ? 'S' : 'N']];
    
    [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.getElementById(\"declinationLon1\").value = \"%f\";", fabs(longitude)]];
    [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"document.getElementsByName('lon1Hemisphere')[0].value = \"%c\";", (longitude < 0.0) ? 'W' : 'E']];
    
    [webView stringByEvaluatingJavaScriptFromString:@"document.getElementsByName('resultFormat')[0].value = \"csv\";"];
    
    [webView stringByEvaluatingJavaScriptFromString:@"performCalculation('declination', '/geomag-web');"];
}

@end
