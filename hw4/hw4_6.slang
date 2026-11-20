struct ContactResult
{
    float signedDistance;
    float4 contactPlane;
}
ContactResult getSignedDistanceForPlane(float4 plane, float3 position)
{
    float3 normalizedPlaneDirection = float3(plane.x, plane.y, plane.z);
    float d = plane.w;
    float signedDistance = dot(normalizedPlaneDirection, position) - d;
    return ContactResult(signedDistance, plane);
}
ContactResult getSignedDistanceForSphere(float4 sphere, float3 position)
{
    float3 sphereCenter = float3(sphere.x, sphere.y, sphere.z);
    float sphereRadius = sphere.w;
    float signedDistance = distance(sphereCenter, position) - sphereRadius;
    float3 contactPlaneNormal = normalize(position - sphereCenter);
    float3 contactPoint = sphereCenter + contactPlaneNormal * sphereRadius;
    float d = contactPlaneNormal.x * contactPoint.x + contactPlaneNormal.y * contactPoint.y + contactPlaneNormal.z * contactPoint.z;
    return ContactResult(signedDistance, float4(contactPlaneNormal, d));
}

struct BVHNode
{
    float3 bbox_min;
    float3 bbox_max;

    // which BVH node we should skip
    // to if this node is totally not
    // intersecting the ray
    // if next_index < 0, then we don't
    // have the next node to skip to
    int next_index;

    uint triangle_begin;
    uint triangle_end;

    bool is_leaf;
};

float point_aabb_distance(float3 x, float3 bmin, float3 bmax)
{
    return length(x - clamp(x, bmin, bmax));
}

struct ClosestPoint
{
    float3 position;
    float3 bary;
};

// From https://iquilezles.org/articles/distfunctions/
ClosestPoint closest_point_triangle(
    float3 p, float3 a, float3 b, float3 c)
{
    float3 ba = b - a, pa = p - a;
    float3 cb = c - b, pb = p - b;
    float3 ac = a - c, pc = p - c;
    float3 nor = cross(ba, ac);

    float t0 = clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0);
    float t1 = clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0);
    float t2 = clamp(dot(ac, pc) / dot(ac, ac), 0.0, 1.0);

    float3 q0 = a + ba * t0;
    float3 q1 = b + cb * t1;
    float3 q2 = c + ac * t2;

    if (sign(dot(cross(ba, nor), pa)) +
            sign(dot(cross(cb, nor), pb)) +
            sign(dot(cross(ac, nor), pc)) <
        2.0)
    {

        float d0 = dot(p - q0, p - q0);
        float d1 = dot(p - q1, p - q1);
        float d2 = dot(p - q2, p - q2);

        if (d0 < d1 && d0 < d2)
            return { q0, float3(1.0 - t0, t0, 0.0) };
        if (d1 < d2)
            return { q1, float3(0.0, 1.0 - t1, t1) };
        return { q2, float3(t2, 0.0, 1.0 - t2) };
    }

    float inv_nor2 = 1.0 / dot(nor, nor);
    float3 q = p - nor * (dot(nor, pa) * inv_nor2);

    float wb = dot(cross(pa, ac), nor) * inv_nor2;
    float wc = dot(cross(pa, ba), nor) * inv_nor2;
    return { q, float3(1.0 - wb - wc, wb, wc) };
}

[shader("compute")]
[numthreads(64, 1, 1)]
void detect_collision(uint tid: SV_DispatchThreadID,
                      StructuredBuffer<float3> positions,
                      StructuredBuffer<float> inv_masses,
                      StructuredBuffer<float4> planes,
                      StructuredBuffer<float4> spheres,
                      StructuredBuffer<float3> mesh_vertices,
                      StructuredBuffer<float3> mesh_vertex_normals,
                      StructuredBuffer<uint3> mesh_triangles,
                      StructuredBuffer<BVHNode> bvh_nodes,
                      RWStructuredBuffer<float4> contact_planes,
                      uniform uint num_particles,
                      uniform uint num_planes,
                      uniform uint num_spheres,
                      uniform uint num_bvh_nodes,
                      uniform float collision_distance,
                      uniform float contact_margin)
{
    if (tid >= num_particles)
    {
        return;
    }

    if (inv_masses[tid] == 0)
    {
        contact_planes[tid] = float4(0, 0, 0, 0);
        return;
    }
    float3 positionOfPoint = positions[tid];
    ContactResult contactResult = ContactResult(float.maxValue, float4(0, 0, 0, 0));
    for (int i = 0; i < num_planes; i++)
    {
        float4 planeInfo = planes[i];
        ContactResult contactResultFromPlane = getSignedDistanceForPlane(planeInfo, positionOfPoint);
        if (contactResultFromPlane.signedDistance < contactResult.signedDistance)
        {
            contactResult = contactResultFromPlane;
        }
    }
    for (int i = 0; i < num_spheres; i++)
    {
        float4 sphereInfo = spheres[i];
        ContactResult contactResultFromSphere = getSignedDistanceForSphere(sphereInfo, positionOfPoint);
        if (contactResultFromSphere.signedDistance < contactResult.signedDistance)
        {
            contactResult = contactResultFromSphere;
        }
    }

    BVHNode bvhRootNode = bvh_nodes[0];
    int bvhTraversalPointer = 0;
    int bvhTraversalEndPointer = bvhRootNode.next_index;
    float unsignedDistanceForTriangle = float.maxValue;
    int triangleIndex = -1;
    while (bvhTraversalPointer < bvhTraversalEndPointer)
    {
        BVHNode currentNode = bvh_nodes[bvhTraversalPointer];
        if (point_aabb_distance(positionOfPoint, currentNode.bbox_min, currentNode.bbox_max) < contact_margin + collision_distance)
        {
            if (currentNode.is_leaf)
            {
                for (int i = currentNode.triangle_begin; i < currentNode.triangle_end; i++)
                {
                    uint3 triangleIndices = mesh_triangles[i];
                    float3 vertexPos1 = mesh_vertices[triangleIndices[0]];
                    float3 vertexPos2 = mesh_vertices[triangleIndices[1]];
                    float3 vertexPos3 = mesh_vertices[triangleIndices[2]];

                    float3 vertexNormal1 = mesh_vertex_normals[triangleIndices[0]];
                    float3 vertexNormal2 = mesh_vertex_normals[triangleIndices[1]];
                    float3 vertexNormal3 = mesh_vertex_normals[triangleIndices[2]];

                    ClosestPoint closestPointTriangle = closest_point_triangle(positionOfPoint, vertexPos1, vertexPos2, vertexPos3);

                    float distanceBetweenTriangleAndPoint = distance(closestPointTriangle.position, positionOfPoint);
                    if (distanceBetweenTriangleAndPoint < unsignedDistanceForTriangle && distanceBetweenTriangleAndPoint < contact_margin + collision_distance)
                    {
                        unsignedDistanceForTriangle = distanceBetweenTriangleAndPoint;
                        triangleIndex = i;
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
            bvhTraversalPointer = currentNode.next_index;
        }
    }
    if (triangleIndex != -1)
    {
        uint3 triangleIndices = mesh_triangles[triangleIndex];
        float3 vertexPos1 = mesh_vertices[triangleIndices[0]];
        float3 vertexPos2 = mesh_vertices[triangleIndices[1]];
        float3 vertexPos3 = mesh_vertices[triangleIndices[2]];

        float3 vertexNormal1 = mesh_vertex_normals[triangleIndices[0]];
        float3 vertexNormal2 = mesh_vertex_normals[triangleIndices[1]];
        float3 vertexNormal3 = mesh_vertex_normals[triangleIndices[2]];
        float3 faceNormal = normalize(cross(vertexPos2 - vertexPos1, vertexPos3 - vertexPos1));
        ClosestPoint closestPointTriangle = closest_point_triangle(positionOfPoint, vertexPos1, vertexPos2, vertexPos3);

        float3 vertexNormal = normalize(closestPointTriangle.bary.x * vertexNormal1 + closestPointTriangle.bary.y * vertexNormal2 + closestPointTriangle.bary.z * vertexNormal3);

        if (dot(faceNormal, vertexNormal) < 0.0)
        {
            faceNormal = -faceNormal;
        }
        float d = faceNormal.x * vertexPos1.x + faceNormal.y * vertexPos1.y + faceNormal.z * vertexPos1.z;

        float4 planeForThisTriangle = float4(faceNormal.x, faceNormal.y, faceNormal.z, d);

        ContactResult contactResultFromPlane = getSignedDistanceForPlane(planeForThisTriangle, positionOfPoint);
        if (contactResultFromPlane.signedDistance < contactResult.signedDistance)
        {
            contactResult = contactResultFromPlane;
        }
    }

    if (contactResult.signedDistance < collision_distance + contact_margin)
    {
        contactResult.contactPlane.w += collision_distance;
        contact_planes[tid] = contactResult.contactPlane;
    }
    else
    {
        contact_planes[tid] = float4(0, 0, 0, 0);
    }
}
