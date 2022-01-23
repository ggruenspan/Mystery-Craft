#version 120
#extension GL_EXT_gpu_shader4 : enable

//#define PBR
#define SSR_METHOD 1 // [0 1] 0 = Flipped image, 1 = Raytracer

varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

uniform vec3 sunPosition;
uniform vec3 upPosition;

uniform mat4 gbufferProjectionInverse;

uniform int isEyeInWater;
uniform int worldTime;

uniform float near;
uniform float far;
uniform float sunAngle;
uniform float rainStrength;
uniform float viewWidth;
uniform float viewHeight;

float luma(vec3 clr) {
	return dot(clr, vec3(0.3333));
}

float rand(vec2 coord) {
  return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float ditherGradNoise() {
  return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y));
}

vec2 decodeLightmap(float a) {

  int bf = int(a * 65535.0);
  return vec2(bf % 256, bf >> 8) / 255.0;

}

vec3 decodeNormal(vec2 enc) {

  vec2 fenc = enc*4-2;
  float f = dot(fenc,fenc);
  float g = sqrt(1-f/4.0);
  vec3 n;
  n.xy = fenc*g;
  n.z = 1-f/2;
  return n;

}

#include "lib/fog.glsl"

#ifdef PBR

	uniform sampler2D colortex5;
	const bool colortex5MipmapEnabled = true;

	float edepth(vec2 coord) {
		return texture2D(depthtex0, coord).z;
	}

	float ld(float depth) {
  	return (2.0 * near) / (far + near - depth * (far - near));
	}

	float getEdge(float border) {

		float pw = 1.0 / viewWidth;
		float ph = 1.0 / viewHeight;

		//edge detect
		float d = edepth(texcoord.xy);
		float dtresh = 1/(far-near)/5000.0;
		vec4 dc = vec4(d,d,d,d);
		vec4 sa = vec4(0.0);
		vec4 sb = vec4(0.0);
		sa.x = edepth(texcoord.xy + vec2(-pw,-ph)*border);
		sa.y = edepth(texcoord.xy + vec2(pw,-ph)*border);
		sa.z = edepth(texcoord.xy + vec2(-pw,0.0)*border);
		sa.w = edepth(texcoord.xy + vec2(0.0,ph)*border);

		//opposite side samples
		sb.x = edepth(texcoord.xy + vec2(pw,ph)*border);
		sb.y = edepth(texcoord.xy + vec2(-pw,ph)*border);
		sb.z = edepth(texcoord.xy + vec2(pw,0.0)*border);
		sb.w = edepth(texcoord.xy + vec2(0.0,-ph)*border);

		vec4 dd = abs(2.0* dc - sa - sb) - dtresh;
		dd = vec4(step(dd.x,0.0),step(dd.y,0.0),step(dd.z,0.0),step(dd.w,0.0));

		float e = 1.0 - clamp(dot(dd,vec4(0.5f,0.5f,0.5f,0.5f)),0.0,1.0);

		float depth_diff = clamp(1.0-pow(ld(texture2D(depthtex0, texcoord.st).r)*5.0,2.0),0.0,1.0);

		return e + (depth_diff * e);

	}

	vec3 renderPBR(vec3 fragpos, vec3 normal, vec3 color, vec3 ambientColor, vec4 albedo) {

		vec3 specular = texture2D(colortex2, texcoord).rgb;

		float roughness = specular.r;
		float metallic = specular.g;
		float specularity = specular.b;

		float dist = 1.0 + length(fragpos) * 0.1;
		float lodding = pow(roughness, 0.4) / (1.0 + exp(-pow(roughness + 0.65, 2.0) * 64.0 + 32.0));

		vec4 reflection = texture2DLod(colortex5, texcoord, (lodding * 12.0 * (0.5 + ditherGradNoise() * 0.5) * (1.0 - getEdge(6.0 * roughness))) / dist);

		vec3 reflectedVector = reflect(normalize(fragpos), normal) * 300.0;

		float normalDotEye = dot(normal.rgb, normalize(fragpos));
		float fresnel = clamp(pow(1.0 + normalDotEye + metallic, 3.0), 0.0, 1.0);

		reflection.rgb = mix(ambientColor, reflection.rgb, reflection.a);
		reflection.rgb = mix(reflection.rgb, reflection.rgb * albedo.rgb, metallic);

		return mix(color * (1.0 - metallic), reflection.rgb, fresnel * specularity);

	}

#endif

void main() {

	vec4 albedo = texture2D(colortex4, texcoord);
  vec3 color = texture2D(colortex0, texcoord).rgb;
	vec3 normal = decodeNormal(texture2D(colortex1, texcoord).yz);

	float depth = texture2D(depthtex0, texcoord).x;

  float skyLightmap = decodeLightmap(texture2D(colortex1, texcoord).x).y;

  float comp = 1.0 - near / far / far;
  bool sky = depth > comp;
  bool land = depth < comp;

  vec4 fragposition0  = gbufferProjectionInverse * (vec4(texcoord.st, depth, 1.0) * 2.0 - 1.0);
	     fragposition0 /= fragposition0.w;

  #include "lib/colors.glsl"

	#ifdef PBR
		if (land) color = renderPBR(fragposition0.xyz, normal, color, ambientColor, albedo);
	#endif

	color.rgb = renderFog(fragposition0.xyz, color.rgb, ambientColor);
	if (sky) color = ambientColor;

/* DRAWBUFFERS:045 */

  gl_FragData[0] = vec4(color, 1.0);
	gl_FragData[1] = vec4(color, 1.0);
  gl_FragData[2] = vec4(color, 1.0);

}
