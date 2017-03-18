#version 420

// http://gamedev.stackexchange.com/questions/63832/normals-vs-normal-maps/63833
// http://blog.selfshadow.com/publications/blending-in-detail/
// http://www.trentreed.net/blog/physically-based-shading-and-image-based-lighting/
// http://graphicrants.blogspot.com/2013/08/specular-brdf-reference.html

#define saturate(x) clamp(x, 0.0, 1.0)
#define PI 3.1415926535897932384626433832795

const int MAX_POINT_LIGHTS = 4;

struct DirectionalLight
{
    vec3 color;
    vec3 direction;
    float amount;
};

struct PointLight
{
    vec3 color; // 12
    vec3 position; // 12
    float radius; // 4
};

layout(binding = 0, std140) uniform PerScene
{
    DirectionalLight u_directionalLight;
    PointLight u_pointLights[MAX_POINT_LIGHTS];
    float u_time;
    int u_activePointLights;
    vec2 resolution;
    vec2 invResolution;
};

layout(binding = 1, std140) uniform PerView
{
    mat4 u_viewMatrix;
    mat4 u_viewProjMatrix;
    vec3 u_eyePos;
};

in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_texcoord;
in vec3 v_tangent;
in vec3 v_bitangent;

uniform sampler2D s_albedo;
uniform sampler2D s_normal;
uniform sampler2D s_roughness;
uniform sampler2D s_metallic;

uniform float u_roughness = 1.0;
uniform float u_metallic = 1.0;
uniform float u_specular = 1.0;

out vec4 f_color;

vec3 blend_normals(vec3 geometric, vec3 detail)
{
    vec3 n1 = geometric;
    vec3 n2 = detail;
    mat3 nBasis = mat3(vec3(n1.z, n1.y, -n1.x), vec3(n1.x, n1.z, -n1.y), vec3(n1.x, n1.y,  n1.z));
    return normalize(n2.x*nBasis[0] + n2.y*nBasis[1] + n2.z*nBasis[2]);
}

// Gotanda 2012, "Beyond a Simple Physically Based Blinn-Phong Model in Real-Time"
vec3 compute_diffuse_term(vec3 diffuseColor, float roughness4, float NoV, float NoL, float VoH)
{
    float VoL = 2 * VoH - 1;
    float c1 = 1 - 0.5 * roughness4 / (roughness4 + 0.33);
    float cosri = VoL - NoV * NoL;
    float c2 = 0.45 * roughness4 / (roughness4 + 0.09) * cosri * (cosri >= 0 ? min(1, NoL / NoV) : NoL);
    return diffuseColor / PI * (NoL * c1 + c2);
}

// GGX normal distribution
float get_normal_distribution(float roughness4, float NoH)
{
    float d = (NoH * roughness4 - NoH) * NoH + 1;
    return roughness4 / (d*d);
}

// Smith GGX geometric shadowing from "Physically-Based Shading at Disney"
float get_geometric_shadowing(float roughness4, float NoV, float NoL, float VoH)
{   
    float gSmithV = NoV + sqrt(NoV * (NoV - NoV * roughness4) + roughness4);
    float gSmithL = NoL + sqrt(NoL * (NoL - NoL * roughness4) + roughness4);
    return 1.0 / (gSmithV * gSmithL);
}

// Fresnel term
vec3 get_fresnel(vec3 specularColor, float VoH)
{
    vec3 specularColorSqrt = sqrt(clamp(vec3(0, 0, 0), vec3(0.99, 0.99, 0.99), specularColor));
    vec3 n = (1 + specularColorSqrt) / (1 - specularColorSqrt);
    vec3 g = sqrt(n * n + VoH * VoH - 1);
    return 0.5 * pow((g - VoH) / (g + VoH), vec3(2.0)) * (1 + pow(((g+VoH)*VoH - 1) / ((g-VoH)*VoH + 1), vec3(2.0)));
}

// http://imdoingitwrong.wordpress.com/2011/01/31/light-attenuation/
float get_attenuation(vec3 lightPosition, vec3 vertexPosition, float lightRadius)
{
    const float cutoff = 0.0052f;

    float r = lightRadius;
    vec3 L = lightPosition - vertexPosition;
    float dist = length(L);
    float d = max(dist - r, 0);
    L /= dist;
    float denom = d / r + 1.0f;

    float attenuation = 1.0f / (denom * denom);
    attenuation = (attenuation - cutoff) / (1.0 - cutoff);
    attenuation = max(attenuation, 0.0);
    return attenuation;
}

void main()
{
    // Surface properties
    float roughnessMask = texture(s_roughness, v_texcoord).r;
    float metallicMask = texture(s_metallic, v_texcoord).r;

    vec3 albedo = texture(s_albedo, v_texcoord).xyz;
    vec3 diffuseColor = albedo - albedo * u_metallic * metallicMask;
    vec3 specularColor = mix(vec3(0.08 * u_specular), albedo, u_metallic * metallicMask);

    vec3 viewDir = normalize(u_eyePos - v_world_position);
    vec3 normalWorld = blend_normals(v_normal, texture(s_normal, v_texcoord).xyz);

    vec3 directLighting = vec3(0, 0, 0);

    for (int i = 0; i < u_activePointLights; ++i)
    {
        vec3 N = normalWorld;
        vec3 L = normalize(u_pointLights[i].position - v_world_position); 
        vec3 V = viewDir; 
        vec3 H = normalize(V + L); // half vector
        
        float NoL = saturate(dot(N, L));
        float NoV = saturate(dot(N, V));
        float VoH = saturate(dot(V, H));
        float NoH = saturate(dot(N, H));
        
        // compute the BRDF
        // f = D * F * G / (4 * (N.L) * (N.V));
        float distribution = get_normal_distribution(u_roughness * roughnessMask, NoH);
        vec3 fresnel = get_fresnel(specularColor, VoH);
        float geom = get_geometric_shadowing(u_roughness * roughnessMask, NoV, NoL, VoH);

        vec3 diffuseTerm = compute_diffuse_term(diffuseColor, u_roughness * roughnessMask, NoV, NoL, VoH);
        vec3 specularTerm = NoL * (distribution * fresnel * geom);

        vec3 Lo += u_pointLights[i].color * (diffuseTerm + specularTerm);
        
        float attenuation = get_attenuation(u_pointLights[i].position, v_world_position, u_pointLights[i].radius);
        Lo *= attenuation;

        directLighting *= Lo;
    }

    f_color = vec4(directLighting, 1);
}