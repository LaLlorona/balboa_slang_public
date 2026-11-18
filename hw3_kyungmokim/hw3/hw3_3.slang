import hw3_common;

bool IsSphereCollidingWithARay(Sphere sphere, float3 from, float3 rayDirection, float tMax, out float t)
{
    float3 sphereCenter = sphere.center;
    float radius = sphere.radius;
    float3 OMinusXc = from - sphereCenter;
    float3 dNormalized = normalize(rayDirection);

    float a = dot(dNormalized, dNormalized);
    float b = 2 * dot(dNormalized, OMinusXc);
    float c = dot(OMinusXc, OMinusXc) - radius * radius;

    float2 quadraticSolution;
    float potentialTValue = float.maxValue;

    if (solve_quadratic(a, b, c, quadraticSolution))
    {
        if (quadraticSolution.x > EPSILON && quadraticSolution.x <= tMax)
        {
            potentialTValue = min(potentialTValue, quadraticSolution.x);
        }
        if (quadraticSolution.y > EPSILON && quadraticSolution.y <= tMax)
        {
            potentialTValue = min(potentialTValue, quadraticSolution.y);
        }
        if (potentialTValue != float.maxValue)
        {
            t = potentialTValue;
            return true;
        }
    }
    t = -1;
    return false;
}
bool TryFindRayHitPoint(float3 rayStartPoint,
                        float3 normalizedRayDirection,
                        int num_shapes,
                        StructuredBuffer<Shape> shapes,
                        StructuredBuffer<Sphere> spheres,
                        out float t,
                        out int toDrawShapeIndex)
{
    float tCandidiate = float.maxValue;
    int shapeToDrawIndex = -1;
    for (int i = 0; i < num_shapes; i++)
    {
        // check whether ray hits the sphere
        Sphere sphere = spheres[shapes[i].index];
        float3 sphereCenter = sphere.center;
        float radius = sphere.radius;
        float3 OMinusXc = rayStartPoint - sphereCenter;

        float tValue;

        if (IsSphereCollidingWithARay(sphere, rayStartPoint, normalizedRayDirection, float.maxValue, tValue))
        {
            if (tValue < tCandidiate)
            {
                shapeToDrawIndex = i;
                tCandidiate = tValue;
            }
        }
    }
    if (shapeToDrawIndex != -1)
    {
        t = tCandidiate;
        toDrawShapeIndex = shapeToDrawIndex;
        return true;
    }
    t = float.maxValue;
    toDrawShapeIndex = -1;
    return false;
}

float3 CalculateContributionOfSingleRay(
    float3 rayHitPoint,
    float3 normalizedSurfaceNormal,
    Shape shapeToDraw,
    int num_lights,
    StructuredBuffer<PointLight> lights,
    int num_shapes,
    StructuredBuffer<Sphere> spheres,
    StructuredBuffer<Shape> shapes)
{
    float3 color = 0;
    for (int i = 0; i < num_lights; i++)
    {
        PointLight pointLight = lights[i];
        float3 toLights = normalize(pointLight.position - rayHitPoint);
        float distanceBetweenPointandLight = distance(rayHitPoint, pointLight.position);
        float3 colorByLight;
        colorByLight = shapeToDraw.Kd * pointLight.intensity * max(0, dot(normalizedSurfaceNormal, toLights)) / (distanceBetweenPointandLight * distanceBetweenPointandLight);

        // shadow check
        for (int j = 0; j < num_shapes; j++)
        {

            Sphere otherSphere = spheres[shapes[j].index];
            float t;
            if (IsSphereCollidingWithARay(otherSphere, rayHitPoint, toLights, distanceBetweenPointandLight, t))
            {
                colorByLight = float3(0, 0, 0);
                break;
            }
        }
        color += colorByLight;
    }
    return color;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid: SV_DispatchThreadID,
                  uniform float3 background,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Sphere> spheres,
                  StructuredBuffer<PointLight> lights,
                  uniform int num_lights,
                  uniform int max_depth,
                  RWTexture2D<float4> image)
{
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height)
    {
        return;
    }

    float2 xyScreenCoordinate = float2(tid.x + 0.5, (height - 1 - tid.y) + 0.5);
    float aspectRatio = (float)width / (float)height;
    float cameraSpaceCoordinateX = -aspectRatio + xyScreenCoordinate.x / width * aspectRatio * 2;
    float cameraSpaceCorodinateY = -1 + xyScreenCoordinate.y / height * 2;

    float3 cameraPosition = float3(0, 0, 0);
    float3 cameraSpaceCoordinate = float3(cameraSpaceCoordinateX, cameraSpaceCorodinateY, -1);

    float3 normalizedCameraPositionToPixelDirection = normalize(cameraSpaceCoordinate);

    image[tid] = float4(background, 1.0);

    float tCandidiate = float.maxValue;
    int shapeToDrawIndex = -1;

    float3 color = 0;
    float3 throughput = 1.0;
    float3 rayOrigin = cameraPosition;
    float3 rayDirection = normalizedCameraPositionToPixelDirection;
    for (int j = 0; j < max_depth; j++)
    {
        tCandidiate = float.maxValue;
        shapeToDrawIndex = -1;
        bool rayHitResult = TryFindRayHitPoint(rayOrigin, rayDirection, num_shapes, shapes, spheres, tCandidiate, shapeToDrawIndex);
        if (rayHitResult)
        {
            Shape shapeToDraw = shapes[shapeToDrawIndex];
            Sphere sphereToDraw = spheres[shapes[shapeToDrawIndex].index];
            float3 raySphereIntersectionCoordinate = rayOrigin + rayDirection * tCandidiate;
            float3 sphereCenter = sphereToDraw.center;
            float3 normalizedSurfaceNormal = normalize(raySphereIntersectionCoordinate - sphereCenter);
            color +=
                throughput *
                CalculateContributionOfSingleRay(raySphereIntersectionCoordinate, normalizedSurfaceNormal, shapeToDraw, num_lights, lights, num_shapes, spheres, shapes);

            if ((shapeToDraw.Kr.x > 0 || shapeToDraw.Kr.y > 0 || shapeToDraw.Kr.z > 0) == false)
            {
                break;
            }
            rayOrigin = raySphereIntersectionCoordinate;
            rayDirection = reflect(rayDirection, normalizedSurfaceNormal);
            throughput *= shapeToDraw.Kr;
        }
        else
        {
            color += background * throughput;
            break;
        }
    }
    image[tid] = float4(color, 1);
}
