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
  
  id <MTLBuffer> vertexBuffer;
  id <MTLBuffer> uniformConstantBuffer;
  
  id <MTLTexture> particlePosSpeedLifeTexture;
  id <MTLTexture> particleDirTexture;
  id<MTLTexture> randomTexture;
  
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
  
  NSUInteger textureSize = 32;

  MTLTextureDescriptor* particleDataTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:textureSize height:textureSize mipmapped:NO];
  particlePosSpeedLifeTexture = [device newTextureWithDescriptor:particleDataTextureDescriptor];
  
  MTLTextureDescriptor* particleDirTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:textureSize height:textureSize mipmapped:NO];
  particleDirTexture = [device newTextureWithDescriptor:particleDirTextureDescriptor];
  
  MTLTextureDescriptor* randomTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:textureSize height:textureSize mipmapped:NO];
  randomTexture = [device newTextureWithDescriptor:randomTextureDescriptor];
  
  int textureWidth = 32;
  int textureHeight = 32;
  int textureArea = textureWidth * textureHeight;
  vector_float4 randomBytes[textureArea];
  for (int i = 0; i < textureArea; i++) {
    randomBytes[i].x = (arc4random_uniform(100) / 100.0f) * 2.0f - 1.0f;
    randomBytes[i].y = (arc4random_uniform(100) / 100.0f) * 2.0f - 1.0f;
    randomBytes[i].z = (arc4random_uniform(100) / 100.0f) * 2.0f - 1.0f;
    randomBytes[i].w = 1.0f;
//    NSLog(@"%f %f", randomBytes[i].x, randomBytes[i].y);
  }
  
  [randomTexture replaceRegion:MTLRegionMake2D(0, 0, textureWidth, textureHeight) mipmapLevel:0 withBytes:randomBytes bytesPerRow:textureWidth * sizeof(vector_float4)];
  
  [self initParticles];
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
}

- (void)displayLink:(CADisplayLink *)displayLink {
  double currentTime = displayLink.timestamp;
  
  if (frameTimeStamp <= 0) {
    frameTimeStamp = currentTime;
  }
  
//  float dt = currentTime - frameTimeStamp;
//  frameTimeStamp = currentTime;
  
//  NSLog(@"%f, %f", dt, displayLink.duration);
  
//  float fps = 1.0f / dt;
//  fpsLabel.text = [NSString stringWithFormat:@"%f fps", fps];
//  [self update:dt];
  
  float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
  matrix_float4x4 perspective = perspective_fov(65.0f * (M_PI / 180.0f), aspect, 0.1f, 1000.0f);
  
  matrix_float4x4 view = matrix_identity_float4x4;
  view.columns[3].z = 90.0f;
  
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
  [commandEncoder setTexture:randomTexture atIndex:2];
  
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
  [commandEncoder setTexture:randomTexture atIndex:2];
  [commandEncoder setTexture:particlePosSpeedLifeTexture atIndex:3];
  [commandEncoder setTexture:particleDirTexture atIndex:4];
  
  MTLSize threadsPerGroup = MTLSizeMake(16, 16, 1);
  MTLSize threadgroupCounts = MTLSizeMake(2, 2, 1);
  
  [commandEncoder dispatchThreadgroups:threadgroupCounts threadsPerThreadgroup:threadsPerGroup];
  
  [commandEncoder popDebugGroup];

  [commandEncoder endEncoding];
  [commandBuffer commit];

  [commandBuffer waitUntilCompleted];
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
