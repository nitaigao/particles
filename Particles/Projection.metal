#include <metal_stdlib>
#include "Uniforms.h"
#include "Particle.h"

using namespace metal;

struct VertexInOut {
  float4 position [[position]];
  float alpha;
};

vertex VertexInOut passThroughVertex(unsigned int             vid       [[vertex_id  ]],
                                     unsigned int             iid       [[instance_id]],
                                     constant packed_float4*  position  [[buffer(0)  ]],
                                     constant Uniforms&       uniforms  [[buffer(1)  ]],
                                     constant Particle*       particles [[buffer(2)  ]]
                                     )
{
  VertexInOut outVertex;
  
  float4 v_position = position[vid];
  Particle particle = particles[iid];
  
  float4 in_position = v_position + float4(particle.position, 0.0f);
  outVertex.position = uniforms.projectionMatrix * uniforms.viewMatrix * in_position;
  
  outVertex.alpha = particle.life;
  
  return outVertex;
};

fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]]) {
  return half4(1.0, 0.0f, 0.0f, inFrag.alpha);
};