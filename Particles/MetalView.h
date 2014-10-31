#import <UIKit/UIKit.h>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@interface MetalView : UIView {
  id<MTLDevice> device;
}

@property (nonatomic, weak) CAMetalLayer* metalLayer;
@property (nonatomic, weak) id<MTLDevice> metalDevice;

@end
