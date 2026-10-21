import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int /*samples_per_axis*/, // ignore for now
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }
    image[tid] = float4(background, 1.0);
    float2 pixel_center = float2(tid.x + 0.5, (height - 1 - tid.y) + 0.5);
    // Front-to-back order
    for (int i = 0; i < num_shapes; i++) {
        Shape shape = shapes[i];
        float3 p_ = float3(pixel_center.x, pixel_center.y, 1.0);
        float2 p = mul(shape.world_to_obj, p_).xy;

        bool hit_fill = false;
        bool hit_stroke = false;
        if (shape.type == ShapeType::Circle) {
            Circle circle = circles[shape.index];
            float dist = length(p - circle.center);
            if (shape.use_fill && dist < circle.radius) {
                hit_fill = true;
            }
            if (shape.use_stroke &&
                    fabs(dist - circle.radius) < shape.stroke_width / 2) {
                hit_stroke = true;
            }
        } else if (shape.type == ShapeType::Polyline) {
            Polyline polyline = polylines[shape.index];
            if (shape.use_fill &&
                    point_in_polyline_fill(points,
                                           polyline.pts_begin,
                                           polyline.pts_end,
                                           p)) {
                hit_fill = true;
            }
            if (shape.use_stroke &&
                    point_in_polyline_stroke(points,
                                             polyline.pts_begin,
                                             polyline.pts_end,
                                             p,
                                             shape.stroke_width,
                                             polyline.closed)) {
                hit_stroke = true;
            }
        }
        if (hit_stroke) {
            image[tid] = shape.stroke_rgba;
            break;
        } else if (hit_fill) {
            image[tid] = shape.fill_rgba;
            break;
        }
    }
}
