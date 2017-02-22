//
//  NSMutableData+NSMutableData_AES256.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-08-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "NSData+AES256.h"

#import <CommonCrypto/CommonCrypto.h>

@implementation NSData (AES256)

- (NSData*)encryptWithKey:(char[33])key {
    size_t buf_size = [self length] + kCCBlockSizeAES128;
    void* outBuffer = malloc(buf_size);
    
    size_t numBytesEncrypted = 0;
    CCCryptorStatus result = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding, key, kCCKeySizeAES256, NULL, [self bytes], [self length], outBuffer, buf_size, &numBytesEncrypted);
    
    if(result == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:outBuffer length:numBytesEncrypted];
    }
    
    free(outBuffer);
    return NULL;
}

- (NSData*)decryptWithKey:(char[33])key {
    size_t buf_size = [self length] + kCCBlockSizeAES128;
    void* outBuffer = malloc(buf_size);
    
    size_t numBytesDecrypted = 0;
    CCCryptorStatus result = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding, key, kCCKeySizeAES256, NULL, [self bytes], [self length], outBuffer, buf_size, &numBytesDecrypted);
    
    if(result == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:outBuffer length:numBytesDecrypted];
    }
    
    free(outBuffer);
    return NULL;
}

@end
