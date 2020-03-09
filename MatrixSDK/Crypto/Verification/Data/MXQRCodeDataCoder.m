/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXQRCodeDataCoder.h"
#import "MXQRCodeDataCodable.h"
#import "MXQRCodeData.h"
#import "MXQRCodeDataBuilder.h"
#import "MXBase64Tools.h"

#import "MXVerifyingAnotherUserQRCodeData.h"

static NSString* const kQRCodeFormatPrefix = @"MATRIX";
static NSUInteger const kQRCodeFormatVersion = 2;

@interface MXQRCodeDataCoder()

@property (nonatomic, strong) NSData *prefixData;
@property (nonatomic) NSUInteger supportedQRCodeVersion;
@property (nonatomic, strong) MXQRCodeDataBuilder *qrCodeDataBuilder;

@end

@implementation MXQRCodeDataCoder

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.prefixData = [kQRCodeFormatPrefix dataUsingEncoding:NSASCIIStringEncoding];
        self.supportedQRCodeVersion = kQRCodeFormatVersion;
        self.qrCodeDataBuilder = [MXQRCodeDataBuilder new];
    }
    return self;
}

- (MXQRCodeData*)decode:(NSData*)data
{
    NSInteger dataByteCount = data.length;
    
    NSInteger minimumDataByteCount = 10;
    
    if (dataByteCount < minimumDataByteCount)
    {
        NSLog(@"[MXQRCodeDataCoder] Data byte count is too short");
        return nil;
    }
    
    NSInteger totalReadBytesCount = 0;
    NSInteger currenReadBytesCount = 0;
    
    NSInputStream *inputStream = [NSInputStream inputStreamWithData:data];
    [inputStream open];
    
    // Found the ASCII string "MATRIX"
    
    NSUInteger prefixLength = self.prefixData.length;
    uint8_t prefixBuffer[prefixLength];
    
    currenReadBytesCount = [inputStream read:prefixBuffer maxLength:prefixLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSData *foundPrefixData = [[NSData alloc] initWithBytes:prefixBuffer length:prefixLength];
    
    if (![self.prefixData isEqualToData:foundPrefixData])
    {
        NSLog(@"[MXQRCodeDataCoder] decode: Invalid prefix");        
        return nil;
    }
    
    // Check the QR code version
    
    NSUInteger versionLength = 1;
    uint8_t versionBuffer[versionLength];
    
    currenReadBytesCount = [inputStream read:versionBuffer maxLength:versionLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse QR code version with inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSUInteger version = versionBuffer[0];
    
    if (version != self.supportedQRCodeVersion)
    {
        NSLog(@"[MXQRCodeDataCoder] Unsupported QR code version");
        return nil;
    }
    
    // Find the QR code verification mode
    
    NSUInteger verificationModeLength = 1;
    uint8_t verificationModeBuffer[versionLength];
    
    currenReadBytesCount = [inputStream read:verificationModeBuffer maxLength:verificationModeLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse verification mode with inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSInteger verificationModeRawValue = verificationModeBuffer[0];
    MXQRCodeVerificationMode verificationMode;
    
    if (verificationModeRawValue >= MXQRCodeVerificationModeVerifyingAnotherUser && verificationModeRawValue <= MXQRCodeVerificationModeSelfVerifyingMasterKeyNotTrusted)
    {
        verificationMode = verificationModeRawValue;
    }
    else
    {
        NSLog(@"[MXQRCodeDataCoder] Invalid verification mode %ld", (long)verificationModeRawValue);
        return nil;
    }
    
    // Find the transaction id length
    
    NSUInteger transactionIdByteLength = 2;
    uint8_t transactionIdLengthBuffer[transactionIdByteLength];
    
    currenReadBytesCount = [inputStream read:transactionIdLengthBuffer maxLength:transactionIdByteLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse transaction id length with inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    uint16_t transactionIdLengthBigEndian;
    
    [data getBytes:&transactionIdLengthBigEndian range:NSMakeRange(totalReadBytesCount, transactionIdByteLength)];
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSUInteger transactionIdLength = CFSwapInt16BigToHost(transactionIdLengthBigEndian);
    
    if (transactionIdLength == 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Transaction id length is equal to zero");
        return nil;
    }
    
    // Find the transaction id
    
    uint8_t transactionIdBuffer[transactionIdLength];
    
    currenReadBytesCount = [inputStream read:transactionIdBuffer maxLength:transactionIdLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse transaction id length with inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSString *transactionId = [[NSString alloc] initWithBytes:transactionIdBuffer length:transactionIdLength encoding:NSASCIIStringEncoding];
    
    // Find the first key
    
    NSUInteger keyByteLength = 32;
    uint8_t firstKeyBuffer[keyByteLength];
    
    currenReadBytesCount = [inputStream read:firstKeyBuffer maxLength:keyByteLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse first key inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSData *firstKeyData = [[NSData alloc] initWithBytes:firstKeyBuffer length:keyByteLength];
    NSString *firstKey = [MXBase64Tools unpaddedBase64FromData:firstKeyData];
    
    // Find the second key
    
    uint8_t secondKeyBuffer[keyByteLength];
    
    currenReadBytesCount = [inputStream read:secondKeyBuffer maxLength:keyByteLength];
    
    if (currenReadBytesCount < 0)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse first key inputStream.streamError: %@", inputStream.streamError);
        return nil;
    }
    
    totalReadBytesCount += currenReadBytesCount;
    
    NSData *secondKeyData = [[NSData alloc] initWithBytes:secondKeyBuffer length:keyByteLength];
    NSString *secondKey = [MXBase64Tools unpaddedBase64FromData:secondKeyData];
    
    // Find the shared secret
    
    NSInteger minimumSharedSecretByteCount = 8;
    
    NSInteger remainingBytesCount = dataByteCount - totalReadBytesCount;
    
    // Shared secret should be 8 bytes length minimum
    if (remainingBytesCount < minimumSharedSecretByteCount)
    {
        NSLog(@"[MXQRCodeDataCoder] Fail to parse shared secret");
        return nil;
    }
    
    uint8_t sharedSecretBuffer[remainingBytesCount];
    
    currenReadBytesCount = [inputStream read:sharedSecretBuffer maxLength:remainingBytesCount];
    
    NSData *sharedSecretData = [[NSData alloc] initWithBytes:sharedSecretBuffer length:currenReadBytesCount];
    
    totalReadBytesCount += currenReadBytesCount;
    
    // Create QR code data
    
    return [self.qrCodeDataBuilder buildQRCodeDataWithVerificationMode:verificationMode
                                                         transactionId:transactionId
                                                              firstKey:firstKey
                                                             secondKey:secondKey
                                                          sharedSecret:sharedSecretData];
}

- (NSData*)encode:(id<MXQRCodeDataCodable>)qrCodeDataCodable
{
    NSMutableData *qrCodeRawData = [NSMutableData data];
    
    // the ASCII string "MATRIX"
    
    [qrCodeRawData appendData:self.prefixData];
    
    // one byte indicating the QR code version

    uint8_t versionBytes = qrCodeDataCodable.version;
    [qrCodeRawData appendBytes:&versionBytes length:sizeof(versionBytes)];

    // one byte indicating the QR code verification mode. May be one of the following values:

    NSInteger verificationModeInt = qrCodeDataCodable.verificationMode;
    uint8_t verificationModeUInt8 = verificationModeInt;
    [qrCodeRawData appendBytes:&verificationModeInt length:sizeof(verificationModeUInt8)];
    
    // two bytes in network byte order (big-endian) indicating the length of the ID
    
    uint16_t transactionIDLenghtBytes = CFSwapInt16HostToBig(qrCodeDataCodable.transactionId.length);
    [qrCodeRawData appendBytes:&transactionIDLenghtBytes length:sizeof(transactionIDLenghtBytes)];
    
    // the ID as an ASCII string

    NSData *transactionIDData = [qrCodeDataCodable.transactionId dataUsingEncoding:NSASCIIStringEncoding];
    [qrCodeRawData appendData:transactionIDData];
    
    // the first key, as 32 bytes. The key to use depends on the mode field:
    
    NSData *firstKeyData = [MXBase64Tools dataFromUnpaddedBase64:qrCodeDataCodable.firstKey];
    [qrCodeRawData appendData:firstKeyData];

    // the second key, as 32 bytes. The key to use depends on the mode field:
    
    NSData *secondKeyData = [MXBase64Tools dataFromUnpaddedBase64:qrCodeDataCodable.secondKey];
    [qrCodeRawData appendData:secondKeyData];

    // a random shared secret
    
    [qrCodeRawData appendData:qrCodeDataCodable.sharedSecret];

    return qrCodeRawData;
}

@end
