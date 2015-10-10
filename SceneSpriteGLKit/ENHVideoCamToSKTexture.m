//
//  ENHVideoCamToSKTexture.m
//  TestVideoCam
//
//  Created by Jonathan Saggau on 1/20/14.
//  Copyright (c) 2014 Enharmonic. All rights reserved.
//

#import "ENHVideoCamToSKTexture.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <SpriteKit/SpriteKit.h>
#import <Accelerate/Accelerate.h>

#define LOWER_CAMERA_FRAMERATE (0)

@interface ENHVideoCamToSKTexture () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property(readwrite, strong)SKMutableTexture *texture;

@end

@implementation ENHVideoCamToSKTexture
{
    AVCaptureSession *_captureSession;
    SKMutableTexture *_texture;
    CVPixelBufferPoolRef _bufferPool;
}

-(id)init
{
    self = [self initWithCaptureSessionPreset:AVCaptureSessionPresetMedium useFrontCamera:YES];
    return self;
}

-(id)initWithCaptureSessionPreset:(NSString *)captureSessionPreset useFrontCamera:(BOOL)frontCam
{
    self = [super init];
    if (self)
    {
        _captureSession = [[AVCaptureSession alloc] init];
        
        //AVCaptureSessionPresetHigh //AVCaptureSessionPresetMedium
        AVCaptureDevice *device = nil;
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        if (frontCam)
        {
            device = [devices lastObject];
        }
        else
        {
            device = [devices firstObject];
        }
        
        if ([captureSessionPreset length] > 0 && [device supportsAVCaptureSessionPreset:captureSessionPreset])
        {
            [_captureSession setSessionPreset:captureSessionPreset];
        }
        else
        {
            [_captureSession setSessionPreset:AVCaptureSessionPresetMedium];
        }
        
        AVCaptureDeviceInput *videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:nil];
        
        if ([_captureSession canAddInput:videoInput])
        {
            [_captureSession addInput:videoInput];
            
            // Create the session output
            AVCaptureVideoDataOutput * dataOutput = [[AVCaptureVideoDataOutput alloc] init];
            [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
            [dataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
            
#if LOWER_CAMERA_FRAMERATE
            //Knock the frame rate down a bit;
            AVCaptureDeviceFormat *format = [device activeFormat];
            AVFrameRateRange *range = [[format videoSupportedFrameRateRanges] firstObject];
            Float64 minRate = [range minFrameRate];
            Float64 maxRate = [range maxFrameRate];
            
            Float64 targetMin = 30.0; //1/30
            targetMin = minRate <= targetMin ? targetMin : minRate;
            Float64 targetMax = 30.0; //15.0; //1/15
            targetMax = maxRate >= targetMax ? targetMax : maxRate;
            
            CMTime maxFrameDuration = CMTimeMakeWithEpoch(1, targetMin, 0);
            CMTime minFrameDuration = CMTimeMakeWithEpoch(1, targetMax, 0);
            
            if ( [device lockForConfiguration:NULL] == YES ) {
                device.activeVideoMinFrameDuration = minFrameDuration;
                device.activeVideoMaxFrameDuration = maxFrameDuration;
                [device unlockForConfiguration];
            }
#endif
            
            [dataOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];
            [_captureSession addOutput:dataOutput];
            [_captureSession commitConfiguration];
            
            AVCaptureConnection *connection = [dataOutput connectionWithMediaType:AVMediaTypeVideo];
            if ([connection isVideoMirroringSupported])
            {
                [connection setVideoMirrored:YES];
            }
        }
        else
        {
            NSLog(@"Cannot add default camera");
        }
    }
    return self;
}

-(void)startCapture
{
    [_captureSession startRunning];
}

-(void)stopCapture
{
    [_captureSession stopRunning];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    @autoreleasepool {
        
        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        
        if (_bufferPool == NULL)
        {
            //http://drop-osx.googlecode.com/svn-history/r22/trunk/Source/MovieEncoder.m
            NSDictionary *attributes = @{(NSString *)kCVPixelBufferWidthKey: @(width),
                                         (NSString *)kCVPixelBufferHeightKey: @(height),
                                         (NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
            CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef) attributes, &_bufferPool);
        }
        
        CVReturn cvErr = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        if (cvErr != kCVReturnSuccess)
        {
            NSLog (@"CVPixelBufferLockBaseAddress(pixelBuffer) failed with CVReturn value %d", cvErr);
        }
        
        uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
        
        CVImageBufferRef passablePixelBuffer;
        cvErr = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                                                                    _bufferPool,
                                                                    (__bridge CFDictionaryRef)(@{(NSString *)kCVPixelBufferPoolAllocationThresholdKey:@(2)}),
                                                                    &passablePixelBuffer);
        if (cvErr != kCVReturnSuccess)
        {
            NSLog (@"CVPixelBufferPoolCreatePixelBufferWithAuxAttributes failed with CVReturn value %d", cvErr);
        }
        
        cvErr = CVPixelBufferLockBaseAddress(passablePixelBuffer, 0);
        if (cvErr != kCVReturnSuccess)
        {
            NSLog (@"CVPixelBufferLockBaseAddress(passablePixelBuffer) failed with CVReturn value %d", cvErr);
        }
        uint8_t *passableBaseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(passablePixelBuffer);

        vImage_Buffer inBuffer;
        inBuffer.data = baseAddress;
        inBuffer.height = height;
        inBuffer.width = width;
        inBuffer.rowBytes = bytesPerRow;

        vImage_Buffer passableBuffer;
        passableBuffer.data = passableBaseAddress;
        passableBuffer.height = height;
        passableBuffer.width = width;
        passableBuffer.rowBytes = bytesPerRow;
        uint8_t bgraMap[4] = {2, 1, 0, 3};
        vImagePermuteChannels_ARGB8888(&inBuffer, &passableBuffer, bgraMap, kvImageNoFlags);

        cvErr = CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        if (cvErr != kCVReturnSuccess)
        {
            NSLog (@"CVPixelBufferUnlockBaseAddress(pixelBuffer) failed with CVReturn value %d", cvErr);
        }
        
        __weak typeof(self) blkSelf = self;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (_texture == nil || _texture.size.height != height || _texture.size.width != width)
            {
                SKMutableTexture *texture = [[SKMutableTexture alloc] initWithSize:(CGSize){.height = height, .width = width}];
                [blkSelf setTexture:texture];
            }
            [_texture modifyPixelDataWithBlock:^(void *pixelData, size_t lengthInBytes) {

                memcpy(pixelData, passableBaseAddress, lengthInBytes);
                CVReturn cvErr = CVPixelBufferUnlockBaseAddress(passablePixelBuffer, 0);
                if (cvErr != kCVReturnSuccess)
                {
                    NSLog (@"CVPixelBufferUnlockBaseAddress(passablePixelBuffer) failed with CVReturn value %d", cvErr);
                }
                CVPixelBufferRelease(passablePixelBuffer);
            }];
        });
        
    }
}

-(void)dealloc
{
    CVPixelBufferPoolRelease(_bufferPool);
}


@end
