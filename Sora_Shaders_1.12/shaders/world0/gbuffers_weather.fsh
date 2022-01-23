#version 120

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec3 normal;
varying vec4 color;

uniform sampler2D texture;

uniform int worldTime;
uniform float sunAngle;
uniform float rainStrength;
uniform float screenBrightness;
uniform float nightVision;
uniform float frameTimeCounter;

#include "lib/timeArray.glsl"

float luma(vec3 clr) {
	return dot(clr, vec3(0.3333));
}

float getTorchLightmap(float lightmap, float skyLightmap) {

	float tRadius = 2.5;	// Higher means lower.
	float tBrightness = 0.09;

	tBrightness *= 1.0 - (skyLightmap * (1.0 - time[5])) * 0.8;

	float torchLightmap = max(exp(pow(lightmap + 0.5, tRadius)) - 1.3, 0.0) * tBrightness;
				torchLightmap *= mix(color.a, 1.0, torchLightmap);

	return torchLightmap;

}

vec3 lowlightEye(vec3 color, vec3 ambientLightmap) {

	return mix(color, vec3(luma(color)), pow(max(1.0 - luma(ambientLightmap), 0.0), 4.0));

}

void main() {

  vec4 baseColor = texture2D(texture, texcoord) * color;
  baseColor.rgb = vec3(luma(baseColor.rgb));

	#include "lib/colors.glsl"



	float minLight = 0.03 + screenBrightness * 0.06;

	vec3 ambientLightmap = minLight + luma(ambientColor) * mix(lmcoord.y, 1.0, nightVision) + getTorchLightmap(lmcoord.x, lmcoord.y) * torchColor;

	baseColor.rgb = lowlightEye(baseColor.rgb, ambientLightmap);
	baseColor.rgb *= ambientLightmap;

/* DRAWBUFFERS:7 */

  gl_FragData[0] = baseColor;

}
