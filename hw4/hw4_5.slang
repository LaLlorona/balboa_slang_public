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
[shader("compute")]
[numthreads(64, 1, 1)]
void detect_collision(uint tid: SV_DispatchThreadID,
                      StructuredBuffer<float3> positions,
                      StructuredBuffer<float> inv_masses,
                      // Plane stores (a, b, c, d) where ax+by+cz=d
                      // a, b, c are normalized to a unit 3D vector
                      StructuredBuffer<float4> planes,
                      // Sphere stores center (xyz) + radius (w)
                      StructuredBuffer<float4> spheres,
                      // Contact plane: dot(n, x) = d, with unit normal n
                      // Set to (0, 0, 0, 0) if there is no contact
                      RWStructuredBuffer<float4> contact_planes,
                      uniform uint num_particles,
                      uniform uint num_planes,
                      uniform uint num_spheres,
                      // How much should we shift the generated
                      // contact plane in the normal direction
                      // (similar to how we shifted the floor by 0.03
                      //  earlier)
                      uniform float collision_distance,
                      // When the signed distance function
                      // evaluates to a value below
                      // contact_margin + collision_distance
                      // (even when it's positive), we count the
                      // particle to be inside the collider and
                      // a collision event has happened.
                      uniform float contact_margin)
{
    if (tid >= num_particles)
    {
        return;
    }
    // TODO: HW 4.5. Your code below.
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

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid: SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         StructuredBuffer<float3> old_positions,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         StructuredBuffer<uint> row_ptr,
                         StructuredBuffer<uint> neighbors,
                         StructuredBuffer<float> neighbor_rest,
                         // Contact plane: dot(n, x) = d, with unit normal n
                         StructuredBuffer<float4> contact_planes,
                         uniform uint num_particles,
                         uniform float static_friction,
                         uniform float kinetic_friction)
{
    if (tid >= num_particles)
    {
        return;
    }
    // TODO: HW 4.5. Your code below.

    // part1: distance constraint
    if (inv_masses[tid] == 0)
    {
        positions_out[tid] = positions_in[tid];
        return;
    }
    float3 positionOfCurrentParticle = positions_in[tid];
    float weightOfCurrentParticle = inv_masses[tid];

    float3 correction = 0;
    int totalNumberOfNeighbors = 0;
    int neighborStartIndex = row_ptr[tid];
    int neighborEndIndex = row_ptr[tid + 1];
    for (int i = neighborStartIndex; i < neighborEndIndex; i++)
    {
        int neighborIndex = neighbors[i];
        totalNumberOfNeighbors++;
        float weightOfNeighborParticle = inv_masses[neighborIndex];
        float3 positionOfNeighborParticle = positions_in[neighborIndex];
        float3 d = (positionOfNeighborParticle - positionOfCurrentParticle);
        float constraintLength = neighbor_rest[i];

        correction += weightOfCurrentParticle / (weightOfCurrentParticle + weightOfNeighborParticle) * (length(d) - constraintLength) * d / (length(d));
    }
    float3 updatedPosition = positions_in[tid] + correction / totalNumberOfNeighbors;

    float4 contactPlane = contact_planes[tid];

    if (contactPlane.x == 0 && contactPlane.y == 0 && contactPlane.z == 0 && contactPlane.w == 0)
    {
        positions_out[tid] = updatedPosition;
        return;
    }

    // normal Correction
    float3 contactPlaneNormal = float3(contactPlane.x, contactPlane.y, contactPlane.z);
    float3 oldPosition = old_positions[tid];
    ContactResult contactResultFromContactPlane = getSignedDistanceForPlane(contactPlane, updatedPosition);

    if (contactResultFromContactPlane.signedDistance < 0)
    {
        updatedPosition = updatedPosition + contactPlaneNormal * abs(contactResultFromContactPlane.signedDistance);
    }

    // tangent correction

    float3 tangent = updatedPosition - oldPosition - dot(updatedPosition - oldPosition, contactPlaneNormal) * contactPlaneNormal;

    if (contactResultFromContactPlane.signedDistance < 0)
    {
        if (length(tangent) <= static_friction * abs(contactResultFromContactPlane.signedDistance))
        {
            updatedPosition = updatedPosition - tangent;
        }
        else
        {
            updatedPosition = updatedPosition - normalize(tangent) * kinetic_friction * abs(contactResultFromContactPlane.signedDistance);
        }
    }

    positions_out[tid] = updatedPosition;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void update_velocity(uint tid: SV_DispatchThreadID,
                     RWStructuredBuffer<float3> positions,
                     StructuredBuffer<float3> old_positions,
                     RWStructuredBuffer<float3> velocities,
                     StructuredBuffer<float> inv_masses,
                     uniform uint num_particles,
                     uniform float dt)
{
    if (tid >= num_particles)
    {
        return;
    }
    // TODO: HW 4.5. Your code below.
    if (inv_masses[tid] == 0)
    {
        // positions[tid] = old_positions[tid];
        // velocities[tid] = 0;
        return;
    }
    float3 nextFramePosition = positions[tid];

    // if (nextFramePosition.y < FLOOR_Y_COORDINATE)
    // {
    //     nextFramePosition = float3(nextFramePosition.x, FLOOR_Y_COORDINATE, nextFramePosition.z);
    // }
    float3 nextFrameVelocity = (nextFramePosition - old_positions[tid]) / dt;
    positions[tid] = nextFramePosition;
    velocities[tid] = nextFrameVelocity;
}
