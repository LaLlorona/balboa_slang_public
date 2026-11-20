[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid: SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         // The CSR matrix data structure
                         StructuredBuffer<uint> row_ptr,
                         StructuredBuffer<uint> neighbors,
                         // Rest lengthes of the neighbor edges
                         StructuredBuffer<float> neighbor_rest,
                         uniform uint num_particles)
{
    if (tid >= num_particles)
    {
        return;
    }
    // TODO: HW 4.4. Your code below.
    if (inv_masses[tid] == 0)
    {
        positions_out[tid] = positions_in[tid];
        return;
    }
    float3 positionOfCurrentParticle = positions_in[tid];
    float weightOfCurrentParticle = inv_masses[tid];

    float3 correction = 0;
    int totalNumberOfNeighbors = 0;
    int neighborStartIndex = row_ptr[tid];
    int neighborEndIndex = row_ptr[tid + 1];
    for (int i = neighborStartIndex; i < neighborEndIndex; i++)
    {
        int neighborIndex = neighbors[i];
        totalNumberOfNeighbors++;
        float weightOfNeighborParticle = inv_masses[neighborIndex];
        float3 positionOfNeighborParticle = positions_in[neighborIndex];
        float3 d = (positionOfNeighborParticle - positionOfCurrentParticle);
        float constraintLength = neighbor_rest[i];

        correction += weightOfCurrentParticle / (weightOfCurrentParticle + weightOfNeighborParticle) * (length(d) - constraintLength) * d / (length(d));
    }
    positions_out[tid] = positions_in[tid] + correction / totalNumberOfNeighbors;
}
