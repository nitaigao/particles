#import "ViewController.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/matrix.h>
#import <simd/matrix_types.h>
#import "Uniforms.h"

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

static const int kNumParticles = 100;

float radians(const float& degrees) {
  return kRadians * degrees;
}

typedef struct {
  simd::float3 position;
} Particle;

@implementation ViewController {
  id <MTLDevice> device;
  id<MTLCommandQueue> commandQueue;
  id<MTLRenderPipelineState> pipeline;
  id <MTLBuffer> vertexBuffer;
  id <MTLBuffer> uniformConstantBuffer;
  id <MTLBuffer> particleConstantBuffer;
  CAMetalLayer* metalLayer;
  CADisplayLink* displayLink;
  dispatch_semaphore_t _inflight_semaphore;
  
  Particle particles[kNumParticles];
}

- (void)viewDidLoad {
  [self setupMetal];
}

- (void)resize {
  if (self.view.window == nil) {
    return;
  }
  
  float nativeScale = self.view.window.screen.nativeScale;
  self.view.contentScaleFactor = nativeScale;
  metalLayer.frame = self.view.layer.frame;
  
  CGSize drawableSize = self.view.bounds.size;
  drawableSize.width = drawableSize.width * CGFloat(self.view.contentScaleFactor);
  drawableSize.height = drawableSize.height * CGFloat(self.view.contentScaleFactor);
  
  metalLayer.drawableSize = drawableSize;
}

- (void)setupMetal {
  _inflight_semaphore = dispatch_semaphore_create(3);
  
  device = MTLCreateSystemDefaultDevice();
  
  metalLayer = [CAMetalLayer layer];
  metalLayer.device = device;
  metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  metalLayer.framebufferOnly = YES;
  
  commandQueue = [device newCommandQueue];
  
  id<MTLLibrary> library = [device newDefaultLibrary];
  
  MTLRenderPipelineDescriptor* pipeLineDescriptor = [MTLRenderPipelineDescriptor new];
  pipeLineDescriptor.vertexFunction = [library newFunctionWithName:@"passThroughVertex"];
  pipeLineDescriptor.fragmentFunction = [library newFunctionWithName:@"passThroughFragment"];
  pipeLineDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat;
  
  pipeline = [device newRenderPipelineStateWithDescriptor:pipeLineDescriptor error:nil];
  
  vertexBuffer = [device newBufferWithBytes:vertexData length:sizeof(vertexData) options:MTLResourceOptionCPUCacheModeDefault];
  
  Uniforms uniforms;
  float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
  uniforms.projectionMatrix = perspective_fov(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
  uniforms.viewMatrix = matrix_identity_float4x4;
  uniforms.viewMatrix.columns[3].z = 30.0f;
  uniformConstantBuffer = [device newBufferWithBytes:&uniforms length:sizeof(Uniforms) options:MTLResourceOptionCPUCacheModeDefault];

  memset(particles, 0, sizeof(Particle) * kNumParticles);
  particleConstantBuffer = [device newBufferWithLength:kNumParticles * sizeof(Particle) options:MTLResourceOptionCPUCacheModeDefault];
  
  [metalLayer setFrame:self.view.layer.frame];
  [self.view.layer addSublayer:metalLayer];
}

- (void)render {
  dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
  
  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  
  id<CAMetalDrawable> drawable = [metalLayer nextDrawable];
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
  displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLink:)];
  [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)displayLink:(CADisplayLink *)displayLink {
  [self update];
  [self render];
}

- (void)update {
  for (int i = 0; i < kNumParticles; i++) {
    particles[i].position.x += ((rand() % 10) - 5) * 0.01f;;
    particles[i].position.y += ((rand() % 10) - 5) * 0.01f;;
  }
  
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
