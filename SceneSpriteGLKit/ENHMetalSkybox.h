//
//  ENHMetalSkybox.h
//  SceneSpriteGLKit
//
//  Created by Jonathan Saggau on 10/10/15.
//  Copyright © 2015 Enharmonic inc. All rights reserved.
//  Based on AAPL sample code -- MetalVideoCapture available at:
//  https://developer.apple.com/library/ios/samplecode/MetalVideoCapture/Introduction/Intro.html

#import <Foundation/Foundation.h>

#import <SceneKit/SceneKit.h>
#import <GLKit/GLKit.h>

@interface ENHMetalSkybox : NSObject

//For making it easy to replace a GLKit skybox with a Metal Skybox
@property (nonatomic, assign) GLfloat xSize, ySize, zSize;
@property (nonatomic, assign) GLKMatrix4 modelviewMatrix, projectionMatrix;

- (instancetype)initWithRenderer:(id<SCNSceneRenderer>)renderer;

- (BOOL)loadSkyboxWithResourceName:(NSString *)resourceName resourceExtension:(NSString *)resourceExtension;

- (void)render;

@end
