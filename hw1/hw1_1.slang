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

    image[tid] = float4(1.0);


    // TODO: your code here
    float xCoordinate = tid.x + 0.5;
    float yCoordinate = height - (tid.y + 0.5);
    if (( (xCoordinate - center.x) * (xCoordinate - center.x) + (yCoordinate - center.y) * (yCoordinate - center.y) ) <= radius * radius) {
        image[tid] = float4(color, 1.0);
    }
    else {
        image[tid] = float4(0.5);
    }
    
    
}
