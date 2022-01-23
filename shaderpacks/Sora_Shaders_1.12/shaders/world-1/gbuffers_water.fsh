#version 120
#extension GL_EXT_gpu_shader4 : enable

#define SSR_METHOD 1 // [0 1] 0 = Flipped image, 1 = Raytracer

#define colortex6 gaux3

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 color;
varying vec4 position2;
varying vec4 worldposition;
varying vec3 tangent;
varying vec4 normal;
varying vec3 binormal;

uniform sampler2D texture;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D noisetex;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform vec3 upPosition;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;

uniform ivec2 eyeBrightness;

uniform int isEyeInWater;
uniform int worldTime;

uniform float rainStrength;
uniform float near;
uniform float far;
uniform float sunAngle;
uniform float screenBrightness;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

#include "lib/timeArray.glsl"

float luma(vec3 clr) {
	return dot(clr, vec3(0.3333));
}

float cdist(vec2 coord) {
	return max(abs(coord.s - 0.5), abs(coord.t - 0.5)) * 2.0;
}

float ditherGradNoise(){
  return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y));
}

bool material(float id) {

	if (normal.a > id - 0.01 && normal.a < id + 0.01) {
		return true;
	} else {
		return false;
	}

}

float encodeLightmap(vec2 a) {

  ivec2 bf = ivec2(a * 255.0);
  return float(bf.x | (bf.y << 8)) / 65535.0;

}

vec3 cameraSpaceToScreenSpace(vec3 fragpos) {

	vec4 pos  = gbufferProjection * vec4(fragpos, 1.0);
			 pos /= pos.w;

	return pos.xyz * 0.5 + 0.5;

}

vec3 cameraSpaceToWorldSpace(vec3 fragpos) {

	vec4 pos  = gbufferProjectionInverse * vec4(fragpos, 1.0);
			 pos /= pos.w;

	return pos.xyz;

}

mat2 rotate2d(float angle) {
  return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

vec3 toNDC(vec3 pos){
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = pos * 2. - 1.;
    vec4 fragpos = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragpos.xyz / fragpos.w;
}

float waterWaves(vec3 worldPos) {

  float wave = 0.0;

  worldPos.z += worldPos.y;
	worldPos.x += worldPos.y;

  worldPos.z *= 0.5;
  worldPos.x += sin(worldPos.x) * 0.3;

  wave  = texture2D(noisetex, worldPos.xz * 0.1 + vec2(frameTimeCounter * 0.03)).x * 0.1;
	wave += texture2D(noisetex, worldPos.xz * 0.02 - vec2(frameTimeCounter * 0.015)).x * 0.5;
	wave += texture2D(noisetex, worldPos.xz * 0.02 * rotate2d(0.5) + vec2(frameTimeCounter * 0.015)).x * 0.5;

  return wave * 0.4;

}

vec3 waterwavesToNormal(vec3 pos) {

  float deltaPos = 0.1;
	float h0 = waterWaves(pos.xyz);
	float h1 = waterWaves(pos.xyz + vec3(deltaPos, 0.0, 0.0));
	float h2 = waterWaves(pos.xyz + vec3(-deltaPos, 0.0, 0.0));
	float h3 = waterWaves(pos.xyz + vec3(0.0, 0.0, deltaPos));
	float h4 = waterWaves(pos.xyz + vec3(0.0, 0.0, -deltaPos));

	float xDelta = ((h1 - h0) + (h0 - h2)) / deltaPos;
	float yDelta = ((h3 - h0) + (h0 - h4)) / deltaPos;

	return normalize(vec3(xDelta, yDelta, 1.0 - xDelta * xDelta - yDelta * yDelta));

}

vec3 getNormals() {

	float bumpMult = 1.0;

	float NdotE = abs(dot(normal.xyz, normalize(position2.xyz)));
	bumpMult *= NdotE;

  vec3 result = normal.xyz;

  if (material(0.1) || material(0.17)) {

  	vec3 bump  = waterwavesToNormal(worldposition.xyz);
  			 bump *= vec3(bumpMult) + vec3(0.0, 0.0, 1.0 - bumpMult);

  	mat3 tbnMatrix = mat3(tangent.x, binormal.x, normal.x,
  						  					tangent.y, binormal.y, normal.y,
  						  					tangent.z, binormal.z, normal.z);

	  result = normalize(bump * tbnMatrix);

  }

  return result;

}

#include "lib/fog.glsl"

vec4 raytrace(vec3 fragpos, vec3 normal) {

	#if (SSR_METHOD == 0)

    vec3 reflectedVector = reflect(normalize(fragpos), normal) * 30.0;
    vec3 pos = cameraSpaceToScreenSpace(fragpos + reflectedVector);

    float border = clamp(1.0 - pow(cdist(pos.st), 10.0), 0.0, 1.0);

    return vec4(texture2DLod(gaux2, pos.xy, 0.0).rgb, border);

	#else

		float dither    = ditherGradNoise();

		const int samples       = 28;
		const int maxRefinement = 10;
		const float stepSize    = 1.2;
		const float stepRefine  = 0.28;
		const float stepIncrease = 1.8;

		vec3 col        = vec3(0.0);
		vec3 rayStart   = fragpos;
		vec3 rayDir     = reflect(normalize(fragpos), normal);
		vec3 rayStep    = (stepSize+dither-0.5)*rayDir;
		vec3 rayPos     = rayStart + rayStep;
		vec3 rayPrevPos = rayStart;
		vec3 rayRefine  = rayStep;

		int refine  = 0;
		vec3 pos    = vec3(0.0);
		float edge  = 0.0;

		for (int i = 0; i < samples; i++) {

			pos = cameraSpaceToScreenSpace(rayPos);

			if (pos.x<0.0 || pos.x>1.0 || pos.y<0.0 || pos.y>1.0 || pos.z<0.0 || pos.z>1.0) break;

			vec3 screenPos  = vec3(pos.xy, texture2D(depthtex1, pos.xy).x);
					 screenPos  = cameraSpaceToWorldSpace(screenPos * 2.0 - 1.0);

			float dist = distance(rayPos, screenPos);

			if (dist < pow(length(rayStep)*pow(length(rayRefine), 0.11), 1.1)*1.22) {

				refine++;
				if (refine >= maxRefinement)	break;

				rayRefine  -= rayStep;
				rayStep    *= stepRefine;

			}

			rayStep        *= stepIncrease;
			rayPrevPos      = rayPos;
			rayRefine      += rayStep;
			rayPos          = rayStart+rayRefine;

		}

		if (pos.z < 1.0-1e-5) {

			float depth = texture2D(depthtex0, pos.xy).x;

			float comp = 1.0 - near / far / far;
			bool land = depth < comp;

			if (land) {
				col = texture2D(gaux2, pos.xy).rgb;
				edge = clamp(1.0 - pow(cdist(pos.st), 10.0), 0.0, 1.0);
			}

		}

		return vec4(col, min(edge * 2.0, 1.0));

	#endif

}

vec3 waterShader(vec3 fragpos, vec3 normal, vec3 color, vec3 ambientColor) {

  vec3 reflectedVector = reflect(normalize(fragpos), normal) * 300.0;

	vec4 reflection = raytrace(fragpos, normal);

	float normalDotEye = dot(normal.rgb, normalize(fragpos));
	float fresnel = clamp(pow(1.0 + normalDotEye, 4.0) + 0.1, 0.0, 1.0);

	vec3 skyReflection = ambientColor;

	reflection.rgb = mix(skyReflection, reflection.rgb, reflection.a);

	return mix(color, reflection.rgb, fresnel);

}

float getTorchLightmap(float lightmap, float skyLightmap) {

	float tRadius = 2.5;	// Higher means lower.
	float tBrightness = 1.0;

	//tRadius *= mix(1.0, 5.0, skyLightmap * timeDay);
	tBrightness *= 1.0 - (skyLightmap * (1.0 - time[5]));

	float torchLightmap = pow(lightmap, tRadius) * tBrightness;

	return min(torchLightmap, 1.0);

}

float bouncedLight(vec3 normal, float lightmap) {

	const float bouncedLightStrength = 0.2;

	float bounce0 = max(dot(normal, -normalize(shadowLightPosition)), 0.0);
  float bounce1 = max(dot(normal, normalize(shadowLightPosition)), 0.0);
  float ground = max(dot(normal, normalize(upPosition)), 0.0);
	float light = mix(bounce0, bounce1 * (1.0 - ground), 1.0 - lightmap);

	return light * lightmap * bouncedLightStrength;

}

vec3 lowlightEye(vec3 color, float shading, float skyLightmap, float torchLightmap) {

	float desaturationAmount = 0.6;

	desaturationAmount *= 1.0 - torchLightmap;
	desaturationAmount *= pow(time[5], 2.0);

	return mix(color, vec3(luma(color)), desaturationAmount);

}

#include "lib/underwaterDepth.glsl"
#include "lib/calcUnderwaterColor.glsl"

vec3 refraction(vec3 fragpos, vec3 color, vec3 waterColor) {

	float	waterRefractionStrength = 0.1;
	float rgbOffset = 0.007;

  vec3 pos = cameraSpaceToScreenSpace(fragpos);
	vec2 waterTexcoord = pos.xy;

	waterRefractionStrength /= 1.0 + length(fragpos) * 0.4;
	rgbOffset *= waterRefractionStrength;

	vec3 waterRefract = waterwavesToNormal(worldposition.xyz);

	waterTexcoord = pos.xy + waterRefract.xy * waterRefractionStrength;

  vec3 watercolor   = vec3(0.0);
  		 watercolor.r = texture2D(gaux2, waterTexcoord.st + rgbOffset).r;
  		 watercolor.g = texture2D(gaux2, waterTexcoord.st).g;
  		 watercolor.b = texture2D(gaux2, waterTexcoord.st - rgbOffset).b;

	if (material(0.1)) color = watercolor;

	return color;

}

void main() {

  vec4 baseColor = texture2D(texture, texcoord) * color;

  bool particles = normal.r < 0.1 && normal.g < 0.1 && normal.b < 0.1;

  vec3 fragposition0 = toNDC(vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z));

  #include "lib/colors.glsl"



	float minLight = 0.03 + screenBrightness * 0.03;

	vec3 ambientLightmap = minLight + luma(ambientColor) * lmcoord.y + getTorchLightmap(lmcoord.x, lmcoord.y) * torchColor;

	baseColor.rgb = lowlightEye(baseColor.rgb, 1.0, lmcoord.y, lmcoord.x);
	baseColor.rgb *= ambientLightmap;

  if (material(0.1)) baseColor = vec4(refraction(fragposition0, baseColor.rgb, waterColor * ambientColor), 1.0);

	baseColor.rgb = renderFog(fragposition0.xyz, baseColor.rgb, ambientColor);
  baseColor.rgb = waterShader(fragposition0.xyz, getNormals(), baseColor.rgb, ambientColor);

/* DRAWBUFFERS:01 */

  gl_FragData[0] = baseColor;
  gl_FragData[1] = vec4(encodeLightmap(lmcoord), 0.0, 0.0, normal.a);

}
