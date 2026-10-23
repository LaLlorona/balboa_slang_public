static const float Epsilon = 0.000001;

bool IsTwoFloatSame(float a, float b)
{
    return abs(a - b) < Epsilon;
}

bool IsScreenCoordinateInsideTriangle(
    float2 xyScreenCoordinate,
    float2 sp0,
    float2 sp1,
    float2 sp2)
{
    float2 e01 = sp1 - sp0;
    float2 e12 = sp2 - sp1;
    float2 e20 = sp0 - sp2;

    float2 ne01 = float2(e01.y, -e01.x);
    float2 ne12 = float2(e12.y, -e12.x);
    float2 ne20 = float2(e20.y, -e20.x);

    float E01p = dot(xyScreenCoordinate - sp0, ne01);
    float E12p = dot(xyScreenCoordinate - sp1, ne12);
    float E20p = dot(xyScreenCoordinate - sp2, ne20);

    bool allNonNegative = (E01p >= 0) && (E12p >= 0) && (E20p >= 0);

    bool allNonPositive = (E01p <= 0) && (E12p <= 0) && (E20p <= 0);

    return allNonNegative || allNonPositive;
}
float GetTriangleArea(float3 p0, float3 p1, float3 p2)
{
    float3 p0p1 = p1 - p0;
    float3 p0p2 = p2 - p0;
    return length(cross(p0p1, p0p2)) / 2;
}

float GetTriangleArea(float2 p0, float2 p1, float2 p2)
{

    float3 p0p1 = float3(p1, 0) - float3(p0, 0);
    float3 p0p2 = float3(p2, 0) - float3(p0, 0);
    return length(cross(p0p1, p0p2)) / 2;
}

float3 GetB0B1B2On3dSpace(float projectedTriangleArea, float2 sp0, float2 sp1, float2 sp2, float2 currentPixelCoordinate, float inv_depth0, float inv_depth1, float inv_depth2)
{

    float pp1p2TriangleArea = GetTriangleArea(currentPixelCoordinate, sp1, sp2);
    float p0pp2TriangleArea = GetTriangleArea(sp0, currentPixelCoordinate, sp2);
    float p0p1pTriangleArea = GetTriangleArea(sp0, sp1, currentPixelCoordinate);

    float b0Prime = pp1p2TriangleArea / projectedTriangleArea;
    float b1Prime = p0pp2TriangleArea / projectedTriangleArea;
    float b2Prime = p0p1pTriangleArea / projectedTriangleArea;

    float b0BarycenterNumerator = b0Prime * inv_depth0;
    float b1BarycenterNumerator = b1Prime * inv_depth1;
    float b2BarycenterNumerator = b2Prime * inv_depth2;

    float barycenterDenominator = b0BarycenterNumerator + b1BarycenterNumerator + b2BarycenterNumerator;
    float b0 = b0BarycenterNumerator / barycenterDenominator;
    float b1 = b1BarycenterNumerator / barycenterDenominator;
    float b2 = b2BarycenterNumerator / barycenterDenominator;
    return float3(b0, b1, b2);
}

[shader("compute")]
[numthreads(64, 1, 1)]
void clear_buffers(uint tid: SV_DispatchThreadID,
                   uniform uint num_pixels,
                   RWStructuredBuffer<uint> depth_buffer,
                   RWStructuredBuffer<uint> triangle_id_buffer)
{
    if (tid >= num_pixels)
        return;

    depth_buffer[tid] = 0xffffffff;
    triangle_id_buffer[tid] = 0xffffffff;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void transform_vertices(
    uint tid: SV_DispatchThreadID,
    uniform uint num_vertices,
    uniform uint vertex_offset,
    uniform float4x4 MVP,
    StructuredBuffer<float3> vertices,
    RWStructuredBuffer<float3> projected_vertices)
{
    if (tid >= num_vertices)
        return;

    uint i = vertex_offset + tid;
    float4 p = mul(MVP, float4(vertices[i], 1.0));
    projected_vertices[i] = p.xyz / p.w;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_depth(
    uint tid: SV_DispatchThreadID,
    uniform uint num_triangles,
    uniform uint width,
    uniform uint height,
    uniform float s,
    uniform float a,
    StructuredBuffer<uint3> faces, // three
    // A projected vertex store the screen space coordinates
    // in xy, and the inverse depth in z.
    StructuredBuffer<float3> projected_vertices,
    RWStructuredBuffer<uint> depth_buffer)
{
    // HW 2.5 TODO
    if (tid >= num_triangles)
    {
        return;
    }
    uint3 verticeIndexOfThisFace = faces[tid];

    float2 sp0 = float2(projected_vertices[verticeIndexOfThisFace[0]].x, projected_vertices[verticeIndexOfThisFace[0]].y);
    float2 sp1 = float2(projected_vertices[verticeIndexOfThisFace[1]].x, projected_vertices[verticeIndexOfThisFace[1]].y);
    float2 sp2 = float2(projected_vertices[verticeIndexOfThisFace[2]].x, projected_vertices[verticeIndexOfThisFace[2]].y);

    int2 aabb_min = int2(int(floor(max(0.0, min(sp0.x, min(sp1.x, sp2.x))))),
                         int(floor(max(0.0, min(sp0.y, min(sp1.y, sp2.y))))));
    int2 aabb_max = int2(int(ceil(min(float(width) - 1.0, max(sp0.x, max(sp1.x, sp2.x))))),
                         int(ceil(min(float(height) - 1.0, max(sp0.y, max(sp1.y, sp2.y))))));

    float projectedTriangleArea = GetTriangleArea(sp0, sp1, sp2);

    if (IsTwoFloatSame(0, projectedTriangleArea))
    {
        return;
    }

    float inv_depth0 = projected_vertices[verticeIndexOfThisFace[0]].z;
    float inv_depth1 = projected_vertices[verticeIndexOfThisFace[1]].z;
    float inv_depth2 = projected_vertices[verticeIndexOfThisFace[2]].z;
    for (int y = aabb_min.y; y <= aabb_max.y; y++)
    {
        for (int x = aabb_min.x; x <= aabb_max.x; x++)
        {
            float2 currentPixelCoordinate = float2(x + 0.5, y + 0.5);
            if (IsScreenCoordinateInsideTriangle(currentPixelCoordinate, float2(sp0.x, sp0.y), float2(sp1.x, sp1.y), float2(sp2.x, sp2.y)))
            {
                // calcualte barycenter and z buffer value
                float3 b0b1b2 = GetB0B1B2On3dSpace(projectedTriangleArea, sp0, sp1, sp2, currentPixelCoordinate, inv_depth0, inv_depth1, inv_depth2);

                float zDepth = (b0b1b2.x / inv_depth0 + b0b1b2.y / inv_depth1 + b0b1b2.z / inv_depth2);
                InterlockedMin(depth_buffer[y * width + x], asuint(zDepth));
            }
        }
    }
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_id(
    uint tid: SV_DispatchThreadID,
    uniform uint num_triangles,
    uniform uint width,
    uniform uint height,
    uniform float s,
    uniform float a,
    StructuredBuffer<uint3> faces,
    StructuredBuffer<float3> projected_vertices,
    RWStructuredBuffer<uint> depth_buffer,
    RWStructuredBuffer<uint> triangle_id_buffer)
{
    // HW 2.5 TODO
    if (tid >= num_triangles)
    {
        return;
    }
    uint3 verticeIndexOfThisFace = faces[tid];

    float2 sp0 = float2(projected_vertices[verticeIndexOfThisFace[0]].x, projected_vertices[verticeIndexOfThisFace[0]].y);
    float2 sp1 = float2(projected_vertices[verticeIndexOfThisFace[1]].x, projected_vertices[verticeIndexOfThisFace[1]].y);
    float2 sp2 = float2(projected_vertices[verticeIndexOfThisFace[2]].x, projected_vertices[verticeIndexOfThisFace[2]].y);

    int2 aabb_min = int2(int(floor(max(0.0, min(sp0.x, min(sp1.x, sp2.x))))),
                         int(floor(max(0.0, min(sp0.y, min(sp1.y, sp2.y))))));
    int2 aabb_max = int2(int(ceil(min(float(width) - 1.0, max(sp0.x, max(sp1.x, sp2.x))))),
                         int(ceil(min(float(height) - 1.0, max(sp0.y, max(sp1.y, sp2.y))))));

    float projectedTriangleArea = GetTriangleArea(sp0, sp1, sp2);

    if (IsTwoFloatSame(projectedTriangleArea, 0))
    {
        return;
    }

    float inv_depth0 = projected_vertices[verticeIndexOfThisFace[0]].z;
    float inv_depth1 = projected_vertices[verticeIndexOfThisFace[1]].z;
    float inv_depth2 = projected_vertices[verticeIndexOfThisFace[2]].z;
    for (int y = aabb_min.y; y <= aabb_max.y; y++)
    {
        for (int x = aabb_min.x; x <= aabb_max.x; x++)
        {
            float2 currentPixelCoordinate = float2(x + 0.5, y + 0.5);
            if (IsScreenCoordinateInsideTriangle(currentPixelCoordinate, float2(sp0.x, sp0.y), float2(sp1.x, sp1.y), float2(sp2.x, sp2.y)))
            {
                // calcualte barycenter and z buffer value

                float3 b0b1b2 = GetB0B1B2On3dSpace(projectedTriangleArea, sp0, sp1, sp2, currentPixelCoordinate, inv_depth0, inv_depth1, inv_depth2);

                float zDepth = (b0b1b2.x / inv_depth0 + b0b1b2.y / inv_depth1 + b0b1b2.z / inv_depth2);

                if (asuint(zDepth) == depth_buffer[y * width + x])
                {
                    InterlockedMin(triangle_id_buffer[y * width + x], tid);
                }
            }
        }
    }
}

[shader("compute")]
[numthreads(8, 8, 1)]
void shade(
    uint2 tid: SV_DispatchThreadID,
    uniform uint width,
    uniform uint height,
    uniform float s,
    uniform float a,
    StructuredBuffer<uint3> faces,
    StructuredBuffer<float3> vertex_colors,
    StructuredBuffer<float3> projected_vertices,
    StructuredBuffer<uint> triangle_id_buffer,
    RWTexture2D<float4> image)
{
    if (tid.x >= width || tid.y >= height)
    {
        return;
    }

    float2 xyScreenCoordinate = float2(tid.x + 0.5, tid.y + 0.5);
    uint triangleId = triangle_id_buffer[tid.y * width + tid.x];
    if (triangleId == 0xffffffff)
    {
        return;
    }

    // HW 2.5 TODO

    uint3 verticeIndexOfThisFace = faces[triangleId];

    float2 sp0 = float2(projected_vertices[verticeIndexOfThisFace[0]].x, projected_vertices[verticeIndexOfThisFace[0]].y);
    float2 sp1 = float2(projected_vertices[verticeIndexOfThisFace[1]].x, projected_vertices[verticeIndexOfThisFace[1]].y);
    float2 sp2 = float2(projected_vertices[verticeIndexOfThisFace[2]].x, projected_vertices[verticeIndexOfThisFace[2]].y);

    float inv_depth0 = projected_vertices[verticeIndexOfThisFace[0]].z;
    float inv_depth1 = projected_vertices[verticeIndexOfThisFace[1]].z;
    float inv_depth2 = projected_vertices[verticeIndexOfThisFace[2]].z;
    float projectedTriangleArea = GetTriangleArea(sp0, sp1, sp2);

    if (IsTwoFloatSame(projectedTriangleArea, 0))
    {
        return;
    }

    float3 b0b1b2 = GetB0B1B2On3dSpace(projectedTriangleArea, sp0, sp1, sp2, xyScreenCoordinate, inv_depth0, inv_depth1, inv_depth2);

    float3 vertex1color = vertex_colors[verticeIndexOfThisFace[0]];
    float3 vertex2color = vertex_colors[verticeIndexOfThisFace[1]];
    float3 vertex3color = vertex_colors[verticeIndexOfThisFace[2]];

    float3 interpolatedColor = vertex1color * b0b1b2.x + vertex2color * b0b1b2.y + vertex3color * b0b1b2.z;
    image[tid] = float4(interpolatedColor, 1);
}
