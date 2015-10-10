//
//  ENHMetalSkybox.m
//  SceneSpriteGLKit
//
//  Created by Jonathan Saggau on 10/10/15.
//  Copyright © 2015 Enharmonic inc. All rights reserved.
//

#import "ENHMetalSkybox.h"
#import "AAPLTexture.h"
#import "AAPLSharedTypes.h"

#import <SceneKit/SceneKit.h>
#import <simd/simd.h>

static const long kMaxBufferBytesPerFrame = 1024*1024;
static const long kInFlightCommandBuffers = 3;

static const simd::float4 cubeVertexData[] =
{
    // posx
    { -1.0f,  1.0f,  1.0f, 1.0f },
    { -1.0f, -1.0f,  1.0f, 1.0f },
    { -1.0f,  1.0f, -1.0f, 1.0f },
    { -1.0f, -1.0f, -1.0f, 1.0f },
    
    // negz
    { -1.0f,  1.0f, -1.0f, 1.0f },
    { -1.0f, -1.0f, -1.0f, 1.0f },
    { 1.0f,  1.0f, -1.0f, 1.0f },
    { 1.0f, -1.0f, -1.0f, 1.0f },
    
    // negx
    { 1.0f,  1.0f, -1.0f, 1.0f },
    { 1.0f, -1.0f, -1.0f, 1.0f },
    { 1.0f,  1.0f,  1.0f, 1.0f },
    { 1.0f, -1.0f,  1.0f, 1.0f },
    
    // posz
    { 1.0f,  1.0f,  1.0f, 1.0f },
    { 1.0f, -1.0f,  1.0f, 1.0f },
    { -1.0f,  1.0f,  1.0f, 1.0f },
    { -1.0f, -1.0f,  1.0f, 1.0f },
    
    // posy
    { 1.0f,  1.0f, -1.0f, 1.0f },
    { 1.0f,  1.0f,  1.0f, 1.0f },
    { -1.0f,  1.0f, -1.0f, 1.0f },
    { -1.0f,  1.0f,  1.0f, 1.0f },
    
    // negy
    { 1.0f, -1.0f,  1.0f, 1.0f },
    { 1.0f, -1.0f, -1.0f, 1.0f },
    { -1.0f, -1.0f,  1.0f, 1.0f },
    { -1.0f, -1.0f, -1.0f, 1.0f },
};

@implementation ENHMetalSkybox
{
    id<SCNSceneRenderer> _renderer;
    id <MTLLibrary> _defaultLibrary;
    
    dispatch_semaphore_t _inflight_semaphore;
    id <MTLBuffer> _dynamicUniformBuffer[kInFlightCommandBuffers];
    
    // render stage
    id <MTLDepthStencilState> _depthState;
    
    // this value will cycle from 0 to g_max_inflight_buffers whenever a display completes ensuring renderer clients
    // can synchronize between g_max_inflight_buffers count buffers, and thus avoiding a constant buffer from being overwritten between draws
    NSUInteger _constantDataBufferIndex;
    
    // skybox
    AAPLTexture *_skyboxTex;
    id <MTLRenderPipelineState> _skyboxPipelineState;
    id <MTLBuffer> _skyboxVertexBuffer;
}

- (instancetype)initWithRenderer:(nonnull id<SCNSceneRenderer>)renderer;
{
    self = [super init];
    if (self) {
        _renderer = renderer;
        _modelviewMatrix = GLKMatrix4Identity;
        _projectionMatrix = GLKMatrix4Identity;

        id <MTLDevice> device = [renderer device];
        MTLPixelFormat depthPixelFormat = [renderer depthPixelFormat];
        
        _constantDataBufferIndex = 0;
        _inflight_semaphore = dispatch_semaphore_create(kInFlightCommandBuffers);
        
        _defaultLibrary = [device newDefaultLibrary];
        if(!_defaultLibrary) {
            NSLog(@">> ERROR: Couldnt create a default shader library");
            // assert here becuase if the shader libary isn't loading, nothing good will happen
            assert(0);
        }
        
        // allocate one region of memory for the constant buffer
        for (int i = 0; i < kInFlightCommandBuffers; i++)
        {
            _dynamicUniformBuffer[i] = [device newBufferWithLength:kMaxBufferBytesPerFrame options:0];
            _dynamicUniformBuffer[i].label = [NSString stringWithFormat:@"ConstantBuffer%i", i];
        }
        
        id <MTLFunction> vertexProgram = [_defaultLibrary newFunctionWithName:@"skyboxVertex"];
        id <MTLFunction> fragmentProgram = [_defaultLibrary newFunctionWithName:@"skyboxFragment"];
        
        //  create a pipeline state for the skybox
        MTLRenderPipelineDescriptor *skyboxPipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        skyboxPipelineStateDescriptor.label = @"SkyboxPipelineState";
        
        // the pipeline state must match the drawable framebuffer we are rendering into
        skyboxPipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

        skyboxPipelineStateDescriptor.depthAttachmentPixelFormat      = depthPixelFormat;
        
        // attach the skybox shaders to the pipeline state
        skyboxPipelineStateDescriptor.vertexFunction   = vertexProgram;
        skyboxPipelineStateDescriptor.fragmentFunction = fragmentProgram;
        
        // finally, read out the pipeline state
        _skyboxPipelineState = [device newRenderPipelineStateWithDescriptor:skyboxPipelineStateDescriptor error:nil];
        if(!_defaultLibrary) {
            NSLog(@">> ERROR: Couldnt create a pipeline");
            assert(0);
        }
        
        // create the skybox vertex buffer
        _skyboxVertexBuffer = [device newBufferWithBytes:cubeVertexData length:sizeof(cubeVertexData) options:MTLResourceOptionCPUCacheModeDefault];
        _skyboxVertexBuffer.label = @"SkyboxVertexBuffer";

        NSString *resourceName = @"skybox";
        NSString *resourceExtension = @"png";
        [self loadSkyboxWithResourceName:resourceName resourceExtension:resourceExtension];

        // setup the depth state
        MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
        depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
        depthStateDesc.depthWriteEnabled = YES;
        _depthState = [device newDepthStencilStateWithDescriptor:depthStateDesc];
    }
    return self;
}

- (BOOL)loadSkyboxWithResourceName:(NSString *)resourceName resourceExtension:(NSString *)resourceExtension
{
    NSParameterAssert(_renderer);
    id <MTLDevice> device = [_renderer device];

    _skyboxTex = [[AAPLTextureCubeMap alloc] initWithResourceName:resourceName extension:resourceExtension];
    BOOL loaded = [_skyboxTex loadIntoTextureWithDevice:device];
    return loaded;
}

- (void)renderSkybox:(id <MTLRenderCommandEncoder>)renderEncoder name:(NSString *)name
{
    // set the pipeline state object for the quad which contains its precompiled shaders
    [renderEncoder setRenderPipelineState:_skyboxPipelineState];
    
    // set the vertex buffers for the skybox at both indicies 0 and 1 since we are using its vertices as texCoords in the shader
    [renderEncoder setVertexBuffer:_skyboxVertexBuffer offset:0 atIndex:SKYBOX_VERTEX_BUFFER];
    [renderEncoder setVertexBuffer:_skyboxVertexBuffer offset:0 atIndex:SKYBOX_TEXCOORD_BUFFER];
    
    // set the model view projection matrix for the skybox
    [renderEncoder setVertexBuffer:_dynamicUniformBuffer[_constantDataBufferIndex] offset:0 atIndex:SKYBOX_CONSTANT_BUFFER];
    
    // set the fragment shader's texture and sampler
    [renderEncoder setFragmentTexture:_skyboxTex.texture atIndex:SKYBOX_IMAGE_TEXTURE];
    
    [renderEncoder drawPrimitives: MTLPrimitiveTypeTriangleStrip vertexStart: 0 vertexCount: 24];
}

- (void)render
{
    // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
    // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
    // signifying the CPU can go ahead and prepare another frame.
    dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
    
    // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
    [self updateConstantBuffer];
    
    id< MTLRenderCommandEncoder > currentRenderCommandEncoder = [_renderer currentRenderCommandEncoder];
    id <MTLCommandQueue> commandQueue = [_renderer commandQueue];
    
    // create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    [currentRenderCommandEncoder setDepthStencilState:_depthState];
    
    // render the skybox
    [self renderSkybox:currentRenderCommandEncoder name:@"skybox"];
    
    // Add a completion handler / block to be called once the command buffer is completed by the GPU. All completion handlers will be returned in the order they were committed.
    __block dispatch_semaphore_t block_sema = _inflight_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        
        // GPU has completed rendering the frame and is done using the contents of any buffers previously encoded on the CPU for that frame.
        // Signal the semaphore and allow the CPU to proceed and construct the next frame.
        dispatch_semaphore_signal(block_sema);
    }];
    
    // finalize rendering here. this will push the command buffer to the GPU
    [commandBuffer commit];
    
    // This index represents the current portion of the ring buffer being used for a given frame's constant buffer updates.
    // Once the CPU has completed updating a shared CPU/GPU memory buffer region for a frame, this index should be updated so the
    // next portion of the ring buffer can be written by the CPU. Note, this should only be done *after* all writes to any
    // buffers requiring synchronization for a given frame is done in order to avoid writing a region of the ring buffer that the GPU may be reading.
    _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kInFlightCommandBuffers;
}

- (void)updateConstantBuffer
{
    AAPL::uniforms_t *uniforms = (AAPL::uniforms_t *)[_dynamicUniformBuffer[_constantDataBufferIndex] contents];
    
    // calculate the model view projection data for the skybox
    GLKMatrix4 scaledMVM = GLKMatrix4Scale(self.modelviewMatrix, self.xSize, self.ySize, self.zSize);
    GLKMatrix4 modelViewProjectionmatrix = GLKMatrix4Multiply(self.projectionMatrix, scaledMVM);
    
    //convert to simd through Scene kit
    simd::float4x4 skyboxModelviewProjectionMatrix = SCNMatrix4ToMat4(SCNMatrix4FromGLKMatrix4(modelViewProjectionmatrix));
    
    // write the skybox transformation data into the current constant buffer
    uniforms->skybox_modelview_projection_matrix = skyboxModelviewProjectionMatrix;
    
    // Set the device orientation
    switch ([UIApplication sharedApplication].statusBarOrientation)
    {
        case UIDeviceOrientationUnknown:
            uniforms->orientation = AAPL::Unknown;
            break;
        case UIDeviceOrientationPortrait:
            uniforms->orientation = AAPL::Portrait;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            uniforms->orientation = AAPL::PortraitUpsideDown;
            break;
        case UIDeviceOrientationLandscapeRight:
            uniforms->orientation = AAPL::LandscapeRight;
            break;
        case UIDeviceOrientationLandscapeLeft:
            uniforms->orientation = AAPL::LandscapeLeft;
            break;
        default:
            uniforms->orientation = AAPL::Portrait;
            break;
    }
}

@end
