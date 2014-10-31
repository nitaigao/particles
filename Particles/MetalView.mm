#import "MetalView.h"

#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>

@implementation MetalView

+ (id)layerClass {
  return [CAMetalLayer class];
}

- (CAMetalLayer*)metalLayer {
  return (CAMetalLayer*)self.layer;
}

- (id<MTLDevice>)metalDevice {
  return device;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    device = MTLCreateSystemDefaultDevice();
    self.metalLayer.device = device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = YES;

  }
  return self;
}

- (void)layoutSubviews {
  [self resize];
}

- (void)resize {
  if (self.window == nil) {
    return;
  }
  
  float nativeScale = self.window.screen.nativeScale;
  self.contentScaleFactor = nativeScale;
  //  layer.frame = self.view.layer.frame;
  
  CGSize drawableSize = self.bounds.size;
  drawableSize.width = drawableSize.width * float(self.contentScaleFactor);
  drawableSize.height = drawableSize.height * float(self.contentScaleFactor);
  
//  NSLog(@"%f %f", drawableSize.width, drawableSize.height);
  
  self.metalLayer.drawableSize = drawableSize;
}


@end
