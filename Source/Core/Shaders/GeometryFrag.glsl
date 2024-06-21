#version 450 core

#include "Include/Utility.glsl"

layout (location = 0) out vec4 o_Albedo;
layout (location = 1) out int o_EntityNumber;

uniform sampler2D u_AlbedoMap;
uniform sampler2D u_NormalMap;

uniform vec3 u_ViewerPosition;

uniform int u_EntityNumber;
uniform vec2 u_Dimensions;

in vec2 v_TexCoords;
in vec3 v_FragPosition;
in vec3 v_Normal;
in mat3 v_TBNMatrix;

void main()
{
	vec3 Incident = normalize(v_FragPosition - u_ViewerPosition); 
	vec3 LFN = normalize(v_Normal);
	vec3 Albedo = vec3(v_TexCoords, 1.);
	o_Albedo.xyz = Albedo * 0.1f + Albedo * clamp(dot(LFN, normalize(vec3(0.3f, 1.0f, 0.3f))), 0., 1.);

}
