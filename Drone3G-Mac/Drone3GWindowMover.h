//
//  Drone3GWindowMover.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-19.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

// Window moving skips child windows

#import <Foundation/Foundation.h>

@interface Drone3GWindowMover : NSObject {
    NSMutableDictionary* locationDictionary;
    BOOL windowsMoved;
}

@property (readonly) BOOL windowsMoved;

+ (id)sharedWindowMover;

// Moves all windows in the application to the closest region offscreen
- (void)moveAllWindows;

// Restores windows to original locations after calling moveAllWindows, flag argument is used to decide if active fullscreen windows
// should prevent window restoration, set to NO for default behavior.
- (void)restoreAllWindows:(BOOL)flag;

@end
