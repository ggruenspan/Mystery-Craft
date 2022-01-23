#version 120
#extension GL_EXT_gpu_shader4 : enable
#extension GL_ARB_shader_texture_lod : enable

#define SHADOW_MAP_BIAS 0.8
#define SOFT_SHADOWS
#define FIX_SUNLIGHT_LEAK
#define NORMAL_MAP_BUMPMULT 1.0 // [0.0 0.2 0.4 0.6 0.8 1.0 1.2 1.4 1.6 1.8 2.0]
#define PBR_FORMAT 0 // [0 1 2 3]
#define COLOR_LENS 2 // [0 1 2]
#define AMBIENT_OCCLUSION
#define AS 0.6  // [0.00 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.225 0.25 0.275 0.3 0.325 0.35 0.375 0.4 0.425 0.45 0.475 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
#define SS 0.55 // [0.00 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.225 0.25 0.275 0.3 0.325 0.35 0.375 0.4 0.425 0.45 0.475 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
#define TR 0.2  // [0.00 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.225 0.25 0.275 0.3 0.325 0.35 0.375 0.4 0.425 0.45 0.475 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
#define TB 0.4  // [0.00 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.225 0.25 0.275 0.3 0.325 0.35 0.375 0.4 0.425 0.45 0.475 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]

//#define PBR
//#define SHAKING_CAMERA
varying vec2 texcoord;
varying vec2 lmcoord;
varying vec3 tangent;
varying vec4 normal;
varying vec3 binormal;
varying vec4 color;

uniform sampler2DShadow shadowtex0;
uniform sampler2D texture;
uniform sampler2D normals;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;

uniform ivec2 eyeBrightness;

uniform int isEyeInWater;
uniform int worldTime;

uniform float rainStrength;
uniform float sunAngle;
uniform float screenBrightness;
uniform float nightVision;
uniform float viewWidth;
uniform float viewHeight;


const int shadowMapResolution = 2048;	// [1024 1536 2048 3172 4096 8192]
const float shadowDistance = 128.0;	// [64.0 72.0 80.0 88.0 96.0 104.0 112.0 120.0 128.0 136.0 144.0 152.0 160.0 168.0 176.0 184.0 192.0 200.0 208.0 216.0 224.0 232.0 240.0 248.0 256.0 512.0]
const bool shadowHardwareFiltering = true;

#include "lib/timeArray.glsl"

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

	float tRadius = 1.7 - ((TR - 0.5) * 2);	// Higher means lower.
	float tBrightness = 0.22 + ((TB - 0.5) * 1.2);

	tBrightness *= 1.0 - (skyLightmap * (1.0 - time[5])) * 0.8;

	float NdotL = translucent? 1.0 : clamp(dot(normal, normalize(upPosition)), 0.0, 1.0) + clamp(dot(normal, normalize(-upPosition)), 0.0, 1.0);

	float torchLightmap = max(exp(pow(lightmap + 0.5, tRadius)) - 1.3, 0.0) * tBrightness * (1.0 + NdotL * 0.5);
				torchLightmap *= mix(color.a, 1.0, torchLightmap);

	return torchLightmap;

}

vec3 emissiveLight(vec3 clr, vec3 originalClr, bool emissive) {

	const float exposure	= 3.5;
	const float cover		= 0.3;

	//if (forHand) emissive = emissiveHandlight;
	if (emissive) clr = mix(clr.rgb, vec3(exposure), max(luma(originalClr.rgb) - cover, 0.0));

	return clr;

}

float bouncedLight(vec3 normal, float lightmap) {

	float bouncedLightStrength = 0.25;

	float shadowLength = 1.0 - abs(-0.25 + sunAngle) * 4.0;

	float bounce0 = max(dot(normal, -normalize(shadowLightPosition)), 0.0);
  float bounce1 = max(dot(normal, normalize(shadowLightPosition)), 0.0);
  float ground = max(dot(normal, normalize(upPosition)), 0.0);
	float light = mix(bounce0 * 0.5, bounce1 * (1.0 - ground) * shadowLength * 3.0, 1.0 - lightmap) * smoothstep(0.8, 1.0, color.a);

	return light * lightmap * bouncedLightStrength + bounce1 * bouncedLightStrength * 0.5 * smoothstep(0.8, 1.0, lightmap);

}

vec3 lowlightEye(vec3 color, vec3 ambientLightmap) {

	return mix(color, vec3(luma(color)), pow(max(1.0 - luma(ambientLightmap), 0.0), 4.0));

}

float subsurfaceScattering(vec3 fragpos, bool translucent) {

  const float strength = 0.25;

  float sunVector = max(dot(normalize(fragpos), normalize(sunPosition)), 0.0);
	float light	= pow(sunVector, 2.0) * float(translucent);

  return light * strength;

}

float calcShadows(vec3 fragpos, float NdotL, bool translucent) {

	float shadowSmoothnessFactor = 1.0 / shadowMapResolution * 0.7;

	float diffuse = translucent? 0.75 : NdotL;
	float shading = 1.0;

	float dist = length(fragpos.xyz);
	float shadowDistanceScale = shadowDistance * (1.0 + (128.0 / shadowDistance));
	float shadowFade = clamp((1.0 - dist / shadowDistanceScale) * 12.0, 0.0, 1.0);

	if (diffuse > 0.001 && dist < shadowDistanceScale) {

		vec4 worldPos = gbufferModelViewInverse * vec4(fragpos, 1.0);
				 worldPos = shadowModelView * worldPos;
			 	 worldPos = shadowProjection * worldPos;

		float distortion = ((1.0 - SHADOW_MAP_BIAS) + length(worldPos.xy * 1.165) * SHADOW_MAP_BIAS) * 0.97;
		worldPos.xy /= distortion;

		float shadowAcneFix = 2048.0 / shadowMapResolution;

		float bias = translucent? 0.00025 : distortion * distortion * (0.0015 * tan(acos(pow(diffuse, 1.1)))) * shadowAcneFix;
		worldPos.xyz = worldPos.xyz * vec3(0.5, 0.5, 0.2) + vec3(0.5, 0.5, 0.5 - bias);

		#ifdef SOFT_SHADOWS

			shading = 0.0;

			vec2 offsets[4] = vec2[4](vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(0.0, -1.0));

			for (int i = 0; i < 4; i++) {

				shading += shadow2D(shadowtex0, vec3(worldPos.xy + offsets[i] * shadowSmoothnessFactor, worldPos.z)).x * 0.25;

			}

		#else

			shading = shadow2D(shadowtex0, worldPos.xyz).x;

		#endif

	}

	#ifdef FIX_SUNLIGHT_LEAK
		shading *= (lmcoord.y < 0.1? eyeBrightness.y / 240.0 : 1.0);
	#endif

	return mix(NdotL, shading * diffuse, shadowFade);

}

vec3 toNDC(vec3 pos){
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = pos * 2. - 1.;
    vec4 fragpos = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragpos.xyz / fragpos.w;
}

#ifdef PBR

	uniform sampler2D specular;

	vec3 PBRData() {

		vec4 spec = texture2D(specular, texcoord);

		float roughness = 0.0;
		float metallic = 0.0;

		#if (PBR_FORMAT == 0)

			// Common
			roughness = 1.0 - spec.r;
			metallic = spec.g;

		#elif (PBR_FORMAT == 2)

			// Pulchra + Continuum Addon
			roughness = 1.0 - spec.b;
			metallic = spec.r;

		#elif (PBR_FORMAT == 3)

			// Chroma Hills
			roughness = 1.0 - spec.r;
			metallic = spec.b;

		#endif

		return vec3(roughness, metallic, luma(spec.rgb));

	}

#endif


void main() {

	bool hand = gl_FragCoord.z < 0.56;
	bool translucent = material(0.2);
	bool emissive = material(0.3);

	#if (COLOR_LENS == 0)
	vec4 albedo = texture2D(texture, texcoord) * mix(color, color * vec4(1.8, 1.4, 1.0, 1.0), 1.0 - luma(color.rgb));
	#elif (COLOR_LENS == 1)
	vec4 albedo = texture2D(texture, texcoord) * mix(color, color * vec4(1.0, 1.1, 1.2, 1.0), 1.0 - luma(color.rgb));
	#elif (COLOR_LENS == 2)
	vec4 albedo = texture2D(texture, texcoord) * mix(color, color * vec4(1.0, 1.0, 1.0, 1.0), 1.0 - luma(color.rgb));
	#endif

	vec4 baseColor = albedo;
	vec3 newNormal = hand? normal.rgb : getNormals(texcoord);

	float NdotL = clamp(dot(newNormal, normalize(shadowLightPosition)), 0.0, 1.0);
	float NdotL2 = clamp(dot(newNormal, normalize(-shadowLightPosition)), 0.0, 1.0);
	float NdotUp = clamp(dot(newNormal, normalize(upPosition)), 0.0, 1.0);

	vec3 fragposition = toNDC(vec3(gl_FragCoord.xy / vec2(viewWidth,viewHeight), hand? gl_FragCoord.z + 0.38 : gl_FragCoord.z));

	#include "lib/colors.glsl"



	const float ambientStrength = 0.53 + ((AS - 0.5) * 2);
	const float skyLight = 0.2;
	const float sunlightStrength = 0.9 + ((SS - 0.5) * 2);


	float shading = calcShadows(fragposition.xyz, NdotL, translucent);
	float minLight = 0.005 + screenBrightness * 0.03;

	if (isEyeInWater == 1) shading *= lmcoord.y;

	#define DIST_DARK 0 // [0 1]
	#if (DIST_DARK == 0)
	float dist = 1.0;
	#elif (DIST_DARK == 1)
	float dist = exp(-pow(length(fragposition.xyz) * 0.005, 1.5));
	#endif
	float smoothLighting = 0.3 + color.a * 0.7;

	#ifdef AMBIENT_OCCLUSION
		smoothLighting = 0.7 + color.a * 0.3;
	#endif

	vec3 ambientLightmap = (minLight + ambientColor * ambientStrength * dist * mix(lmcoord.y, 1.0, min(nightVision + shading, 1.0)) * (1.0 + NdotUp * skyLight)) * smoothLighting + (shading * (sunlightStrength + subsurfaceScattering(fragposition.xyz, translucent)) + bouncedLight(newNormal, lmcoord.y)) * sunColor;
			 ambientLightmap *= 1.0 - smoothstep(0.9, 0.95, lmcoord.y) * rainStrength * 0.2;
			 ambientLightmap += getTorchLightmap(newNormal, lmcoord.x, lmcoord.y, translucent) * torchColor;
			 ambientLightmap = emissiveLight(ambientLightmap, baseColor.rgb * torchColor, emissive);

	baseColor.rgb = lowlightEye(baseColor.rgb, ambientLightmap);
	baseColor.rgb *= ambientLightmap;

	if (isEyeInWater == 1) {

		baseColor.rgb *= mix(vec3(1.0), mix(waterColor * ambientColor, vec3(0.0, 1.0, 1.0), pow(max(lmcoord.y, 0.0), 1.5)), (1.0 - pow(lmcoord.y, 4.0)) * (1.0 - lmcoord.x));

	}


/* DRAWBUFFERS:0124 */

  gl_FragData[0] = baseColor;
  gl_FragData[1] = vec4(encodeLightmap(lmcoord), encodeNormal(newNormal), normal.a);
	gl_FragData[3] = vec4(albedo.rgb, shading);

	#ifdef PBR
		gl_FragData[2] = vec4(hand? vec3(0.0) : PBRData(), 1.0);
	#endif

}
