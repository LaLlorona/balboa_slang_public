

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid: SV_DispatchThreadID,
                  uniform float2 sp0,
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform int2 aabb_min,
                  uniform float3 color,
                  RWTexture2D<float4> image)
{
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height)
    {
        return;
    }

    // TODO: HW 2.1e

    float2 xyScreenCoordinate = float2(ipixel.x + 0.5, ipixel.y + 0.5);

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

    if (allNonNegative || allNonPositive)
    {
        image[ipixel] = float4(color, 1);
    }
}
