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
  1.0, -1.0, 0.0, 1.0,
 -1.0,  1.0, 0.0, 1.0,
  1.0,  1.0, 0.0, 1.0
};

static const float kPi_f      = float(M_PI);
static const float k1Div180_f = 1.0f / 180.0f;
static const float kRadians   = k1Div180_f * kPi_f;

static const int kNumParticles = 10000;

float radians(const float& degrees) {
  return kRadians * degrees;
}

@implementation ViewController {
  id <MTLDevice> device;
  CAMetalLayer* layer;
  id<MTLCommandQueue> commandQueue;
  id<MTLRenderPipelineState> pipeline;
  id <MTLBuffer> vertexBuffer;
  id <MTLBuffer> uniformConstantBuffer;
  id <MTLBuffer> particleConstantBuffer;
  dispatch_semaphore_t _inflight_semaphore;
  
  Particle particles[kNumParticles];
}

- (void)viewDidLoad {
  [self setupMetal];
}

- (void)setupMetal {
  _inflight_semaphore = dispatch_semaphore_create(3);
  
  MetalView* metalView = (MetalView*)self.view;
  device = metalView.metalDevice;
  layer = metalView.metalLayer;
  
  commandQueue = [device newCommandQueue];
  
  id<MTLLibrary> library = [device newDefaultLibrary];
  
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
  pipeline = [device newRenderPipelineStateWithDescriptor:pipeLineDescriptor error:nil];
  
  vertexBuffer = [device newBufferWithBytes:vertexData length:sizeof(vertexData) options:MTLResourceOptionCPUCacheModeDefault];
  
  uniformConstantBuffer = [device newBufferWithLength:sizeof(Uniforms) options:MTLResourceOptionCPUCacheModeDefault];

  memset(particles, 0, sizeof(Particle) * kNumParticles);
  
  for (int i = 0; i < kNumParticles; i++) {
    float angle = 2 * (rand() / (float)RAND_MAX) - 1.0f;
    
    simd::float2x2 rotation = {
      simd::float2 { simd::cos(angle), -simd::sin(angle) },
      simd::float2 { simd::sin(angle), simd::cos(angle) }
    };
    
    simd::float2 direction = { 0.0f, 1.0f };
    simd::float2 rotatedDirection = direction * rotation;
    
    particles[i].direction.xy = rotatedDirection;
//    particles[i].life = (rand() % 5);
    particles[i].speed = (rand() % 20);
  }
  
  particleConstantBuffer = [device newBufferWithLength:kNumParticles * sizeof(Particle) options:MTLResourceOptionCPUCacheModeDefault];
}

- (void)setUniforms:(matrix_float4x4)perspective view:(matrix_float4x4)view {
  Uniforms uniforms;
  uniforms.projectionMatrix = perspective;
  uniforms.viewMatrix = view;
  
  uint8_t *bufferPointer = (uint8_t *)[uniformConstantBuffer contents];
  memcpy(bufferPointer, &uniforms, sizeof(Uniforms));
}

- (void)render {
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
  
  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  
  id<CAMetalDrawable> drawable = [layer nextDrawable];
  id<MTLTexture> texture = drawable.texture;
  
  MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor new];
  renderPassDescriptor.colorAttachments[0].texture = texture;
  renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
  renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
  renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 1.0, 0.0, 1.0);
  
  { // Model Specific
    id <MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [commandEncoder setRenderPipelineState:pipeline];
    [commandEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [commandEncoder setVertexBuffer:uniformConstantBuffer offset:0 atIndex:1];
    [commandEncoder setVertexBuffer:particleConstantBuffer offset:0 atIndex:2];
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:kNumParticles];
    [commandEncoder endEncoding];
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
  [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
  
  dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    while (true) {
      [self update:0.016f];
      [NSThread sleepForTimeInterval:0.016f];
    }
  } );
}

double frameTimeStamp = 0;

- (void)displayLink:(CADisplayLink *)displayLink {
  double currentTime = displayLink.timestamp;
  
  if (frameTimeStamp <= 0) {
    frameTimeStamp = currentTime;
  }
  
  float dt = currentTime - frameTimeStamp;
  frameTimeStamp = currentTime;
  
  float fps = 1.0f / dt;
  fpsLabel.text = [NSString stringWithFormat:@"%d fps", (int)std::round(fps)];
//  [self update:dt];
  
  float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
  matrix_float4x4 perspective = perspective_fov(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
  
  matrix_float4x4 view = matrix_identity_float4x4;
  view.columns[3].z = 30.0f;
  
  [self setUniforms:perspective view:view];
  [self render];
}

- (void)update:(float)dt {
  for (int i = 0; i < kNumParticles; i++) {
    particles[i].position = particles[i].position + particles[i].direction * particles[i].speed * dt;
    
    particles[i].life -= dt;
    if (particles[i].life <= 0.0f) {
      particles[i].life = 0.0f;
    }
    
    if (particles[i].life <= 0.0f) {
      particles[i].life = (rand() % 5);
      particles[i].position = { 0, 0, 0 };
    }

  }
  
//  for (int i = 0; i < kNumParticles; i++) {
//    if (particles[i].life <= 0.0f) {
//      particles[i].life = (rand() % 5);
//      particles[i].position = { 0, 0, 0 };
//    }
//  }

  uint8_t *bufferPointer = (uint8_t *)[particleConstantBuffer contents];
  memcpy(bufferPointer, particles, sizeof(Particle) * kNumParticles);
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
