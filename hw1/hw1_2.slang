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
    float2 q = float2(xCoordinate, yCoordinate);
    if (use_fill_color) {
        //chekc whether given coordinate is inside polyline
        int endIndex = is_closed ? polyline.getCount() : polyline.getCount() - 1;
        int count = 0;
        for (int i = 0; i < endIndex; i++) {
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
        int endIndex = is_closed ? polyline.getCount() : polyline.getCount() - 1;
         for (int i = 0; i < endIndex; i++) {
            float2 p0 = polyline[i];
            float2 p1 = polyline[(i+1) % polyline.getCount()];
            float2 p1MinusP0 = p1 - p0;
            float2 qMinusP0 = q - p0;
            float distanceFromP0ToP1 = distance(p0, p1);
            float distanceFromP0ToProjectionOfQ = dot(p1MinusP0, qMinusP0) / distanceFromP0ToP1;
            float2 projectionOfQOnP0P1 = p0 + distanceFromP0ToProjectionOfQ * (p1 - p0) / distanceFromP0ToP1;

            bool isPointInsideStorkeWidth = distanceFromP0ToProjectionOfQ > 0
                && distanceFromP0ToProjectionOfQ < distanceFromP0ToP1
                && distance(q, projectionOfQOnP0P1) < stroke_width / 2;

            bool isPointInsideRoundJoin = (is_closed ||i >= 1) && distance(p0, q) <=stroke_width / 2;

            if (isPointInsideStorkeWidth || isPointInsideRoundJoin) {
                image[tid] = float4(stroke_color, 1.0);
            }
        }
        
    }
}
