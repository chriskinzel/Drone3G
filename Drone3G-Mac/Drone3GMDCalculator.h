//
//  Drone3GMDCalculator.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-06-22.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// ALL METHODS MUST BE CALLED ON MAIN THREAD

@interface Drone3GMDCalculator : NSObject {
    WebView* webView;
    
    BOOL loaded;
    BOOL isRequestPending;
    
    void(*current_callback)(float);
}

@property (readonly) BOOL isRequestPending;

+ (id)sharedCalculator; // Starts loading, call this at application startup

// Returns immediately subsequent requests before completion of previous requests will be ignored
- (void)getMagneticDeclinationForCoordinates:(double)latitude longitude:(double)longitude callback:(void(*)(float))f_callback;


@end
