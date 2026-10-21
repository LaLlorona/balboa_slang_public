[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 center,
                  uniform float radius,
                  uniform float3 color,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    float2 pixel_center = float2(tid.x + 0.5, (height - 1 - tid.y) + 0.5);
    float2 diff = center - pixel_center;
    if (dot(diff, diff) < radius * radius) {
        image[tid] = float4(color, 1.0);
    } else {
        image[tid] = float4(float3(0.5), 1.0);
    }
}
