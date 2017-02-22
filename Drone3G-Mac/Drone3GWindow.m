//
//  Drone3GWindow.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-09-04.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GWindow.h"

@implementation Drone3GWindow

// FIXME: All animation code should be moved here from the delegate this is getting really messy

- (BOOL) canBecomeKeyWindow { return YES; }
- (BOOL) canBecomeMainWindow { return YES; }
- (BOOL) acceptsFirstResponder { return YES; }
- (BOOL) becomeFirstResponder { return YES; }
- (BOOL) resignFirstResponder { return YES; }

@end
