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

@import SceneKit;
@import GLKit;
@import SpriteKit;
@import CoreMotion;
@import OpenGLES;

static NSString *kMonkeyObjectName = @"Suzanne";
static NSString *kObjectFileName = @"monkey";

static NSString *kCameraName = @"kCameraName";
static NSString *kSkyboxCubeName = @"kSkyboxCubeName";
static NSString *kskSceneCubeHostName = @"kskSceneCubeHostName";
static NSString *kskScenePlaneHostName = @"kskScenePlaneHostName";

@interface GameViewController () <SCNSceneRendererDelegate, SKSceneDelegate>

@property(nonatomic, weak)SCNView *scnView;
@property(nonatomic, readonly)SCNScene *scnScene;

@property(nonatomic, readonly)SCNNode *monkey;
@property(nonatomic, readonly)SCNNode *camera;

@property(nonatomic, strong)CMMotionManager *motionManager;

@end


@implementation GameViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    NSDictionary *options = @{SCNPreferredRenderingAPIKey:@(SCNRenderingAPIOpenGLES2)};
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
    monkeyMaterial.shininess = 100.0;
    monkeyMaterial.locksAmbientWithDiffuse = YES;
    
    monkeyNode.geometry.firstMaterial = monkeyMaterial;
    
    SCNCamera *camera = [SCNCamera camera];
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

@end
