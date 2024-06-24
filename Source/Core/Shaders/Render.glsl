#version 450 core
layout (location = 0) out vec4 o_Color;

uniform sampler2D u_Input;

uniform float u_zNear;
uniform float u_zFar;
uniform mat4 u_InverseProjection;
uniform mat4 u_InverseView;
uniform float u_Time;

uniform vec2 u_InvRes;
uniform vec2 u_Res;

uniform int u_Subframes;

in vec2 v_TexCoords;


layout (std430, binding = 0) buffer MatrixSSBO {
	mat4 Matrices[];
};

const vec3 BoxExtent = vec3(4.0f, 8.0f, 0.1f);

float HASH2SEED = 0.0f;
vec2 hash2() 
{
	return fract(sin(vec2(HASH2SEED += 0.1, HASH2SEED += 0.1)) * vec2(43758.5453123, 22578.1459123));
}


vec3 SampleIncidentRayDirection(vec2 screenspace)
{
	vec4 clip = vec4(screenspace * 2.0f - 1.0f, -1.0, 1.0);
	vec4 eye = vec4(vec2(u_InverseProjection * clip), -1.0, 0.0);
	return normalize(vec3(u_InverseView * eye));
}

vec2 IntersectBox(in vec3 ro, in vec3 rd, in vec3 invdir, in vec3 rad, out vec3 oN) 
{
    vec3 m = invdir;
    vec3 n = m*ro;
    vec3 k = abs(m)*rad;
    vec3 t1 = -n - k;
    vec3 t2 = -n + k;
    float tN = max( max( t1.x, t1.y ), t1.z );
    float tF = min( min( t2.x, t2.y ), t2.z );
    if( tN>tF || tF<0.0) return vec2(-1.0); // no intersection
    oN = -sign(rd)*step(t1.yzx,t1.xyz)*step(t1.zxy,t1.xyz);
    return vec2( tN, tF );
}

vec2 GetBoxUV(vec3 p, in vec3 n)
{
    p /= BoxExtent;
    p = p * 0.5f + 0.5f;
    vec3 Mapping = abs(n);
    vec2 MeaningfulPos = (p.yz * Mapping.x + p.xz * Mapping.y + p.xy * Mapping.z);
    return fract(MeaningfulPos);
}


vec3 RayColor(in vec3 RayOrigin, in vec3 RayDirection, in vec3 InvDir) {
    vec3 N = vec3(-1.);

    vec2 Box = IntersectBox(RayOrigin, RayDirection, InvDir,BoxExtent , N);

    if (Box.x < 0.0f) {
        return vec3(0.0f); // Sky
    }

    vec3 P = (RayOrigin + RayDirection * Box.x);

    vec2 UV = GetBoxUV(P, N);

    const float dotSpace = 8.0;
    const float dotSize = 3.0;
    const float sinPer = 3.141592 / dotSpace;
    const float frac = dotSize / dotSpace;
    const float DotMatrixScreenRes = 128.0f;

    float Aspect = BoxExtent.x / BoxExtent.y;

    vec2 fragCoord = UV * vec2(DotMatrixScreenRes * Aspect,DotMatrixScreenRes);

    vec2 Hash = hash2();

    float varyX = (abs(sin(sinPer * fragCoord.x + Hash.x)) - frac);
    float varyY = (abs(sin(sinPer * fragCoord.y + Hash.y)) - frac);
    float pointX = floor(fragCoord.x / dotSpace) * dotSpace + (0.5 * dotSpace);
    float pointY = floor(fragCoord.y / dotSpace) * dotSpace + (0.5 * dotSpace);

    vec3 c = (vec3(Hash.x,Hash.y,hash2().y) * varyX * varyY) * (2.0/frac);;

    return vec3(c);
}

void main() {

    HASH2SEED = (v_TexCoords.x * v_TexCoords.y) * 64.0 * 8.0f;
	HASH2SEED += fract(u_Time) * 128.0f;

    vec3 RayDirection = SampleIncidentRayDirection(v_TexCoords);

    vec3 RayOrigin = u_InverseView[3].xyz;
    vec3 N; 

    // Box test
    if (IntersectBox(RayOrigin, RayDirection, 1.0/RayDirection, BoxExtent.xyx + vec3(0.02f), N).x < 0.0f && IntersectBox(RayOrigin, RayDirection, 1.0/RayDirection, BoxExtent.xyx + vec3(0.02f), N).y < 0.0f) {
        o_Color = vec4(vec3(0.), 1.);
        return;
    }

    vec3 Color = vec3(0.0f);


    for (int i = 0 ; i < u_Subframes ; i++) {

        vec3 Hash = (vec3(hash2(), hash2().x) * 2.0f - 1.0f) * 0.2f;
        vec2 Hash2 = hash2();
        
        RayDirection = SampleIncidentRayDirection(v_TexCoords + Hash2 * u_InvRes); // Antialiasing :) 
        vec3 CurrentRayOrigin = vec3(Matrices[i] * vec4(RayOrigin, 1.0f));
        vec3 CurrentRayDirection = vec3(Matrices[i] * vec4(RayDirection, 0.0f));
        vec3 InvDir = 1.0f / CurrentRayDirection;

        vec3 CurrentColor = RayColor(CurrentRayOrigin, CurrentRayDirection, InvDir);

        Color += CurrentColor;
    }

    Color /= float(u_Subframes);

    o_Color = vec4(vec3(Color),1.);
}