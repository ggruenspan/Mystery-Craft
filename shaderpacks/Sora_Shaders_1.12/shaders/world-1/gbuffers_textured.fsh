#version 120
#extension GL_EXT_gpu_shader4 : enable
#extension GL_ARB_shader_texture_lod : enable

#define NORMAL_MAP_BUMPMULT 1.0 // [0.0 0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]
#define PBR_FORMAT 0 // [0 1 2 3]
#define AMBIENT_OCCLUSION

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec3 tangent;
varying vec4 normal;
varying vec3 binormal;
varying vec4 color;

uniform sampler2D texture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform sampler2D colortex6;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;

uniform vec3 upPosition;

uniform ivec2 eyeBrightness;

uniform int isEyeInWater;
uniform int worldTime;

uniform float rainStrength;
uniform float sunAngle;
uniform float screenBrightness;
uniform float viewWidth;
uniform float viewHeight;

float luma(vec3 clr) {
	return dot(clr, vec3(0.3333));
}

float encodeLightmap(vec2 a) {

  ivec2 bf = ivec2(a * 255.0);
  return float(bf.x | (bf.y << 8)) / 65535.0;

}

vec2 encodeNormal(vec3 normal) {

  return normal.xy * inversesqrt(normal.z * 8.0 + 8.0) + 0.5;

}

bool material(float id) {

	if (normal.a > id - 0.01 && normal.a < id + 0.01) {
		return true;
	} else {
		return false;
	}

}

vec3 getNormals(vec2 coord) {

		vec2 dcdx = dFdx(coord);
		vec2 dcdy = dFdy(coord);

		vec3 bump  = texture2DGradARB(normals, coord, dcdx, dcdy).rgb * 2.0 - 1.0;
				 bump *= vec3(NORMAL_MAP_BUMPMULT) + vec3(0.0, 0.0, 1.0 - NORMAL_MAP_BUMPMULT);

		mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
													tangent.y, binormal.y, normal.y,
													tangent.z, binormal.z, normal.z);

	return normalize(bump * tbnMatrix);

}

float getTorchLightmap(vec3 normal, float lightmap, float skyLightmap, bool translucent) {

	float tRadius = 2.5;	// Higher means lower.
	float tBrightness = 1.0;

	float NdotL = translucent? 1.0 : clamp(dot(normal, normalize(upPosition)), 0.0, 1.0) + clamp(dot(normal, normalize(-upPosition)), 0.0, 1.0);

	float torchLightmap = pow(lightmap, tRadius) * tBrightness * (1.0 + NdotL * 0.5);
				torchLightmap *= mix(color.a, 1.0, torchLightmap);

	return torchLightmap;

}

vec3 emissiveLight(vec3 clr, vec3 originalClr, bool emissive) {

	const float exposure	= 2.5;
	const float cover		= 0.3;

	//if (forHand) emissive = emissiveHandlight;
	if (emissive) clr = mix(clr.rgb, vec3(exposure), max(luma(originalClr.rgb) - cover, 0.0));

	return clr;

}

vec3 lowlightEye(vec3 color, float skyLightmap, float torchLightmap) {

	float desaturationAmount = 0.6;

	desaturationAmount *= 1.0 - torchLightmap;

	return mix(color, vec3(luma(color)), desaturationAmount);

}

vec3 toNDC(vec3 pos){
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = pos * 2. - 1.;
    vec4 fragpos = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragpos.xyz / fragpos.w;
}

vec3 PBRData(vec4 spec) {

	float roughness = 1.0;
	float metallic = 1.0;

	#if (PBR_FORMAT == 0)

		// Common
		roughness = 1.0 - spec.r;
		metallic = spec.g;

	#elif (PBR_FORMAT == 1)

		// Pulchra + Continuum Addon
		roughness = 1.0 - spec.b;
		metallic = spec.r;

	#elif (PBR_FORMAT == 2)

		// Chroma Hills
		roughness = 1.0 - spec.r;
		metallic = spec.b;

	#endif

	return vec3(roughness, metallic, luma(spec.rgb));

}


void main() {

	bool hand = gl_FragCoord.z < 0.56;
	bool translucent = material(0.2);
	bool emissive = material(0.3);

	vec4 albedo = texture2D(texture, texcoord) * mix(color, color * vec4(1.8, 1.4, 1.0, 1.0), 1.0 - luma(color.rgb));

	vec4 baseColor = albedo;
	vec3 newNormal = hand? normal.rgb : getNormals(texcoord);

	vec3 fragposition = toNDC(vec3(gl_FragCoord.xy / vec2(viewWidth,viewHeight), hand? gl_FragCoord.z + 0.38 : gl_FragCoord.z));

	#include "lib/colors.glsl"



	const float ambientStrength = 0.4;
	const float sunlightStrength = 1.0;


	float minLight = 0.1 + screenBrightness * 0.03;

	float smoothLighting = 0.3 + color.a * 0.7;

	#ifdef AMBIENT_OCCLUSION
		smoothLighting = 0.7 + color.a * 0.3;
	#endif

	vec3 ambientLightmap = (minLight + ambientColor * ambientStrength) * smoothLighting;
			 ambientLightmap += getTorchLightmap(newNormal, lmcoord.x, lmcoord.y, translucent) * torchColor;
			 ambientLightmap = emissiveLight(ambientLightmap, baseColor.rgb * torchColor, emissive);

	baseColor.rgb = lowlightEye(baseColor.rgb, lmcoord.y, lmcoord.x);
	baseColor.rgb *= ambientLightmap;


/* DRAWBUFFERS:0124 */

  gl_FragData[0] = baseColor;
  gl_FragData[1] = vec4(encodeLightmap(lmcoord), encodeNormal(newNormal), normal.a);
  gl_FragData[2] = vec4(hand? vec3(0.0) : PBRData(texture2D(specular, texcoord)), 1.0);
	gl_FragData[3] = vec4(albedo.rgb, 1.0);
}
