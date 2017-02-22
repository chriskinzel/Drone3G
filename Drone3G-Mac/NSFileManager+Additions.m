//
//  NSFileManager+Additions.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-07-17.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "NSFileManager+Additions.h"

@implementation NSFileManager (Additions)

+ (NSString*)applicationStoragePath {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSString* folderPath = [NSString stringWithFormat:@"~/Library/Application Support/%@/", [[NSRunningApplication currentApplication] localizedName]];
    folderPath = [folderPath stringByExpandingTildeInPath];
    
    if([fileManager fileExistsAtPath:folderPath] == NO) {
        [fileManager createDirectoryAtPath:folderPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    return folderPath;
}

@end
