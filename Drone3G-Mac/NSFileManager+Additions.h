//
//  NSFileManager+Additions.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-17.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSFileManager (Additions)

// Returns the path to the application support directory of the current running application, if it does not exist it is created
+ (NSString*)applicationStoragePath;

@end
