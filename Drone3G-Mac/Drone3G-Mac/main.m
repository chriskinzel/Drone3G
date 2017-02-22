//
//  main.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[])
{
    // Ignore SIGPIPE
    signal(SIGPIPE, SIG_IGN);
    
    return NSApplicationMain(argc, argv);
}
