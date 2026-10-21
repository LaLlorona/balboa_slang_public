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

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);
    float2 pixel_center = float2(tid.x + 0.5, (height - 1 - tid.y) + 0.5);
    if (use_fill_color && point_in_polyline_fill(
            polyline, 0, num_polyline, pixel_center)) {
        image[tid] = float4(fill_color, 1.0);
    }
    if (use_stroke_color && point_in_polyline_stroke(
            polyline, 0, num_polyline, pixel_center, stroke_width, is_closed)) {
        image[tid] = float4(stroke_color, 1.0);
    }
}
