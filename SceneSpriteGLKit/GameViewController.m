//
//  GameViewController.m
//  SceneSpriteGLKit
//
//  Created by Jonathan Saggau on 10/10/15.
//  Copyright (c) 2015 Enharmonic inc. All rights reserved.
//

#import "GameViewController.h"
#import "SKScene+Unarchive.h"
#import "normalizeRotation.h"
#import "ENHVideoCamToSKTexture.h"
#import "ENHMetalSkybox.h"

@import SceneKit;
@import GLKit;
@import SpriteKit;
@import CoreMotion;
@import OpenGLES;
@import Metal;

static NSString *kMonkeyObjectName = @"Suzanne";
static NSString *kObjectFileName = @"monkey";

static NSString *kCameraName = @"kCameraName";
static NSString *kSkyboxCubeName = @"kSkyboxCubeName";
static NSString *kskSceneCubeHostName = @"kskSceneCubeHostName";
static NSString *kskScenePlaneHostName = @"kskScenePlaneHostName";
static NSString *textureObservationContext = @"Texture Observation Key";

static const GLfloat skyboxSize = 64.0f;

@interface GameViewController () <SCNSceneRendererDelegate, SKSceneDelegate>

@property(nonatomic, weak)SCNView *scnView;
@property(nonatomic, readonly)SCNScene *scnScene;

@property(nonatomic, readonly)SCNNode *monkey;
@property(nonatomic, readonly)SCNNode *camera;
@property(nonatomic, readonly)SCNNode *skSceneCubeHost;

@property(nonatomic, strong)CMMotionManager *motionManager;
@property(nonatomic, strong)GLKSkyboxEffect *skybox;
@property(nonatomic, strong)ENHMetalSkybox *metalSkybox;

@property(nonatomic, weak)SKScene *loadedFromDiskSKScene;
@property(nonatomic, strong)ENHVideoCamToSKTexture *videoTextureBridge;

@end


@implementation GameViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    //Let Scene Kit choose Metal or OpenGL ES 2, depending on device capabilities.
    NSDictionary *options = nil;
    SCNView *scnView = [[SCNView alloc] initWithFrame:self.view.bounds options:options];
    [self.view addSubview:scnView];
    
    NSDictionary *views = NSDictionaryOfVariableBindings(scnView);
    [scnView setTranslatesAutoresizingMaskIntoConstraints:NO];
    for (NSString *constraintString in @[@"H:|[scnView]|", @"V:|[scnView]|"])
    {
        NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:constraintString
                                                                       options:0
                                                                       metrics:nil
                                                                         views:views];
        [self.view addConstraints:constraints];
    }
    
    [self setScnView:scnView];
    [scnView setDelegate:self];
    
    SCNScene *scnScene = [self.class loadSceneKitScene];
    scnView.scene = scnScene;
    scnView.showsStatistics = YES;
    scnView.backgroundColor = [UIColor darkGrayColor];
    
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    NSMutableArray *gestureRecognizers = [NSMutableArray array];
    [gestureRecognizers addObject:pinchGesture];
    [gestureRecognizers addObjectsFromArray:scnView.gestureRecognizers];
    scnView.gestureRecognizers = [NSArray arrayWithArray:gestureRecognizers];
    
    CMMotionManager *motionManager = [[CMMotionManager alloc] init];
    [self setMotionManager:motionManager];
    
    if (scnView.renderingAPI == SCNRenderingAPIOpenGLES2)
    {
        //Background (GLKit) skybox
        GLKSkyboxEffect *skybox = [self.class loadSkybox];
        [self setSkybox:skybox];
    }
    else
    {
        //Background (Metal) skybox
        ENHMetalSkybox *skybox = [self.class loadMetalSkybox:scnView];
        [self setMetalSkybox:skybox];
    }
    
    //Place the Sprite Kit scene on a cube and attach it to the monkey node
    SKScene *loadedFromDiskSKScene = [self.class loadSpriteKitScene];
    SCNMaterial *loadedFromDiskSKSceneMaterial = [SCNMaterial material];
    loadedFromDiskSKSceneMaterial.diffuse.contents = loadedFromDiskSKScene;
    
    [loadedFromDiskSKScene setName:@"Loaded SKScene"];
    [loadedFromDiskSKScene setDelegate:self];
    [self setLoadedFromDiskSKScene:loadedFromDiskSKScene];
    
   
    SCNBox *geometry = [SCNBox boxWithWidth:1.0 height:1.0 length:1.0 chamferRadius:0.0];
    [geometry setMaterials:@[loadedFromDiskSKSceneMaterial]];
    SCNNode *cubeHost = [SCNNode nodeWithGeometry:geometry];
    [cubeHost setPosition:(SCNVector3){.x = 0.0, .y = -3.0, .z = 0.0}]; // in front of the monkey
    [cubeHost setName:kskSceneCubeHostName];
    
    SCNNode *monkey = [self monkey];
    NSParameterAssert(monkey);
    [monkey addChildNode:cubeHost];
    
    SCNAction *rotate = [SCNAction rotateByAngle:M_PI aroundAxis:(SCNVector3){.x = 0.0, .y = 1.0, .z = 1.0} duration:5.0];
    SCNAction *repeat = [SCNAction repeatActionForever:rotate];
    [cubeHost runAction:repeat];
    
    ENHVideoCamToSKTexture *videoTextureBridge = [[ENHVideoCamToSKTexture alloc] initWithCaptureSessionPreset:AVCaptureSessionPresetMedium useFrontCamera:YES];
    
    [videoTextureBridge addObserver:self
                         forKeyPath:@"texture"
                            options:NSKeyValueObservingOptionNew
                            context:&textureObservationContext];
    
    [videoTextureBridge startCapture];

    [self setVideoTextureBridge:videoTextureBridge];
    
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if ([self.motionManager isDeviceMotionAvailable])
    {
        [self.motionManager startDeviceMotionUpdates];
        [self.scnView setPlaying:YES];
    }
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if ([self.motionManager isDeviceMotionActive])
    {
        [self.motionManager stopDeviceMotionUpdates];
    }
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

#pragma mark - loading

+(NSArray *)cubeMapImages
{
    static NSArray *mapArray;
    if (mapArray == nil)
    {
        mapArray = @[
                     [UIImage imageNamed:@"right.jpg"],
                     [UIImage imageNamed:@"left.jpg"],
                     [UIImage imageNamed:@"top.jpg"],
                     [UIImage imageNamed:@"bottom.jpg"],
                     [UIImage imageNamed:@"back.jpg"],
                     [UIImage imageNamed:@"front.jpg"],
                     ];
    }
    return mapArray;
}

+(NSArray *)cubeMapFiles
{
    static NSArray *mapArray;
    if (mapArray == nil)
    {
        
        NSBundle *bundle = [NSBundle mainBundle];
        [bundle pathForResource:@"right" ofType:@"jpg"];
        mapArray = @[
                     [bundle pathForResource:@"right" ofType:@"jpg"],
                     [bundle pathForResource:@"left" ofType:@"jpg"],
                     [bundle pathForResource:@"top" ofType:@"jpg"],
                     [bundle pathForResource:@"bottom" ofType:@"jpg"],
                     [bundle pathForResource:@"back" ofType:@"jpg"],
                     [bundle pathForResource:@"front" ofType:@"jpg"],
                     ];
    }
    return mapArray;
}

+(ENHMetalSkybox *)loadMetalSkybox:(SCNView *)sceneView
{
    ENHMetalSkybox *skybox = [[ENHMetalSkybox alloc] initWithRenderer:sceneView];
    [skybox loadSkyboxWithResourceName:@"skybox" resourceExtension:@"png"];
    skybox.xSize = skyboxSize;
    skybox.ySize = skyboxSize;
    skybox.zSize = skyboxSize;
    return skybox;
}

+(GLKSkyboxEffect *)loadSkybox
{
    NSArray *cubeMapFiles = [self.class cubeMapFiles];
    GLKTextureInfo *cubemapTexInfo = [GLKTextureLoader cubeMapWithContentsOfFiles:cubeMapFiles options:nil error:nil];
    GLKSkyboxEffect *skybox = [[GLKSkyboxEffect alloc] init];
    skybox.center = GLKVector3Make(0.0f, 0.0f, 0.0f);
    skybox.textureCubeMap.name = cubemapTexInfo.name;
    skybox.textureCubeMap.enabled = true;
    skybox.xSize = skyboxSize;
    skybox.ySize = skyboxSize;
    skybox.zSize = skyboxSize;
    skybox.label = kSkyboxCubeName;
    return skybox;
}

+(SKScene *)loadSpriteKitScene
{
    SKScene *scene = [SKScene unarchiveFromFile:@"SpriteKitDemoScene"];
    NSParameterAssert(scene);
    return scene;
}

+(SCNScene *)loadSceneKitScene
{
    NSURL *sceneURL = [[NSBundle mainBundle] URLForResource:kObjectFileName withExtension:@"dae"];
    NSError *error = nil;
    SCNScene *scene = [SCNScene sceneWithURL:sceneURL options:nil error:&error];
    if (scene == nil)
    {
        NSLog(@"Scene loading error %@", [error localizedDescription]);
    }
    
    SCNNode *monkeyNode  = [scene.rootNode childNodeWithName:kMonkeyObjectName recursively:YES];
    
    SCNMaterial *monkeyMaterial = [SCNMaterial material];
    monkeyMaterial.diffuse.contents = [UIColor purpleColor];
    monkeyMaterial.specular.contents = [UIColor whiteColor];
    
    //Reflect the skybox on the monkey model
    monkeyMaterial.reflective.contents = [self cubeMapImages];

    monkeyMaterial.shininess = 100.0;
    monkeyMaterial.locksAmbientWithDiffuse = YES;
    
    monkeyNode.geometry.firstMaterial = monkeyMaterial;
    
    SCNCamera *camera = [SCNCamera camera];
    double zFar = hypot(skyboxSize*2, skyboxSize*2) + [camera zNear]; // make sure the skybox fits
    [camera setZFar:zFar];
    SCNNode *cameraNode = [SCNNode node];
    [cameraNode setCamera:camera];
    [cameraNode setName:kCameraName];
    [cameraNode setPosition:(SCNVector3){.x = 0.0, .y = 0.0, .z = 10.0}];
    [scene.rootNode addChildNode:cameraNode];
    
    SCNNode *frontLightNode = [SCNNode node];
    frontLightNode.light = [SCNLight light];
    frontLightNode.light.type = SCNLightTypeOmni;
    frontLightNode.light.color = [UIColor whiteColor];
    frontLightNode.position = SCNVector3Make(0, -2, 4);
    [scene.rootNode addChildNode:frontLightNode];
    
    SCNNode *fillLightNode = [SCNNode node];
    fillLightNode.light = [SCNLight light];
    fillLightNode.light.type = SCNLightTypeOmni;
    fillLightNode.light.color = [UIColor darkGrayColor];
    fillLightNode.position = SCNVector3Make(0, -2, -4);
    [scene.rootNode addChildNode:frontLightNode];
    
    SCNNode *ambientLightNode = [SCNNode node];
    ambientLightNode.light = [SCNLight light];
    ambientLightNode.light.type = SCNLightTypeAmbient;
    ambientLightNode.light.color = [UIColor colorWithWhite:0.8 alpha:1.0];
    [scene.rootNode addChildNode:ambientLightNode];
    return scene;
}

#pragma mark - SCNSceneRendererDelegate

static inline void applyRotationMatrixToTransform(CMRotationMatrix deviceRotationMatrix, SCNMatrix4 *transform_p)
{
    transform_p->m11 = deviceRotationMatrix.m11;
    transform_p->m21 = deviceRotationMatrix.m12;
    transform_p->m31 = deviceRotationMatrix.m13;
    transform_p->m12 = deviceRotationMatrix.m21;
    transform_p->m22 = deviceRotationMatrix.m22;
    transform_p->m32 = deviceRotationMatrix.m23;
    transform_p->m13 = deviceRotationMatrix.m31;
    transform_p->m23 = deviceRotationMatrix.m32;
    transform_p->m33 = deviceRotationMatrix.m33;
}

- (void)renderer:(id <SCNSceneRenderer>)aRenderer updateAtTime:(NSTimeInterval)time
{
    if ([self.motionManager isDeviceMotionActive])
    {
        CMDeviceMotion *deviceMotion = [self.motionManager deviceMotion];
        CMAttitude *deviceAttitude = deviceMotion.attitude;
        CMRotationMatrix deviceRotationMatrix = deviceAttitude.rotationMatrix;
        SCNNode *monkey = [self monkey];
        SCNVector3 monkeyScale = [monkey scale];
        
        SCNMatrix4 transform = [monkey transform];
        
        applyRotationMatrixToTransform(deviceRotationMatrix, &transform);
        
        [monkey setTransform:transform];
        [monkey setScale:monkeyScale];
        [monkey setPosition:(SCNVector3){0.0, 0.0, 0.0}];
        
        SCNNode *cameraNode = [self camera];
        SCNCamera *camera = [cameraNode camera];
        SCNMatrix4 camProjectionmatrix = [camera projectionTransform];
        GLKMatrix4 projectionMatrix = SCNMatrix4ToGLKMatrix4(camProjectionmatrix);
        self.skybox.transform.projectionMatrix = projectionMatrix;
        self.metalSkybox.projectionMatrix = projectionMatrix;

        GLKMatrix4 baseModelViewMatrix = GLKMatrix4Identity;
        GLKMatrix4 modelViewMatrix = GLKMatrix4Make(deviceRotationMatrix.m11, deviceRotationMatrix.m21, deviceRotationMatrix.m31, 0.0f,
                                                    deviceRotationMatrix.m12, deviceRotationMatrix.m22, deviceRotationMatrix.m32, 0.0f,
                                                    deviceRotationMatrix.m13, deviceRotationMatrix.m23, deviceRotationMatrix.m33, 0.0f,
                                                    0.0f, 0.0, 0.0, 1.0);
        modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, M_PI_2, 1.0, 0.0, 0.0);
        modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
        self.skybox.transform.modelviewMatrix = modelViewMatrix;
        self.metalSkybox.modelviewMatrix = modelViewMatrix;
    }
}

-(void)drawSkybox
{
#if DEBUG
    glPushGroupMarkerEXT(0, "GLKitDrawing");
#endif
    [self.skybox prepareToDraw];
    [self.skybox draw];
#if DEBUG
    glPopGroupMarkerEXT();
#endif
}

-(void)drawMetalSkybox
{
#if DEBUG
    id< MTLRenderCommandEncoder > currentRenderCommandEncoder = [self.scnView currentRenderCommandEncoder];
    [currentRenderCommandEncoder pushDebugGroup:@"MetalDrawing"];
#endif
    
    [self.metalSkybox render];
    
#if DEBUG
    [currentRenderCommandEncoder popDebugGroup];
#endif
}

-(void)renderer:(nonnull id<SCNSceneRenderer>)renderer willRenderScene:(nonnull SCNScene *)scene atTime:(NSTimeInterval)time
{
    SCNRenderingAPI api = renderer.renderingAPI;
    if (api == SCNRenderingAPIOpenGLES2)
    {
        [self drawSkybox];
    }
    else
    {
        [self drawMetalSkybox];
    }
}

#pragma mark - gesture recognition

//Zoom
-(void)handlePinch:(UIPinchGestureRecognizer *)gestureRecognizer
{
    const CGFloat maxScale = 4.0;
    const CGFloat minScale = 1.0/maxScale;
    
    SCNNode *object = [self monkey];
    SCNVector3 objectScale = [object scale];
    
    CGFloat grScale = [gestureRecognizer scale];
    
    objectScale.x *= grScale;
    objectScale.x = objectScale.x > maxScale ? maxScale : objectScale.x;
    objectScale.x = objectScale.x < minScale ? minScale : objectScale.x;
    objectScale.y = objectScale.z = objectScale.x;
    [object setScale:objectScale];
    [gestureRecognizer setScale:1.0];
}

#pragma mark - KVO
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &textureObservationContext)
    {
        
        SCNNode *cube = [self skSceneCubeHost];
        SCNGeometry *cubeGeometry = [cube geometry];
        
        //Place the Sprite Kit scene on a cube and attach it to the monkey node
        SKScene *loadedFromDiskSKScene = [self.class loadSpriteKitScene];
        SCNMaterial *loadedFromDiskSKSceneMaterial = [SCNMaterial material];
        loadedFromDiskSKSceneMaterial.diffuse.contents = loadedFromDiskSKScene;
      
        if (self.videoTextureBridge.texture != nil)
        {
            SCNMaterial *videoMaterial = [SCNMaterial material];
            videoMaterial.diffuse.contents = self.videoTextureBridge.texture;
            [cubeGeometry setMaterials:@[loadedFromDiskSKSceneMaterial,
                                         videoMaterial]];

        }
        else
        {
            [cubeGeometry setMaterials:@[loadedFromDiskSKSceneMaterial]];
        }
        
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - convenience properties

-(SCNScene *)scnScene
{
    SCNScene *scene = [self.scnView scene];
    return scene;
}

-(SCNNode *)monkey
{
    SCNNode *object  = [self.scnScene.rootNode childNodeWithName:kMonkeyObjectName recursively:YES];
    return object;
}

-(SCNNode *)camera
{
    SCNNode *object  = [self.scnScene.rootNode childNodeWithName:kCameraName recursively:YES];
    return object;
}

-(SCNNode *)skSceneCubeHost
{
    SCNNode *object = [self.scnScene.rootNode childNodeWithName:kskSceneCubeHostName recursively:YES];
    return object;
}

@end
