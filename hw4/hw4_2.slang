static const float FLOOR_Y_COORDINATE = -0.97;
static const float GRAVITY = -9.8;

[shader("compute")]
[numthreads(64, 1, 1)]
void predict(uint tid: SV_DispatchThreadID,
             // Updated position
             RWStructuredBuffer<float3> positions,
             // Store the position before update
             RWStructuredBuffer<float3> old_positions,
             RWStructuredBuffer<float3> velocities,
             StructuredBuffer<float> inv_masses,
             uniform uint num_particles,
             // time step size
             uniform float dt)
{
    if (tid >= num_particles)
    {
        return;
    }
    if (inv_masses[tid] == 0)
    {
        positions[tid] = old_positions[tid];
        velocities[tid] = 0;
        return;
    }

    float3 currentVelocity = velocities[tid];
    float3 currentPosition = positions[tid];
    old_positions[tid] = currentPosition;
    float3 nextFrameVelocity = currentVelocity + float3(0, GRAVITY, 0) * dt;
    float3 nextFramePosition = currentPosition + nextFrameVelocity * dt;

    // if (nextFramePosition.y < FLOOR_Y_COORDINATE)
    // {
    //     nextFramePosition = float3(nextFramePosition.x, FLOOR_Y_COORDINATE, nextFramePosition.z);
    //     nextFrameVelocity = float3(nextFrameVelocity.x, -nextFrameVelocity.y, nextFrameVelocity.z);
    // }
    positions[tid] = nextFramePosition;
    velocities[tid] = nextFrameVelocity;
}

int[2] get_neighbors(int index, int num_particles)
{
    int result[2] = { -1, -1 };
    if (index == 0)
    {
        result[0] = index + 1;
    }
    else if (index == num_particles - 1)
    {
        result[0] = index - 1;
    }
    else
    {
        result[0] = index - 1;
        result[1] = index + 1;
    }
    return result;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid: SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         StructuredBuffer<float> rest_lengths,
                         uniform uint num_particles)
{
    if (tid >= num_particles)
    {
        return;
    }
    if (inv_masses[tid] == 0)
    {
        positions_out[tid] = positions_in[tid];
        return;
    }
    // TODO: HW 4.2. Your code below.
    float3 correction = 0;
    int[2] neighbors = get_neighbors(tid, num_particles);
    float weightOfCurrentParticle = inv_masses[tid];
    float3 positionOfCurrentParticle = positions_in[tid];
    for (int i = 0; i < 2; i++)
    {
        int neighborIndex = neighbors[i];
        if (neighborIndex == -1)
        {
            continue;
        }
        float weightOfNeighborParticle = inv_masses[neighborIndex];
        float3 positionOfNeighborParticle = positions_in[neighborIndex];
        float3 d = (positionOfNeighborParticle - positionOfCurrentParticle);
        float constraintLength = rest_lengths[min(tid, neighborIndex)];

        correction += weightOfCurrentParticle / (weightOfCurrentParticle + weightOfNeighborParticle) * (length(d) - constraintLength) * d / (length(d));
    }
    int numNeighbors = tid == 0 || tid == num_particles - 1 ? 1 : 2;

    positions_out[tid] = positions_in[tid] + correction / numNeighbors;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void update_velocity(uint tid: SV_DispatchThreadID,
                     RWStructuredBuffer<float3> positions,
                     StructuredBuffer<float3> old_positions,
                     RWStructuredBuffer<float3> velocities,
                     StructuredBuffer<float> inv_masses,
                     uniform uint num_particles,
                     // time step size
                     uniform float dt)
{
    if (tid >= num_particles)
    {
        return;
    }
    if (inv_masses[tid] == 0)
    {
        // positions[tid] = old_positions[tid];
        // velocities[tid] = 0;
        return;
    }
    float3 nextFramePosition = positions[tid];

    if (nextFramePosition.y < FLOOR_Y_COORDINATE)
    {
        nextFramePosition = float3(nextFramePosition.x, FLOOR_Y_COORDINATE, nextFramePosition.z);
    }
    float3 nextFrameVelocity = (nextFramePosition - old_positions[tid]) / dt;
    positions[tid] = nextFramePosition;
    velocities[tid] = nextFrameVelocity;
}
