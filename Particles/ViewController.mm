#import "ViewController.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/matrix.h>
#import <simd/matrix_types.h>
#import "MetalView.h"
#import "Uniforms.h"
#import "Particle.h"

float vertexData[] = {
 -1.0, -1.0, 0.0, 1.0,
 -1.0,  1.0, 0.0, 1.0,
  1.0, -1.0, 0.0, 1.0,
//  1.0, -1.0, 0.0, 1.0,
// -1.0,  1.0, 0.0, 1.0,
  1.0,  1.0, 0.0, 1.0
};

static const float kPi_f      = float(M_PI);
static const float k1Div180_f = 1.0f / 180.0f;
static const float kRadians   = k1Div180_f * kPi_f;

static const int kNumParticles = 1000;

float radians(const float& degrees) {
  return kRadians * degrees;
}

@implementation ViewController {
  id <MTLDevice> device;
  CAMetalLayer* layer;
  
  id<MTLCommandQueue> commandQueue;
  id<MTLRenderPipelineState> renderPipeline;
  
//  id<MTLCommandQueue> computeCommandQueue;
//  id<MTLComputePipelineState> particleSimulateComputePipeline;
  
  id <MTLBuffer> vertexBuffer;
  id <MTLBuffer> uniformConstantBuffer;
  
  id <MTLTexture> particlePosSpeedLifeTexture;
//  id <MTLTexture> particlePosSpeedLifeTexture2;
  id <MTLTexture> particleDirTexture;


  
//  id <MTLBuffer> particleConstantBuffer;
  dispatch_semaphore_t _inflight_semaphore;
  
  id<MTLLibrary> library;
  
  id<MTLFunction> initParticlesKernelFunction;
  id<MTLComputePipelineState> initParticlesComputePipeline;
  
  id<MTLFunction> simulateParticlesKernelFunction;
  id<MTLComputePipelineState> simulateParticlesComputePipeline;
  
  CGPoint emissionLocation;
  
  Particle particles[kNumParticles];
}

- (void)viewDidLoad {
  [self setupMetal];
}

- (int)nearestPowerOf2:(int)x {
  int next = pow(2, ceil(log(x)/log(2)));
  return next;
}

- (void)setupMetal {
  _inflight_semaphore = dispatch_semaphore_create(3);
  
  MetalView* metalView = (MetalView*)self.view;
  device = metalView.metalDevice;
  layer = metalView.metalLayer;
  
  emissionLocation = CGPointMake(0, 0);
  
  commandQueue = [device newCommandQueue];
  
  library = [device newDefaultLibrary];
  
  initParticlesKernelFunction = [library newFunctionWithName:@"initParticles"];
  initParticlesComputePipeline = [device newComputePipelineStateWithFunction:initParticlesKernelFunction error:nil];
  
  simulateParticlesKernelFunction = [library newFunctionWithName:@"simulateParticles"];
  simulateParticlesComputePipeline = [device newComputePipelineStateWithFunction:simulateParticlesKernelFunction error:nil];
  
  
//  id<MTLFunction> kernelFunction = [library newFunctionWithName:@"simulateParticles"];
//  particleSimulateComputePipeline = [device newComputePipelineStateWithFunction:kernelFunction error:nil];
  
//  MTLComputePipelineDescriptor* computePipelineDescriptor = [MTLComputePipelineDescriptor new];
//  computePipeline =
  
  MTLRenderPipelineDescriptor* pipeLineDescriptor = [MTLRenderPipelineDescriptor new];
  pipeLineDescriptor.vertexFunction = [library newFunctionWithName:@"passThroughVertex"];
  pipeLineDescriptor.fragmentFunction = [library newFunctionWithName:@"passThroughFragment"];
  pipeLineDescriptor.colorAttachments[0].pixelFormat = layer.pixelFormat;
  pipeLineDescriptor.colorAttachments[0].blendingEnabled = YES;
  
  pipeLineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
  pipeLineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  pipeLineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;

  
  pipeLineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
  pipeLineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  pipeLineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
  renderPipeline = [device newRenderPipelineStateWithDescriptor:pipeLineDescriptor error:nil];
  
  vertexBuffer = [device newBufferWithBytes:vertexData length:sizeof(vertexData) options:MTLResourceOptionCPUCacheModeDefault];
  
  static const int kMinBufferSize = 196;
  uniformConstantBuffer = [device newBufferWithLength:kMinBufferSize options:MTLResourceOptionCPUCacheModeDefault];
  
//  int next = [self nearestPowerOf2:kNumParticles];
//  NSUInteger textureSize = next / 2;
  
  NSUInteger textureSize = 32;

  MTLTextureDescriptor* particleDataTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:textureSize height:textureSize mipmapped:NO];
  particlePosSpeedLifeTexture = [device newTextureWithDescriptor:particleDataTextureDescriptor];
  
//  MTLTextureDescriptor* particleDataTextureDescriptor2 = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:textureSize height:textureSize mipmapped:NO];
//  particlePosSpeedLifeTexture2 = [device newTextureWithDescriptor:particleDataTextureDescriptor2];
//  
  MTLTextureDescriptor* particleDirTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:textureSize height:textureSize mipmapped:NO];
  particleDirTexture = [device newTextureWithDescriptor:particleDirTextureDescriptor];

  [self initParticles];
  
//  for (int i = 0; i < kNumParticles; i++) {
//    float angle = (2 * (rand() / (float)RAND_MAX) - 1.0f) * 1.0f;//3.141;
//    
//    simd::float2x2 rotation = {
//      simd::float2 { simd::cos(angle), -simd::sin(angle) },
//      simd::float2 { simd::sin(angle), simd::cos(angle) }
//    };
//    
//    simd::float2 direction = { 0.0f, 1.0f };
//    simd::float2 rotatedDirection = direction * rotation;
//    
//    particles[i].direction.xy = rotatedDirection;
//    particles[i].life = 0;//(rand() % 5);
//    particles[i].speed = arc4random_uniform(200);// (rand() % 90);
//  }
  
//  particleConstantBuffer = [device newBufferWithLength:kNumParticles * sizeof(Particle) options:MTLResourceOptionCPUCacheModeDefault];
}

- (void)setUniforms:(matrix_float4x4)perspective view:(matrix_float4x4)view depth:(float)depth {
  Uniforms uniforms;
  
  uniforms.viewProjMatrix = matrix_multiply(perspective, view);
  
  uint8_t *bufferPointer = (uint8_t *)[uniformConstantBuffer contents];
  memcpy(bufferPointer, &uniforms, sizeof(Uniforms));
}

double frameTimeStamp = 0;

- (void)render {
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
  
  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  
  id<CAMetalDrawable> drawable = [layer nextDrawable];
  id<MTLTexture> texture = drawable.texture;
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor new];
  renderPassDescriptor.colorAttachments[0].texture = texture;
  renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
  renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
  renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0);
  
  { // Model Specific
    id <MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [commandEncoder pushDebugGroup:@"Render Particles"];
    [commandEncoder setRenderPipelineState:renderPipeline];
    [commandEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [commandEncoder setVertexBuffer:uniformConstantBuffer offset:0 atIndex:1];
    [commandEncoder setVertexTexture:particlePosSpeedLifeTexture atIndex:0];
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:kNumParticles];
    [commandEncoder endEncoding];
    [commandEncoder popDebugGroup];
  }
  
  __block dispatch_semaphore_t block_sema = _inflight_semaphore;
  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    dispatch_semaphore_signal(block_sema);
  }];

  [commandBuffer presentDrawable:drawable];
  [commandBuffer commit];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  CADisplayLink* displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLink:)];
  displayLink.frameInterval = 1;
  [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
  
  dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    while (true) {
      
    }
  });
}

- (void)displayLink:(CADisplayLink *)displayLink {
  double currentTime = displayLink.timestamp;
  
  if (frameTimeStamp <= 0) {
    frameTimeStamp = currentTime;
  }
  
  float dt = currentTime - frameTimeStamp;
  frameTimeStamp = currentTime;
  
  NSLog(@"%f, %f", dt, displayLink.duration);
  
//  float fps = 1.0f / dt;
//  fpsLabel.text = [NSString stringWithFormat:@"%f fps", fps];
//  [self update:dt];
  
  float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
  matrix_float4x4 perspective = perspective_fov(65.0f * (M_PI / 180.0f), aspect, 0.1f, 1000.0f);
  
  matrix_float4x4 view = matrix_identity_float4x4;
  view.columns[3].z = 90.0f;
  
  {
//    vector_float4 emissionLocationNDC = { (float)emissionLocation.x, (float)emissionLocation.y, 0.9f, 1.0f };
//    vector_float4 emissionClip = matrix_multiply(matrix_invert(perspective), emissionLocationNDC);
//    vector_float4 emissionView = emissionClip / emissionClip.w;
//    vector_float4 emissionWorld = matrix_multiply(matrix_invert(view), emissionView);
    
//    NSLog(@"%f %f %f", emissionWorld.x, emissionWorld.y, emissionWorld.z);
    
//      vector_float3 emissionWorld = { 0, 0, 0 };
    //
    
    //  NSLog(@"%f %f %f", emissionWorld.x, emissionWorld.y, emissionWorld.z);
    //  matrix_float4x4 model = {
    //    .columns[0] = { 1.0f, 0.0f, 0.0f,  0.0f },
    //    .columns[1] = { 0.0f, 1.0f, 0.0f,  0.0f },
    //    .columns[2] = { 0.0f, 0.0f, 1.0f,  0.0f },
    //    .columns[3] = { emissionWorld.x, emissionWorld.y, depth, 1.0f }
    //  };
    
    //  matrix_float4x4 modelView = matrix_multiply(view, model);
  }
  [self update:0.016f];
  
  [self setUniforms:perspective view:view depth:900.0f];
  [self render];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
  UITouch *touch = [[event allTouches] anyObject];
  CGPoint touchLocation = [touch locationInView:touch.view];
  
  CGPoint touchLocationNorm = CGPointMake(touchLocation.x / self.view.frame.size.width, touchLocation.y / self.view.frame.size.height);
  CGPoint touchLocationNDC = CGPointMake(touchLocationNorm.x * 2.0f - 1.0f, touchLocationNorm.y * 2.0f - 1.0f);
  emissionLocation = touchLocationNDC;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
  UITouch *touch = [[event allTouches] anyObject];
  CGPoint touchLocation = [touch locationInView:self.view];
  
  CGPoint touchLocationNorm = CGPointMake(touchLocation.x / self.view.frame.size.width, touchLocation.y / self.view.frame.size.height);
  CGPoint touchLocationNDC = CGPointMake(touchLocationNorm.x * 2.0f - 1.0f, touchLocationNorm.y * 2.0f - 1.0f);
  emissionLocation = touchLocationNDC;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
  UITouch *touch = [[event allTouches] anyObject];
  CGPoint touchLocation = [touch locationInView:touch.view];
  
  CGPoint touchLocationNorm = CGPointMake(touchLocation.x / self.view.frame.size.width, touchLocation.y / self.view.frame.size.height);
  CGPoint touchLocationNDC = CGPointMake(touchLocationNorm.x * 2.0f - 1.0f, touchLocationNorm.y * 2.0f - 1.0f);
  emissionLocation = touchLocationNDC;
}

- (void)initParticles {
  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];
  [commandEncoder pushDebugGroup:@"Init Particles"];
  [commandEncoder setComputePipelineState:initParticlesComputePipeline];
  [commandEncoder setTexture:particlePosSpeedLifeTexture atIndex:0];
  [commandEncoder setTexture:particleDirTexture atIndex:1];
  [commandEncoder setTexture:particlePosSpeedLifeTexture atIndex:2];
  
  MTLSize threadsPerGroup = MTLSizeMake(16, 16, 1);
  MTLSize threadgroupCounts = MTLSizeMake(2, 2, 1);
  
  [commandEncoder dispatchThreadgroups:threadgroupCounts threadsPerThreadgroup:threadsPerGroup];
  
  [commandEncoder popDebugGroup];
  
  [commandEncoder endEncoding];
  [commandBuffer commit];
  
  [commandBuffer waitUntilCompleted];
}

- (void)update:(float)dt {
  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  id<MTLComputeCommandEncoder> commandEncoder = [commandBuffer computeCommandEncoder];

  [commandEncoder pushDebugGroup:@"Simulate Particles"];
  [commandEncoder setComputePipelineState:simulateParticlesComputePipeline];
  [commandEncoder setTexture:particlePosSpeedLifeTexture atIndex:0];
  [commandEncoder setTexture:particleDirTexture atIndex:1];
  [commandEncoder setTexture:particlePosSpeedLifeTexture atIndex:2];
  
  MTLSize threadsPerGroup = MTLSizeMake(16, 16, 1);
  MTLSize threadgroupCounts = MTLSizeMake(2, 2, 1);
  
  [commandEncoder dispatchThreadgroups:threadgroupCounts threadsPerThreadgroup:threadsPerGroup];
  
  [commandEncoder popDebugGroup];

  [commandEncoder endEncoding];
  [commandBuffer commit];

  [commandBuffer waitUntilCompleted];
  
//  int emissionRate = 1000;
//  int emissionCount = 0;
//  for (int i = 0; i < kNumParticles; i++) {
//    particles[i].position = particles[i].position + particles[i].direction * particles[i].speed * dt;
//    
//    particles[i].life -= dt;
//    if (particles[i].life <= 0.0f) {
//      particles[i].life = 0.0f;
//    }
//    
//    if (particles[i].life <= 0.0f && emissionCount < emissionRate) {
//      particles[i].life = arc4random_uniform(200);// (rand() % 8);
//      particles[i].position = { 0, 0, 0 };
//      emissionCount++;
//    }
//  }
//  
//  uint8_t *bufferPointer = (uint8_t *)[particleConstantBuffer contents];
//  memcpy(bufferPointer, particles, sizeof(Particle) * kNumParticles);
}

static matrix_float4x4 perspective_fov(const float fovY, const float aspect, const float nearZ, const float farZ) {
  float yscale = 1.0f / tanf(fovY * 0.5f); // 1 / tan == cot
  float xscale = yscale / aspect;
  float q = farZ / (farZ - nearZ);

  matrix_float4x4 m = {
    .columns[0] = { xscale, 0.0f, 0.0f, 0.0f },
    .columns[1] = { 0.0f, yscale, 0.0f, 0.0f },
    .columns[2] = { 0.0f, 0.0f, q, 1.0f },
    .columns[3] = { 0.0f, 0.0f, q * -nearZ, 0.0f }
  };

  return m;
}

@end
