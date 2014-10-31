#ifndef Particles_Particle_h
#define Particles_Particle_h

typedef struct {
  simd::float3 direction;
  simd::float3 position;
  float life;
  float speed;
} Particle;

#endif
