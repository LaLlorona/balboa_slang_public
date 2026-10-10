import hw1_common;


bool IsInsideCircle(RWTexture2D<float4> image, uint2 tid, Circle circle, bool useFill) {
    if (useFill == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    float xCoordinate = tid.x + 0.5;
    float yCoordinate =  height - (tid.y + 0.5);
    float2 pixelCoordinate = float2(xCoordinate, yCoordinate);
    if (distance(circle.center, pixelCoordinate) <= circle.radius)  {
        return true;
    }
    else {
        return false;
    }
}
bool IsInsideCircleStroke(RWTexture2D<float4> image, uint2 tid, Circle circle, bool useStroke, float strokeWidth) {
    if (useStroke == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    float xCoordinate = tid.x + 0.5;
    float yCoordinate =  height - (tid.y + 0.5);
    float2 pixelCoordinate = float2(xCoordinate, yCoordinate);
    float distanceFromCircleCenter = distance(circle.center, pixelCoordinate);
    if (distanceFromCircleCenter > circle.radius - circle.radius / 2 && distanceFromCircleCenter <= strokeWidth + circle.radius / 2) {
        return true;
    }
    return false;
}

bool IsInsidePolyline(RWTexture2D<float4> image, uint2 tid, StructuredBuffer<float2> polylineCoordinates, bool useFill, bool isClosed) {
    if (useFill == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    float xCoordinate = tid.x + 0.5;
    float yCoordinate = height - (tid.y + 0.5);
    float2 q = float2(xCoordinate, yCoordinate);
    int endIndex = isClosed ? polylineCoordinates.getCount() : polylineCoordinates.getCount() - 1;
    int count = 0;
    for (int i = 0; i < endIndex; i++) {
        float2 firstPoint = polylineCoordinates[i];
        float2 secondPoint = polylineCoordinates[(i+1) % polylineCoordinates.getCount()];
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
        return true;
    }
    return false;
}

bool IsInsidePolylineStroke(RWTexture2D<float4> image, uint2 tid, StructuredBuffer<float2> polylineCoordinates, bool useStroke, bool isClosed, float strokeWidth) {
    if (useStroke == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    float xCoordinate = tid.x + 0.5;
    float yCoordinate = height - (tid.y + 0.5);
    float2 q = float2(xCoordinate, yCoordinate);
    int endIndex = isClosed ? polylineCoordinates.getCount() : polylineCoordinates.getCount() - 1;
    for (int i = 0; i < endIndex; i++) {
        float2 p0 = polylineCoordinates[i];
        float2 p1 = polylineCoordinates[(i+1) % polylineCoordinates.getCount()];
        float2 p1MinusP0 = p1 - p0;
        float2 qMinusP0 = q - p0;
        float distanceFromP0ToP1 = distance(p0, p1);
        float distanceFromP0ToProjectionOfQ = dot(p1MinusP0, qMinusP0) / distanceFromP0ToP1;
        float2 projectionOfQOnP0P1 = p0 + distanceFromP0ToProjectionOfQ * (p1 - p0) / distanceFromP0ToP1;

        bool isPointInsideStorkeWidth = distanceFromP0ToProjectionOfQ > 0
            && distanceFromP0ToProjectionOfQ < distanceFromP0ToP1
            && distance(q, projectionOfQOnP0P1) < strokeWidth / 2;

        bool isPointInsideRoundJoin = (isClosed ||i >= 1) && distance(p0, q) <=strokeWidth / 2;
        if (isPointInsideStorkeWidth ||isPointInsideRoundJoin) {
            return true;
        }
    }
    return false;
}
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
    image[tid] = float4(background, 1);
    for (int i = 0; i < shapes.getCount(); i++) {
        Shape currentShape = shapes[i];
        switch (currentShape.type) {
            case ShapeType.Circle :
                Circle circle = circles[currentShape.index];
                if (IsInsideCircle(image,tid, circle, currentShape.use_fill)) {
                    image[tid] = currentShape.fill_rgba;
                }
                if (IsInsideCircleStroke(image, tid, circle, currentShape.use_stroke, currentShape.stroke_width)) {
                    image[tid] = currentShape.stroke_rgba;
                }
                break;
            case ShapeType.Polyline:
                break;
        }
    }
}
