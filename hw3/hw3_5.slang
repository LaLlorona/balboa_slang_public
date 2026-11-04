import hw3_common;
bool IsSphereCollidingWithARay(Sphere sphere, float3 from, float3 rayDirection, float tMax, out float t)
{
    float3 sphereCenter = sphere.center;
    float radius = sphere.radius;
    float3 OMinusXc = from - sphereCenter;

    float a = dot(rayDirection, rayDirection);
    float b = 2 * dot(rayDirection, OMinusXc);
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
                        StructuredBuffer<TriangleMesh> triangleMesh,
                        StructuredBuffer<uint3> triangles,
                        StructuredBuffer<float3> vertices,
                        StructuredBuffer<float3> vertex_normals,
                        out float t,
                        out int toDrawShapeIndex,
                        out float3 getWorldNormalDirectionOfRayHitPoint)
{
    float tCandidiate = float.maxValue;
    int shapeToDrawIndex = -1;
    for (int i = 0; i < num_shapes; i++)
    {
        // check whether ray hits the sphere
        Shape currentShape = shapes[i];
        float3 rayOriginAtObjectSpace = xform_pt(currentShape.world_to_obj, rayStartPoint);
        float3 rayDirectionAtObjectSpace = xform_vec(currentShape.world_to_obj, normalizedRayDirection);
        if (currentShape.type == ShapeType.Sphere)
        {
            Sphere sphere = spheres[shapes[i].index];
            float3 sphereCenter = sphere.center;
            float radius = sphere.radius;
            float3 OMinusXc = rayStartPoint - sphereCenter;
            float tValue;

            if (IsSphereCollidingWithARay(sphere, rayOriginAtObjectSpace, rayDirectionAtObjectSpace, float.maxValue, tValue))
            {
                if (tValue < tCandidiate)
                {
                    shapeToDrawIndex = i;
                    tCandidiate = tValue;
                }
            }
        }
        else if (currentShape.type == ShapeType.TriangleMesh)
        {
            TriangleMesh currentTriangleMesh = triangleMesh[currentShape.index];
            for (int j = currentTriangleMesh.triangle_begin; j < currentTriangleMesh.triangle_end; j++)
            {
                uint3 triangleIndices = triangles[j] + currentTriangleMesh.vertex_offset;
                float3 vertexPos1 = vertices[triangleIndices[0]];
                float3 vertexPos2 = vertices[triangleIndices[1]];
                float3 vertexPos3 = vertices[triangleIndices[2]];

                float3 vertexNormal1 = vertex_normals[triangleIndices[0]];
                float3 vertexNormal2 = vertex_normals[triangleIndices[1]];
                float3 vertexNormal3 = vertex_normals[triangleIndices[2]];
                float tValue;
                float3 b;
                if (intersect_tri(vertexPos1, vertexPos2, vertexPos3, rayOriginAtObjectSpace, rayDirectionAtObjectSpace, EPSILON, float.maxValue, b, tValue))
                {
                    if (tValue < tCandidiate)
                    {

                        shapeToDrawIndex = i;
                        tCandidiate = tValue;
                    }
                }
            }
        }
    }

    // start from here: 11042026
    if (shapeToDrawIndex != -1)
    {
        t = tCandidiate;
        toDrawShapeIndex = shapeToDrawIndex;

        Shape closestShape = shapes[toDrawShapeIndex];
        float3 rayOriginAtObjectSpace = xform_pt(closestShape.world_to_obj, rayStartPoint);
        float3 rayDirectionAtObjectSpace = xform_vec(closestShape.world_to_obj, normalizedRayDirection);
        float3 rayHitPointAtObjectSpace = t * rayDirectionAtObjectSpace + rayOriginAtObjectSpace;
        float3 normalDirectionAtObjectSpace = rayHitPointAtObjectSpace - spheres[closestShape.index].center;
        float3 normalDirectionAtWorldSpace = normalize(xform_vec(transpose(closestShape.world_to_obj), normalDirectionAtObjectSpace));

        getWorldNormalDirectionOfRayHitPoint = normalDirectionAtWorldSpace;
        return true;
    }
    t = float.maxValue;
    toDrawShapeIndex = -1;
    getWorldNormalDirectionOfRayHitPoint = float3(0);
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

            Shape otherShape = shapes[j];
            Sphere otherSphere = spheres[shapes[j].index];

            float3 rayHitPointFromObjectSpaceOfOtherShape = xform_pt(otherShape.world_to_obj, rayHitPoint);
            float3 rayDirectionFromObjectSapceOfOtherShape = xform_vec(otherShape.world_to_obj, toLights);

            float t;
            if (IsSphereCollidingWithARay(otherSphere, rayHitPointFromObjectSpaceOfOtherShape, rayDirectionFromObjectSapceOfOtherShape, distanceBetweenPointandLight, t))
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
                  uniform Camera camera,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Sphere> spheres,
                  StructuredBuffer<TriangleMesh> meshes,
                  StructuredBuffer<float3> vertices,
                  StructuredBuffer<float3> vertex_normals,
                  StructuredBuffer<uint3> triangles,
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

    // we should map cameraSpaceCoordinateX [-tan(f/2.0), tan(f/2.0)]
    // we should map cameraSpaceCoordinateY [[-tan(f/2.0) / a, tan(f/2.0) / a]]
    float tanFdividedby2 = tan(radians(camera.fov_x) / 2.0);
    float cameraSpaceCoordinateX = -tanFdividedby2 + xyScreenCoordinate.x / width * tanFdividedby2 * 2;
    float cameraSpaceCorodinateY = (-tanFdividedby2 + xyScreenCoordinate.y / height * tanFdividedby2 * 2) / aspectRatio;

    float3 cameraPosition = float3(0, 0, 0);
    float3 cameraSpaceCoordinate = float3(cameraSpaceCoordinateX, cameraSpaceCorodinateY, -1);
    float3 normalizedCameraPositionToPixelDirection = normalize(cameraSpaceCoordinate);

    float3 worldCoordinateCameraPosition = xform_pt(camera.cam_to_world, cameraPosition);
    float3 worldCoordinateNormalizedCameraForwardDirection = normalize(xform_vec(camera.cam_to_world, normalizedCameraPositionToPixelDirection));

    float tCandidiate = float.maxValue;
    int shapeToDrawIndex = -1;

    float3 color = 0;
    float3 throughput = 1.0;
    float3 rayOrigin = worldCoordinateCameraPosition;
    float3 rayDirection = worldCoordinateNormalizedCameraForwardDirection;
    for (int j = 0; j < max_depth; j++)
    {
        tCandidiate = float.maxValue;
        shapeToDrawIndex = -1;
        float3 worldNormalDirectionOfHitPoint = float3(0);
        bool rayHitResult = TryFindRayHitPoint(rayOrigin, rayDirection, num_shapes, shapes, spheres, tCandidiate, shapeToDrawIndex, worldNormalDirectionOfHitPoint);
        if (rayHitResult)
        {
            Shape shapeToDraw = shapes[shapeToDrawIndex];
            Sphere sphereToDraw = spheres[shapes[shapeToDrawIndex].index];
            float3 raySphereIntersectionCoordinate = rayOrigin + rayDirection * tCandidiate;
            float3 sphereCenter = sphereToDraw.center;

            // we have to calculate normal
            color +=
                throughput *
                CalculateContributionOfSingleRay(raySphereIntersectionCoordinate, worldNormalDirectionOfHitPoint, shapeToDraw, num_lights, lights, num_shapes, spheres, shapes);

            if ((shapeToDraw.Kr.x > 0 || shapeToDraw.Kr.y > 0 || shapeToDraw.Kr.z > 0) == false)
            {
                break;
            }
            rayOrigin = raySphereIntersectionCoordinate;
            rayDirection = reflect(rayDirection, worldNormalDirectionOfHitPoint);
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
