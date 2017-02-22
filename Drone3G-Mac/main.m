//
//  main.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// The breakpoint below executes a debugger command to ignore SIGPIPE which immediately continues after executing
int main(int argc, const char * argv[])
{
    // Ignore signals
    signal(SIGPIPE, SIG_IGN);
    signal(SIGURG, SIG_IGN);
    signal(SIGALRM, SIG_IGN);
        
    return NSApplicationMain(argc, argv);
}
