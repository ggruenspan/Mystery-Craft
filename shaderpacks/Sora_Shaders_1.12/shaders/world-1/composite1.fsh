#version 120

//#define DISTANCE_BLUR

varying vec2 texcoord;

uniform sampler2D colortex1;
uniform sampler2D colortex7;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform vec3 sunPosition;
uniform vec3 moonPosition;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform int worldTime;
uniform int isEyeInWater;

uniform ivec2 eyeBrightness;

uniform float near;
uniform float far;
uniform float sunAngle;
uniform float rainStrength;

#include "lib/timeArray.glsl"

float luma(vec3 clr) {
	return dot(clr, vec3(0.3333));
}

vec3 underwaterFog(vec3 fragpos, vec3 color, vec3 waterColor) {

  float fogFactor = 1.0 - exp(-pow(length(fragpos) * 0.03, 1.0));

  return mix(color, waterColor * vec3(0.6, 1.0, 0.8) * 0.2, fogFactor);

}

float distanceBlur(vec3 fragpos) {

  return 1.0 - exp(-pow(length(fragpos.xyz) * 0.005, 2.0));

}


void main() {

  // x = 0; y = 1
	vec2 depth = vec2(texture2D(depthtex0, texcoord).x, texture2D(depthtex1, texcoord).x);

  float mat = texture2D(colortex1, texcoord).a;


  vec4 fragposition0  = gbufferProjectionInverse * (vec4(texcoord.st, depth.x, 1.0) * 2.0 - 1.0);
	     fragposition0 /= fragposition0.w;

	vec4 fragposition1  = gbufferProjectionInverse * (vec4(texcoord.st, depth.y, 1.0) * 2.0 - 1.0);
	     fragposition1 /= fragposition1.w;

  float comp = 1.0 - near / far / far;

  bool sky = depth.y > comp;
  bool land = depth.y < comp;

  bool water = mat > 0.09 && mat < 0.11;
	bool gbuffers_water = mat > 0.09 && mat < 0.2;

  vec3 color = vec3(0.0);
  #ifdef DISTANCE_BLUR
		const bool colortex4MipmapEnabled = true;
   	color = texture2DLod(colortex4, texcoord, distanceBlur(fragposition1.xyz)).rgb;
  #else
   	color = texture2D(colortex4, texcoord).rgb;
  #endif


	vec4 tpos = vec4(sunPosition, 1.0) * gbufferProjection;
			 tpos = vec4(tpos.xyz / tpos.w, 1.0);
	vec2 pos = tpos.xy / tpos.z;
	vec2 lightPos = pos * 0.5 + 0.5;

  #include "lib/colors.glsl"

	// Render fog on top of gbuffers_water
	if (gbuffers_water)  {
	  if (isEyeInWater == 1) color = underwaterFog(fragposition0.xyz, color, waterColor * ambientColor);
	}

/* DRAWBUFFERS:4 */

  gl_FragData[0] = vec4(color, float(texture2D(depthtex1, lightPos).x > comp));

}
