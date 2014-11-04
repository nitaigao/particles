#include <metal_stdlib>
#include "Uniforms.h"
#include "Particle.h"

using namespace metal;

struct VertexInOut {
  float4 position [[position]];
  float alpha;
};

float rand(float2 co){
  return fract(sin(dot(co.xy ,float2(12.9898,78.233))) * 43758.5453);
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
  float normFactor = 100.0f;
  
  float2 offset = posSpeedLifeTexture.read(uint2(column, row)).xy * normFactor;
  float4 offsetPositon = position + float4(offset, 0.0f, 0.0f);
  outVertex.position = uniforms.viewProjMatrix * offsetPositon;
  
  return outVertex;
};

fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]] ) {
  return half4(1.0f, 0.0, 0.0f, 1.0f);
};

kernel void initParticles(  uint2                           gid                   [[thread_position_in_grid]]
                          , texture2d<float, access::write> posSpeedLifeTexture   [[texture(0)]]
                          , texture2d<float, access::write> dirTexture            [[texture(1)]]) {
  posSpeedLifeTexture.write(float4(0.0f, 0.0f, 1.0f, 1.0f), gid);
//  float r = rand(float2(gid.x, gid.y));
//  float2 dirUnorm = float2(r, r);
  float2 dir = normalize(float2(gid));
  dirTexture.write(float4(dir, 0.0f, 1.0f), gid);
};

kernel void simulateParticles(  uint2                           gid                    [[thread_position_in_grid]]
                              , texture2d<float, access::read>  inPosSpeedLifeTexture  [[texture(0)]]
                              , texture2d<float, access::read>  inDirTexture           [[texture(1)]]
                              , texture2d<float, access::write> outPosSpeedLifeTexture [[texture(2)]]) {
  float4 inPosSpeedLife = inPosSpeedLifeTexture.read(gid);

  float normFactor = 100.0f;
  float2 inPos = inPosSpeedLife.xy * normFactor;
  float inSpeed = inPosSpeedLife.z;
  float inLife = inPosSpeedLife.w;

  float2 inDir = inDirTexture.read(gid).xy;

  float2 newPosition = inPos + inDir;// * inSpeed * (inLife > 0.0f);
  float4 outPosSpeedLife = float4(newPosition / normFactor, inSpeed, inLife);

  outPosSpeedLifeTexture.write(outPosSpeedLife, gid);
};