#include <metal_stdlib>
#include "Uniforms.h"

using namespace metal;

struct VertexInOut {
  float4 position [[position]];
};

vertex VertexInOut passThroughVertex(unsigned int             vid      [[vertex_id ]],
                                     constant packed_float4*  position [[buffer(0) ]],
                                     constant Uniforms&       uniforms [[buffer(1) ]]
                                     )
{
  VertexInOut outVertex;
  
  float4 in_position = position[vid];
  outVertex.position = uniforms.projectionMatrix * uniforms.viewMatrix * in_position;
  return outVertex;
};

fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]]) {
  return half4(1.0, 0.3f, 0.7f, 1.0f);
};