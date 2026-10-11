import hw1_common;


bool IsInsideCircle(RWTexture2D<float4> image, float2 canvasCoordinate, Circle circle, bool useFill) {
    if (useFill == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    if (distance(circle.center, canvasCoordinate) <= circle.radius)  {
        return true;
    }
    else {
        return false;
    }
}
bool IsInsideCircleStroke(RWTexture2D<float4> image, float2 canvasCoordinate, Circle circle, bool useStroke, float strokeWidth) {
    if (useStroke == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    float distanceFromCircleCenter = distance(circle.center, canvasCoordinate);
    if (distanceFromCircleCenter > circle.radius - strokeWidth / 2 && distanceFromCircleCenter <= circle.radius + strokeWidth / 2) {
        return true;
    }
    return false;
}

bool IsInsidePolyline(
    RWTexture2D<float4> image,
    float2 canvasCoordinate,
    StructuredBuffer<float2> polylineCoordinates,
    int startIndexInclusive,
    int endIndexExclusive, 
    bool useFill,
    bool isClosed) {
    if (useFill == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    int startIndex = startIndexInclusive;
    int endIndex = isClosed ? endIndexExclusive - 1 : endIndexExclusive - 2;
    float2 q = canvasCoordinate;
    int count = 0;
    for (int i = startIndex; i <= endIndex; i++) {
        float2 firstPoint = polylineCoordinates[i];
        float2 secondPoint = polylineCoordinates[i==endIndexExclusive - 1 ? startIndex : (i+1)];
        float smallerY = min(firstPoint.y, secondPoint.y);
        float largerY = max(firstPoint.y, secondPoint.y);
        if (q.y > smallerY && q.y <=largerY) {
            float t = (q.y - firstPoint.y) / (secondPoint.y - firstPoint.y); 
            float xIntersection = firstPoint.x + t * (secondPoint.x - firstPoint.x);
            if (xIntersection > q.x) {
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

bool IsInsidePolylineStroke(
    RWTexture2D<float4> image,
    float2 canvasCoordinate, StructuredBuffer<float2> polylineCoordinates,
    int startIndexInclusive,
    int endIndexExclusive, 
    bool useStroke,
    bool isClosed,
    float strokeWidth) {
    if (useStroke == false) {
        return false;
    }
    uint width, height;
    image.GetDimensions(width, height);
    int startIndex = startIndexInclusive;
    int endIndex = isClosed ? endIndexExclusive - 1 : endIndexExclusive - 2;
    float2 q = canvasCoordinate;
    for (int i = startIndex; i <= endIndex; i++) {
        float2 p0 = polylineCoordinates[i];
        float2 p1 = polylineCoordinates[i==endIndexExclusive - 1 ? startIndex : (i+1)];
        float2 p1MinusP0 = p1 - p0;
        float2 qMinusP0 = q - p0;
        float distanceFromP0ToP1 = distance(p0, p1);
        float distanceFromP0ToProjectionOfQ = dot(p1MinusP0, qMinusP0) / distanceFromP0ToP1;
        float2 projectionOfQOnP0P1 = p0 + distanceFromP0ToProjectionOfQ * (p1 - p0) / distanceFromP0ToP1;

        bool isPointInsideStorkeWidth = distanceFromP0ToProjectionOfQ > 0
            && distanceFromP0ToProjectionOfQ < distanceFromP0ToP1
            && distance(q, projectionOfQOnP0P1) < strokeWidth / 2;

        bool isPointInsideRoundJoin = (isClosed || i >= startIndex + 1) && distance(p0, q) <=strokeWidth / 2;
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
    for (int i = shapes.getCount() - 1; i >=0 ; i--) {
        Shape currentShape = shapes[i];
        float xCoordinate = tid.x + 0.5;
        float yCoordinate = height - (tid.y + 0.5);
        float3 canvasCoordinate = float3(xCoordinate, yCoordinate, 1);
        float3 objectCoordinate = mul(currentShape.world_to_obj, canvasCoordinate);
        float2 objectCoordinateFloat2 =
        float2(objectCoordinate.x, objectCoordinate.y);
        switch (currentShape.type) {

            case ShapeType.Circle :
                Circle circle = circles[currentShape.index];
                if (IsInsideCircle(image,objectCoordinateFloat2, circle, currentShape.use_fill)) {
                    image[tid] = currentShape.fill_rgba;
                }
                if (IsInsideCircleStroke(image, objectCoordinateFloat2, circle, currentShape.use_stroke, currentShape.stroke_width)) {
                    image[tid] = currentShape.stroke_rgba;
                }
                break;
            case ShapeType.Polyline:
                Polyline polyline = polylines[currentShape.index];
                if (IsInsidePolyline(image,objectCoordinateFloat2, points, polyline.pts_begin, polyline.pts_end, currentShape.use_fill, polyline.closed)) {
                    image[tid] = currentShape.fill_rgba;
                }
                if (IsInsidePolylineStroke(image,objectCoordinateFloat2, points, polyline.pts_begin, polyline.pts_end, currentShape.use_stroke, polyline.closed, currentShape.stroke_width)) {
                    image[tid] = currentShape.stroke_rgba;
                }
                break;
        }
    }
}
