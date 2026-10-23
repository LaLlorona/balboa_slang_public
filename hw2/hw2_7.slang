StructuredBuffer<float3> vertices;
StructuredBuffer<float3> vertex_normals;
StructuredBuffer<float2> vertex_uvs;
uniform float4x4 MVP;
uniform float4x4 model_matrix;
uniform float3x3 normal_matrix; // inverse transpose of the top-left 3x3 above
uniform float3 light_dir;
uniform float3 light_color;
uniform float3 camera_position;
uniform float3 Ks;
uniform float exponent;
Texture2D<float4> Kd_texture;
SamplerState Kd_sampler;

struct VertexOutput
{
    float4 position : SV_Position;
    float3 world_position : TEXCOORD0;
    float3 world_normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

[shader("vertex")]
VertexOutput vertex_main(uint vid: SV_VertexID)
{
    // HW 2.6: your code here
    float4 vertexCoordinate = float4(vertices[vid], 1);

    float4 screenCoordinateAfterMVP = mul(MVP, vertexCoordinate);
    float2 vertexUv = vertex_uvs[vid];
    float3 worldNormal = normalize(mul(normal_matrix, vertex_normals[vid]));
    float4 worldPositionWithOneAttached = mul(model_matrix, vertexCoordinate);
    float3 worldPosition = worldPositionWithOneAttached.xyz;

    return VertexOutput(screenCoordinateAfterMVP, worldPosition, worldNormal, vertexUv);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target
{
    // HW 2.7 TODO: implement
    float4 albedoColorFloat4 = Kd_texture.Sample(Kd_sampler, input.uv);
    float3 albedoColor = albedoColorFloat4.xyz;
    float3 normalizedWorldNormal = normalize(input.world_normal);
    float3 diffuseColor = albedoColor * light_color * max(0, dot(normalizedWorldNormal, light_dir));

    float3 specularColor = float3(0);
    float3 reflectionDirection = 2 * dot(normalizedWorldNormal, light_dir) * normalizedWorldNormal - light_dir;
    float3 viewVector = normalize(camera_position - input.world_position);
    if (dot(normalizedWorldNormal, light_dir) > 0)
    {
        specularColor = Ks * light_color * pow(max(0, dot(reflectionDirection, viewVector)), exponent);
    }

    float3 ambientColor = albedoColor * 0.2;
    float3 combinedColor = diffuseColor + ambientColor + specularColor;

    return float4(combinedColor, 1.0);
}
