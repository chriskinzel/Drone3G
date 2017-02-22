//
//  Drone3GTipGenerator.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-08-12.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Drone3GTipGenerator : NSObject {
    NSTextField* theLabel;
    
    NSTimer* timer;
    
    NSArray* tipStrings;
    NSMutableArray* tipIndices;
    NSUInteger currentTipIndex;
}

+ (id)sharedTipGenerator;
- (void)generateTipsAtInterval:(NSTimeInterval)interval forLabel:(NSTextField*)label;

@end
