import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  StructuredBuffer<float2> polyline,
                  uniform int num_polyline,
                  uniform bool is_closed,
                  uniform bool use_fill_color,
                  uniform float3 fill_color,
                  uniform bool use_stroke_color,
                  uniform float3 stroke_color,
                  uniform float stroke_width,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(1.0);
    // TODO: your code here
    image[tid] = float4(0.5);
    float xCoordinate = tid.x + 0.5;
    float yCoordinate = height - (tid.y + 0.5);

    if (is_closed) {
        //chekc whether given coordinate is inside polyline
    }
    if (use_fill_color) {
        //chekc whether given coordinate is inside polyline
        int count = 0;
        for (int i = 0; i < polyline.getCount(); i++) {
            float2 firstPoint = polyline[i];
            float2 secondPoint = polyline[(i+1) % polyline.getCount()];
            float smallerY = min(firstPoint.y, secondPoint.y);
            float largerY = max(firstPoint.y, secondPoint.y);
            if (yCoordinate > smallerY && yCoordinate <=largerY) {
                float t = (yCoordinate - firstPoint.y) / (secondPoint.y - firstPoint.y); 
                float xIntersection = firstPoint.x + t * (secondPoint.x - firstPoint.x);
                if (xIntersection > xCoordinate) {
                    if (firstPoint.y < secondPoint.y) {
                        count++;
                    }
                    else {
                        count--;
                    }
                }
            }
        }
        if (count != 0) {
            image[tid] = float4(fill_color, 1.0);
        }
    }
    if (use_stroke_color) {
    }
}
