#version 450 core

#include "SDF.glsl"

#define PI 3.14159265359 

layout (location = 0) out vec4 o_Color;

uniform sampler2D u_Input;

uniform float u_zNear;
uniform float u_zFar;
uniform mat4 u_InverseProjection;
uniform mat4 u_InverseView;
uniform mat4 u_PrevProjection;
uniform mat4 u_PrevView;
uniform float u_Time;

uniform vec2 u_InvRes;
uniform vec2 u_Res;

uniform int u_Subframes;
uniform int u_TemporalFrames;

uniform float u_Thickness;
uniform int u_SHAPE;

uniform sampler2D u_Circuit;
uniform sampler2D u_Temporal;

in vec2 v_TexCoords;

// Ext 
layout (std430, binding = 0) buffer MatrixSSBO {
	mat4 Matrices[];
};

layout (std430, binding = 1) buffer Matrix2SSBO {
	mat4 SmoothMatrices[];
};

// Usecase -> 
// If you want to use this with an actual LED, it should be easily achievable by outputting each subframe to a texture 
//layout (std430, binding = 2) buffer OutputSSBO {
//	uint Packed[]
//};

// Subframe 
int SUBFRAME = 0;

// Screen
float Spacing = 8.0f;
float BlotchMagnitude = 3.0;
float DotMatrixScreenRes = 128.0f;
const vec3 BoxExtent = vec3(4.0f, 8.0f, 0.1f);

// RNG 
float HASH2SEED = 0.0f;
vec2 hash2() 
{
	return fract(sin(vec2(HASH2SEED += 0.1, HASH2SEED += 0.1)) * vec2(43758.5453123, 22578.1459123));
}

// Polar 

float GetPixelTheta(float x, float y) {
    return atan(x,y);
}

float GetPixelRadii(float x, float y) {
    return length(vec2(x,y)) * 2.f;
}

// Sky gradient 
vec3 GetSky(float R)
{
    return 1.0f * mix(vec3(0.2f, 0.4f, 0.8f), mix(vec3(1.0f), vec3(1.0f, 0.3f, 0.0f) * 1.5f, 1.0f - clamp(pow(0.0f,1.0f/15.0f),0.8f,1.f)),sqrt(1.0f-R)/1.3f);
}

// Get incident ray at some UV
vec3 SampleIncidentRayDirection(vec2 screenspace)
{
	vec4 clip = vec4(screenspace * 2.0f - 1.0f, -1.0, 1.0);
	vec4 eye = vec4(vec2(u_InverseProjection * clip), -1.0, 0.0);
	return normalize(vec3(u_InverseView * eye));
}

// raybox
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


float sdfOct(in vec3 pos)
{
    return sdfoctt(pos,0.5-0.05f) - 0.05f;
}

float sdfSph(in vec3 pos)
{
    float ra = 0.5;
    float rb = 0.35+0.20*cos(u_Time*1.1+4.0);
    float di = 0.50+0.15*cos(u_Time*1.7);
    return sdCutSph(pos, ra, rb, di );
}

float sdfBox(vec3 Point) {
    vec3 Distance = abs(Point) - vec3(0.5f); // <- gets to center of box
    float CorrectionFactor = min(max(Distance.x, max(Distance.y, Distance.z)), 0.0);
    return CorrectionFactor + length(max(Distance, 0.0));
}

vec2 GetBoxUV(vec3 p, in vec3 n)
{
    p /= BoxExtent;
    p = p * 0.5f + 0.5f;
    vec3 Mapping = abs(n);
    vec2 MeaningfulPos = (p.yz * Mapping.x + p.xz * Mapping.y + p.xy * Mapping.z);
    return fract(MeaningfulPos);
}

vec3 GetBitmask(vec3 n) {
    vec3 Mapping = abs(n);
    return vec3(0.0f, 1.0f, 1.0f) * Mapping.x + vec3(1.0f, 0.0f, 1.0f) * Mapping.y + vec3(1.0f, 1.0f, 0.0f) * Mapping.z;
}


bool LEDMatrix(vec3 p) {
 
    //if (distance(p, vec3(0.5)) < 0.3) {
    //    return true;
    //}
    //
    //return false;

    //if ( (p.x+p.y+p.z) % 2 == 0) {
    //    return true;
    //}

    //if (  p.x == p.y && p.x == p.z) {
    //    return true;
    //}

    p = p * 2.0f - 1.0f;
    p *= BoxExtent.xyx;

    p /= 4.0f;

    p = (SmoothMatrices[SUBFRAME] * vec4(p, 0.0f)).xyz;

    //if (distance(p, vec3(0.0f)) < 1.25f) {
    //    return true;
    //}

    //if (abs(p.x) + abs(p.y) + abs(p.z) < 4.0f) {
    //    return true;
    //}

    float d = -1.0f;

    switch (u_SHAPE) {

        case 0 : {
            d = sdfBox(p);
            break;
        };

        case 1 : {
            d = sdfOct(p);
            break;
        };

        case 2 : {
            d = sdfSph(p);
            break;
        };

        case 3 : {
            d = mandelbulb_sdf(p * 1.4) * 5.0f;
            break;
        }

        default : {
            d = sdfSph(p);
        }
    }

    if (d < (0.05f*u_Thickness) && d > 0.0f) {
        return true;
    }

    return false;
}


vec3 RayColor(in vec3 AcRayOrigin, in vec3 AcRayDirection, in vec3 TrRayOrigin, in vec3 TrRayDirection, in vec3 InvDir, in mat4 Mat) {
    vec3 N = vec3(-1.);

    vec2 Box = IntersectBox(TrRayOrigin, TrRayDirection, InvDir,BoxExtent , N);

    if (Box.x < 0.0f) {
        return GetSky(AcRayDirection.y); // Sky
    }

    vec3 LocalPoint = TrRayOrigin + TrRayDirection * Box.x;
    vec3 Point = AcRayOrigin + AcRayDirection * Box.x;
    //vec3 Point = (inverse(Mat) * vec4(LocalPoint, 1.0f)).xyz;

    vec2 UV = GetBoxUV(LocalPoint, N);

    bool Screenface = N == vec3(0.0f, 0.0f, 1.0f);

    float Aspect = BoxExtent.x / BoxExtent.y;
    vec2 LocalCoord = UV * vec2(DotMatrixScreenRes * Aspect,DotMatrixScreenRes);

    vec2 SinWave;
    SinWave.x = clamp(1.0f - exp(-pow(abs(sin((PI / Spacing) * LocalCoord.x)) - (BlotchMagnitude / Spacing), 4.0f) * 10.0f), 0.0f, 1.0f);
    SinWave.y = clamp(1.0f - exp(-pow(abs(sin((PI / Spacing) * LocalCoord.y)) - (BlotchMagnitude / Spacing), 4.0f) * 10.0f), 0.0f, 1.0f);

    // Matrix coordinate 
    int Px = int(floor(LocalCoord.x / Spacing) * Spacing + (0.5 * Spacing) / 8.0f);
    int Py = int(floor(LocalCoord.y / Spacing) * Spacing + (0.5 * Spacing) / 8.0f);

    vec3 ComputedColor = vec3(0.2,0.2,0.2) * 1.0f; // gray 

    //for (int i = 2 ; i <= 14 ; i += 2) {
    //    if (Px == 2 && Py == i && Screenface) {
    //        ComputedColor = vec3(1., 1., 1.) * 25.0f;
    //    }
    //
    //     if (Px == 5 && Py == i && Screenface) {
    //        ComputedColor = vec3(1., 1., 1.) * 25.0f;
    //    }
    //}

    vec3 SamplePosition = Point;
    SamplePosition /= BoxExtent.xyx;
    SamplePosition = SamplePosition * 0.5f + 0.5f;

    //SamplePosition = (floor((SamplePosition * vec3(128.0f, 256.0f, 128.0f) * 0.5f) / dotSpace) * dotSpace + (0.5 * dotSpace)) / 8.0f;

    if (LEDMatrix((SamplePosition))) {
        ComputedColor = vec3(1., 1., 1.) * 16.0f;
    }

    vec3 FinalColor = ComputedColor ; 
    //vec3 FinalColor = (ComputedColor*SinWave.x*SinWave.y)*(2.0f/(BlotchMagnitude/Spacing));

    return Screenface ? vec3(FinalColor) : vec3(0.0f, 0.2f, 0.0f) * texture(u_Circuit, UV * vec2(Aspect, 1.0f)).x;

}

vec3 Reprojection(vec3 WorldPos) 
{
	vec4 ProjectedPosition = u_PrevProjection * u_PrevView * vec4(WorldPos, 1.0f);
	ProjectedPosition.xyz /= ProjectedPosition.w;
	ProjectedPosition.xyz = ProjectedPosition.xyz * 0.5f + 0.5f;
	return ProjectedPosition.xyz;

}

void Temporal(vec3 Color,vec2 Coords) {

    bool Valid = true;

    if (Coords != clamp(Coords, 0.004f, 0.996f)) {
        Valid = false;
    }

    if (!Valid) return;

    int NumFrames = u_TemporalFrames;
    float TemporalFactor = 1.0f - (1. / float(NumFrames));
    o_Color.xyz = mix(o_Color.xyz,Color,TemporalFactor);
}

void main() {

    HASH2SEED = (v_TexCoords.x * v_TexCoords.y) * 64.0 * 8.0f;
	HASH2SEED += fract(u_Time) * 128.0f;

    vec2 JitterHash = (vec2(hash2()) * 2.0f - 1.0f);

    vec3 BaseDirection = SampleIncidentRayDirection(v_TexCoords);
    vec3 RayOrigin = u_InverseView[3].xyz;
    vec3 N; 

    vec3 RayDirection = SampleIncidentRayDirection(v_TexCoords + (JitterHash.xy*u_InvRes));

    vec2 FittedBox = IntersectBox(RayOrigin, RayDirection, 1.0/RayDirection, BoxExtent.xyx + vec3(0.02f), N);

    // Box test
    if (FittedBox.x < 0.0f && FittedBox.y < 0.0f) {
        vec2 Reprojected = Reprojection(RayOrigin+BaseDirection*64.0f).xy;
        vec3 PrevColor = texture(u_Temporal, Reprojected).xyz;
        o_Color = vec4(GetSky(RayDirection.y), 1.);
        o_Color.xyz = 1.0f - exp(-o_Color.xyz);
        Temporal(PrevColor,Reprojected);
        return;
    }

    vec3 Color = vec3(0.0f);


    for (SUBFRAME = 0 ; SUBFRAME < u_Subframes ; SUBFRAME++) {
        
        int i = SUBFRAME;

        vec3 Hash = (vec3(hash2(), hash2().x) * 2.0f - 1.0f) * 0.33f; 
        vec2 Hash2 = hash2();
        
        RayDirection = SampleIncidentRayDirection(v_TexCoords + (Hash.xy*u_InvRes));
        vec3 CurrentRayOrigin = vec3(Matrices[i] * vec4(RayOrigin, 1.0f));
        vec3 CurrentRayDirection = vec3(Matrices[i] * vec4(RayDirection, 0.0f));
        //vec3 CurrentRayDirection = vec3(Matrices[i] * vec4(SampleIncidentRayDirection(v_TexCoords + (Hash.xy*u_InvRes)), 0.0f));
        vec3 InvDir = 1.0f / CurrentRayDirection;

        vec3 CurrentColor = RayColor(RayOrigin, RayDirection, CurrentRayOrigin, CurrentRayDirection, InvDir, Matrices[i]);

        Color += CurrentColor;
    }

    Color /= float(u_Subframes);


    o_Color = vec4(vec3(Color),1.);
    o_Color.xyz = 1.0f - exp(-o_Color.xyz);

    vec2 Reprojected = Reprojection(RayOrigin+BaseDirection*max(FittedBox.x,FittedBox.y)).xy;
    vec3 PrevColor = texture(u_Temporal, Reprojected).xyz;
    Temporal(PrevColor,Reprojected);
}