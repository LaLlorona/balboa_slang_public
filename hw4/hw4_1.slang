[shader("compute")]
[numthreads(64, 1, 1)]
void compute_main(uint tid: SV_DispatchThreadID,
                  RWStructuredBuffer<float3> positions,
                  RWStructuredBuffer<float3> velocities,
                  uniform uint num_particles,
                  // time step size
                  uniform float dt)
{
    if (tid >= num_particles)
    {
        return;
    }
    float floorYCoordinate = -0.97;
    float3 currentVelocity = velocities[tid];
    float3 currentPosition = positions[tid];
    float3 nextFrameVelocity = currentVelocity + float3(0, -9.8, 0) * dt;
    float3 nextFramePosition = currentPosition + nextFrameVelocity * dt;

    if (nextFramePosition.y < floorYCoordinate)
    {
        nextFramePosition = float3(nextFramePosition.x, floorYCoordinate, nextFramePosition.z);
        nextFrameVelocity = float3(nextFrameVelocity.x, -nextFrameVelocity.y, nextFrameVelocity.z);
    }
    positions[tid] = nextFramePosition;
    velocities[tid] = nextFrameVelocity;
}
