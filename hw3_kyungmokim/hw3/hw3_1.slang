import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  StructuredBuffer<Sphere> spheres,
                  uniform int num_spheres,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    float2 xyScreenCoordinate = float2(tid.x + 0.5, (height - 1 - tid.y) + 0.5);
    float aspectRatio = (float)width / (float)height;
    float cameraSpaceCoordinateX = -aspectRatio + xyScreenCoordinate.x / width * aspectRatio * 2;
    float cameraSpaceCorodinateY = -1 + xyScreenCoordinate.y / height * 2;
    float3 cameraSpaceCoordinate = float3(cameraSpaceCoordinateX, cameraSpaceCorodinateY, -1);
    float3 d = cameraSpaceCoordinate;
    float3 dNormalized = normalize(cameraSpaceCoordinate);


    image[tid] = float4(background, 1.0);
    float tCandidiate = float.maxValue;
    int sphereToDrawIndex = -1; 
    for (int i = 0; i < num_spheres; i++) {
        // check whether ray hits the sphere
        Sphere sphere = spheres[i];
        float3 sphereCenter = sphere.center;
        float radius = sphere.radius;
        float3 OMinusXc = -sphereCenter;
        float a = dot(dNormalized, dNormalized);
        float b = 2 * dot(dNormalized, OMinusXc);
        float c = dot(OMinusXc, OMinusXc) - radius * radius;

        float2 quadraticSolution;

        if (solve_quadratic(a, b, c, quadraticSolution)) {
            if (quadraticSolution.x > 0 && tCandidiate > quadraticSolution.x) {
                tCandidiate = quadraticSolution.x;
                sphereToDrawIndex = i;
                
            }
            if (quadraticSolution.y > 0 && tCandidiate > quadraticSolution.y) {
                tCandidiate = quadraticSolution.y;
                sphereToDrawIndex = i;
            }
        }
    }
    if (sphereToDrawIndex != -1) {
        Sphere sphereToDraw = spheres[sphereToDrawIndex];
        float3 raySphereIntersectionCoordinate = dNormalized * tCandidiate;
        float3 sphereCenter = sphereToDraw.center;
        float3 vector3NormalDirection = normalize(raySphereIntersectionCoordinate - sphereCenter);
        float4 normalColor = float4((vector3NormalDirection + 1) / 2,1);
        image[tid] = normalColor;
    }



}
