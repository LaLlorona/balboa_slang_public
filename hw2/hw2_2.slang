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

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid: SV_DispatchThreadID,
                  uniform float2 sp0, // vertex at screen space
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform float inv_depth0, // inverse depth in camera space
                  uniform float inv_depth1,
                  uniform float inv_depth2,
                  uniform int2 aabb_min,
                  uniform float3 c0, // vertex color
                  uniform float3 c1,
                  uniform float3 c2,
                  uniform float s,
                  uniform float a,
                  RWTexture2D<float4> color_image,
                  RWTexture2D<float> depth_image)
{
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    color_image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height)
    {
        return;
    }

    // TODO: HW 2.1

    float2 xyScreenCoordinate = float2(ipixel.x + 0.5, ipixel.y + 0.5);
    if (IsScreenCoordinateInsideTriangle(xyScreenCoordinate, sp0, sp1, sp2) == false)
    {
        return;
    }
    float projectedTriangleArea = GetTriangleArea(sp0, sp1, sp2);
    float pp1p2TriangleArea = GetTriangleArea(xyScreenCoordinate, sp1, sp2);
    float p0pp2TriangleArea = GetTriangleArea(sp0, xyScreenCoordinate, sp2);
    float p0p1pTriangleArea = GetTriangleArea(sp0, sp1, xyScreenCoordinate);

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

    float zDepth = (b0 / inv_depth0 + b1 / inv_depth1 + b2 / inv_depth2);
    float3 interpolatedColor = b0 * c0 + b1 * c1 + b2 * c2;

    if (zDepth < depth_image[ipixel])
    {
        depth_image[ipixel] = zDepth;
        color_image[ipixel] = float4(interpolatedColor, 1);
    }
}
