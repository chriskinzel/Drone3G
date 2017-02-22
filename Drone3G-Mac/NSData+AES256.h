//
//  NSMutableData+NSMutableData_AES256.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-08-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (AES256)

// KEY MUST BE 32 BYTES

- (NSData*)encryptWithKey:(char[33])key;
- (NSData*)decryptWithKey:(char[33])key;

@end
