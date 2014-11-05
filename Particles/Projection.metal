#include <metal_stdlib>
#include "Uniforms.h"
#include "Particle.h"

using namespace metal;

struct VertexInOut {
  float4 position [[position]];
  float alpha;
};

float rand(float2 co);
float rand(float2 co) {
  return fract(sin(dot(co.xy, float2(12.9898,78.233))) * 43758.5453);
}

vertex VertexInOut passThroughVertex(  unsigned         int             vid                 [[vertex_id  ]]
                                     , unsigned         int             iid                 [[instance_id]]
                                     , constant         float4*         positions           [[buffer(0)  ]]
                                     , constant         Uniforms&       uniforms            [[buffer(1)  ]]
                                     , texture2d<float> posSpeedLifeTexture                 [[texture(0)]]) {
  VertexInOut outVertex;
  
  float4 position = positions[vid];
  uint row = floor(iid / 32.0f);
  uint column = iid % 32;
  
  float2 offset = posSpeedLifeTexture.read(uint2(column, row)).xy;
  
  float4 offsetPositon = position + float4(offset, 0.0f, 0.0f);
  outVertex.position = uniforms.viewProjMatrix * offsetPositon;
  
  return outVertex;
};

fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]] ) {
  return half4(1.0f, 0.0, 0.0f, 1.0f);
};

kernel void initParticles(  uint2                           gid                   [[thread_position_in_grid]]
                          , uint                            tgi                   [[thread_index_in_threadgroup]]
                          , texture2d<float, access::write> posSpeedLifeTexture   [[texture(0)]]
                          , texture2d<float, access::write> dirTexture            [[texture(1)]]
                          , texture2d<float, access::read>  randomTexture         [[texture(2)]]) {
  float2 random = randomTexture.read(gid).xy;
  posSpeedLifeTexture.write(float4(0.0f, 0.0f, 1.0f, 1.0f), gid);
  dirTexture.write(float4(normalize(random), 0.0f, 1.0f), gid);
};

kernel void simulateParticles(  uint2                           gid                    [[thread_position_in_grid]]
                              , texture2d<float, access::read>  inPosSpeedLifeTexture  [[texture(0)]]
                              , texture2d<float, access::read>  inDirTexture           [[texture(1)]]
                              , texture2d<float, access::read>  randomTexture          [[texture(2)]]
                              , texture2d<float, access::write> outPosSpeedLifeTexture [[texture(3)]]
                              , texture2d<float, access::write> outDirTexture          [[texture(4)]]) {
  float4 inPosSpeedLife = inPosSpeedLifeTexture.read(gid);
  float2 inPos = inPosSpeedLife.xy;

  float inSpeed = inPosSpeedLife.z;
  float inLife = inPosSpeedLife.w;
  
  float2 inDir = inDirTexture.read(gid).xy;
  float2 newPosition = inPos + inDir * inSpeed;
  
  float outLife = inLife - 0.016f;
  float2 outDir = inDir;
  
  if (outLife <= 0.0f) {
    float2 random = randomTexture.read(gid).xy;
    newPosition = float2(0, 0);
    outLife = 2 + rand(random);
    float x = rand(random) * 2.0f - 1.0f;
    float y = rand(1.0f - random) * 2.0f - 1.0f;
    outDir = normalize(float2(x, y));
  }

  float4 outPosSpeedLife = float4(newPosition, inSpeed, outLife);
  outPosSpeedLifeTexture.write(outPosSpeedLife, gid);
  
  outDirTexture.write(float4(outDir, 0.0f, 1.0f), gid);
};