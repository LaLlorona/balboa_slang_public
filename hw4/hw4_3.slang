static const float FLOOR_Y_COORDINATE = -0.97;
static const float GRAVITY = -9.8;

static const int structural[4][2] = { { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 } };
static const int shearing[4][2] = { { -1, -1 }, { -1, 1 }, { 1, 1 }, { 1, -1 } };
static const int bending[4][2] = { { -2, 0 }, { 2, 0 }, { 0, 2 }, { 0, -2 } };

// static const int allClothingIndexs[3][4][2] = { { { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 } }, { { -1, -1 }, { -1, 1 }, { 1, 1 }, { 1, -1 } }, { { -2, 0 }, { 2, 0 }, { 0, 2 }, { 0, -2 } } };

static const int allClothingIndexs[3][4][2] = { structural, shearing, bending };
public bool IsIndexInside(int x, int y, int2 grid_size)
{
    return x >= 0 && x < grid_size.x && y >= 0 && y < grid_size.y;
}
public int convertCoordinateToIndex(int xIndex, int yIndex, int gridSizeX)
{
    return yIndex * gridSizeX + xIndex;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid: SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         uniform int2 grid_size,
                         uniform float2 spacing)
{
    if (tid >= grid_size.x * grid_size.y)
    {
        return;
    }
    // TODO: HW 4.3. Your code below.

    // copy
    if (inv_masses[tid] == 0)
    {
        positions_out[tid] = positions_in[tid];
        return;
    }
    int xIndex = tid % grid_size.x;
    int yIndex = tid / grid_size.x;
    float3 positionOfCurrentParticle = positions_in[tid];
    float weightOfCurrentParticle = inv_masses[tid];

    float3 correction = 0;
    int totalNumberOfNeighbors = 0;

    for (int j = 0; j < 3; j++)
    {
        for (int i = 0; i < 4; i++)
        {
            int[2] clothNeighborOffset = allClothingIndexs[j][i];
            int targetX = xIndex + clothNeighborOffset[0];
            int targetY = yIndex + clothNeighborOffset[1];
            if (IsIndexInside(targetX, targetY, grid_size))
            {
                totalNumberOfNeighbors++;
                int neighborIndex = convertCoordinateToIndex(targetX, targetY, grid_size.x);
                float weightOfNeighborParticle = inv_masses[neighborIndex];
                float3 positionOfNeighborParticle = positions_in[neighborIndex];
                float3 d = (positionOfNeighborParticle - positionOfCurrentParticle);
                float constraintLength = sqrt((clothNeighborOffset[0] * spacing[0]) * (clothNeighborOffset[0] * spacing[0]) +
                                              (clothNeighborOffset[1] * spacing[1]) * (clothNeighborOffset[1] * spacing[1]));

                correction += weightOfCurrentParticle / (weightOfCurrentParticle + weightOfNeighborParticle) * (length(d) - constraintLength) * d / (length(d));
            }
        }
    }

    positions_out[tid] = positions_in[tid] + correction / totalNumberOfNeighbors;
}
