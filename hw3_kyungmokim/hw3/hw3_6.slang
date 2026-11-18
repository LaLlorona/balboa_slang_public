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

bool IsMeshCollidingWithARay(Shape currentShape,
                             int shapeIndex,
                             float tMax,
                             float3 rayOriginAtObjectSpace,
                             float3 rayDirectionAtObjectSpace,
                             StructuredBuffer<TriangleMesh> triangleMesh,
                             StructuredBuffer<uint3> triangles,
                             StructuredBuffer<float3> vertices,
                             StructuredBuffer<float3> vertex_normals,
                             StructuredBuffer<BVHNode> bvh_nodes,
                             out HitInformation outPuthitInformation)
{
    TriangleMesh currentTriangleMesh = triangleMesh[currentShape.index];
    float tCandidiate = float.maxValue;
    HitInformation hitInformation = HitInformation(0, 0, float3(0));
    float3 vertexNormal1OfClosestPoint = 0;
    float3 vertexNormal2OfClosestPoint = 0;
    float3 vertexNormal3OfClosestPoint = 0;
    float3 bOfClosestPoint;

    int bvhTraversalPointer = currentTriangleMesh.bvh_root_index;
    int bvhTraversalEndPointer = bvh_nodes[currentTriangleMesh.bvh_root_index].next_index;

    while (bvhTraversalPointer < bvhTraversalEndPointer)
    {
        BVHNode currentNode = bvh_nodes[bvhTraversalPointer];
        if (intersect_aabb(currentNode.bbox_min, currentNode.bbox_max, rayOriginAtObjectSpace, rayDirectionAtObjectSpace, EPSILON, float.maxValue))
        {
            // visit node
            if (currentNode.is_leaf)
            {
                for (int j = currentNode.triangle_begin; j < currentNode.triangle_end; j++)
                {
                    uint3 triangleIndices = triangles[j] + currentTriangleMesh.vertex_offset;
                    float3 vertexPos1 = vertices[triangleIndices[0]];
                    float3 vertexPos2 = vertices[triangleIndices[1]];
                    float3 vertexPos3 = vertices[triangleIndices[2]];

                    float tValue;
                    float3 b;

                    if (intersect_tri(vertexPos1, vertexPos2, vertexPos3, rayOriginAtObjectSpace, rayDirectionAtObjectSpace, EPSILON, tMax, b, tValue))
                    {
                        if (tValue < tCandidiate)
                        {
                            vertexNormal1OfClosestPoint = vertex_normals[triangleIndices[0]];
                            vertexNormal2OfClosestPoint = vertex_normals[triangleIndices[1]];
                            vertexNormal3OfClosestPoint = vertex_normals[triangleIndices[2]];
                            bOfClosestPoint = b;
                            tCandidiate = tValue;
                        }
                    }
                }
                bvhTraversalPointer = currentNode.next_index;
            }
            else
            {
                bvhTraversalPointer += 1;
            }
        }
        else
        {
            // ray does not hit the aabb box
            bvhTraversalPointer = currentNode.next_index;
        }
    }

    if (tCandidiate != float.maxValue)
    {
        float3 rayHitPointAtObjectSpace = tCandidiate * rayDirectionAtObjectSpace + rayOriginAtObjectSpace;
        float3 normalDirectionAtObjectSpace =
            vertexNormal1OfClosestPoint * bOfClosestPoint[0] +
            vertexNormal2OfClosestPoint * bOfClosestPoint[1] +
            vertexNormal3OfClosestPoint * bOfClosestPoint[2];
        float3 normalDirectionAtWorldSpace = normalize(xform_vec(transpose(currentShape.world_to_obj), normalDirectionAtObjectSpace));
        hitInformation = HitInformation(tCandidiate, shapeIndex, normalDirectionAtWorldSpace);
        outPuthitInformation = hitInformation;
        return true;
    }
    outPuthitInformation = hitInformation;
    return false;
}

struct HitInformation
{
    float t;
    int shapeIndex;
    float3 worldCoordinateNormalOfRayHit;
}
bool TryFindRayHitPoint(float3 rayStartPoint,
                        float3 normalizedRayDirection,
                        int num_shapes,
                        StructuredBuffer<BVHNode> bvh_nodes,
                        StructuredBuffer<Shape> shapes,
                        StructuredBuffer<Sphere> spheres,
                        StructuredBuffer<TriangleMesh> triangleMesh,
                        StructuredBuffer<uint3> triangles,
                        StructuredBuffer<float3> vertices,
                        StructuredBuffer<float3> vertex_normals,
                        out HitInformation outPuthitInformation)
{
    float tCandidiate = float.maxValue;
    HitInformation hitInformation;
    for (int i = 0; i < num_shapes; i++)
    {
        // check whether ray hits the sphere
        Shape currentShape = shapes[i];
        float3 rayOriginAtObjectSpace = xform_pt(currentShape.world_to_obj, rayStartPoint);
        float3 rayDirectionAtObjectSpace = xform_vec(currentShape.world_to_obj, normalizedRayDirection);
        if (currentShape.type == ShapeType.Sphere)
        {
            Sphere sphere = spheres[shapes[i].index];
            float tValue;

            if (IsSphereCollidingWithARay(sphere, rayOriginAtObjectSpace, rayDirectionAtObjectSpace, float.maxValue, tValue))
            {
                if (tValue < tCandidiate)
                {
                    float3 rayHitPointAtObjectSpace = tValue * rayDirectionAtObjectSpace + rayOriginAtObjectSpace;
                    float3 normalDirectionAtObjectSpace = rayHitPointAtObjectSpace - sphere.center;
                    float3 normalDirectionAtWorldSpace = normalize(xform_vec(transpose(currentShape.world_to_obj), normalDirectionAtObjectSpace));
                    hitInformation = HitInformation(tValue, i, normalDirectionAtWorldSpace);
                    tCandidiate = tValue;
                }
            }
        }
        else if (currentShape.type == ShapeType.TriangleMesh)
        {
            HitInformation temporaryHitInformationForMesh;
            if (IsMeshCollidingWithARay(currentShape,
                                        i,
                                        float.maxValue,
                                        rayOriginAtObjectSpace,
                                        rayDirectionAtObjectSpace,
                                        triangleMesh,
                                        triangles,
                                        vertices,
                                        vertex_normals,
                                        bvh_nodes,
                                        temporaryHitInformationForMesh))
            {
                if (temporaryHitInformationForMesh.t < tCandidiate)
                {
                    hitInformation = temporaryHitInformationForMesh;
                    tCandidiate = temporaryHitInformationForMesh.t;
                }
            }
        }
    }
    if (tCandidiate != float.maxValue)
    {
        outPuthitInformation = hitInformation;
        return true;
    }
    outPuthitInformation = hitInformation;
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
    StructuredBuffer<TriangleMesh> triangleMesh,
    StructuredBuffer<uint3> triangles,
    StructuredBuffer<float3> vertices,
    StructuredBuffer<float3> vertex_normals,
    StructuredBuffer<Shape> shapes,
    StructuredBuffer<BVHNode> bvh_nodes

)
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
            float3 rayHitPointFromObjectSpaceOfOtherShape = xform_pt(otherShape.world_to_obj, rayHitPoint);
            float3 rayDirectionFromObjectSapceOfOtherShape = xform_vec(otherShape.world_to_obj, toLights);
            float t;
            if (otherShape.type == ShapeType.Sphere)
            {
                Sphere otherSphere = spheres[shapes[j].index];
                if (IsSphereCollidingWithARay(otherSphere, rayHitPointFromObjectSpaceOfOtherShape, rayDirectionFromObjectSapceOfOtherShape, distanceBetweenPointandLight, t))
                {
                    colorByLight = float3(0, 0, 0);
                    break;
                }
            }
            if (otherShape.type == ShapeType.TriangleMesh)
            {
                TriangleMesh currentTriangleMesh = triangleMesh[otherShape.index];
                HitInformation temporaryHitInformation;
                if (IsMeshCollidingWithARay(otherShape,
                                            j,
                                            distanceBetweenPointandLight,
                                            rayHitPointFromObjectSpaceOfOtherShape,
                                            rayDirectionFromObjectSapceOfOtherShape,
                                            triangleMesh,
                                            triangles,
                                            vertices,
                                            vertex_normals,
                                            bvh_nodes,
                                            temporaryHitInformation))
                {
                    colorByLight = float3(0, 0, 0);
                    break;
                }
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
                  StructuredBuffer<BVHNode> bvh_nodes,
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
    float3 color = 0;
    float3 throughput = 1.0;
    float3 rayOrigin = worldCoordinateCameraPosition;
    float3 rayDirection = worldCoordinateNormalizedCameraForwardDirection;
    for (int j = 0; j < max_depth; j++)
    {
        HitInformation hitInformation;
        bool rayHitResult =
            TryFindRayHitPoint(rayOrigin,
                               rayDirection,
                               num_shapes,
                               bvh_nodes,
                               shapes,
                               spheres,
                               meshes,
                               triangles,
                               vertices,
                               vertex_normals,
                               hitInformation);
        if (rayHitResult)
        {
            Shape shapeToDraw = shapes[hitInformation.shapeIndex];
            float3 raySphereIntersectionCoordinate = rayOrigin + rayDirection * hitInformation.t;

            // we have to calculate normal
            color +=
                throughput *
                CalculateContributionOfSingleRay(raySphereIntersectionCoordinate,
                                                 hitInformation.worldCoordinateNormalOfRayHit,
                                                 shapeToDraw,
                                                 num_lights,
                                                 lights,
                                                 num_shapes,
                                                 spheres,
                                                 meshes,
                                                 triangles,
                                                 vertices,
                                                 vertex_normals,
                                                 shapes,
                                                 bvh_nodes);

            if ((shapeToDraw.Kr.x > 0 || shapeToDraw.Kr.y > 0 || shapeToDraw.Kr.z > 0) == false)
            {
                break;
            }
            rayOrigin = raySphereIntersectionCoordinate;
            rayDirection = reflect(rayDirection, hitInformation.worldCoordinateNormalOfRayHit);
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
