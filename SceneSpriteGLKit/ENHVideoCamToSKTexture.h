//
//  ENHVideoCamToSKTexture.h
//  TestVideoCam
//
//  Created by Jonathan Saggau on 1/20/14.
//  Copyright (c) 2014 Enharmonic. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AVFoundation;

@class SKTexture, SKSpriteNode;
@interface ENHVideoCamToSKTexture : NSObject

@property(readonly)SKTexture *texture;

-(void)startCapture;
-(void)stopCapture;

-(instancetype)initWithCaptureSessionPreset:(NSString *)captureSessionPreset useFrontCamera:(BOOL)frontCam NS_DESIGNATED_INITIALIZER;

@end
