#version 120

//#define DISTANCE_BLUR
#define GODRAYS
//#define RAINDROP_REFRACTION

varying vec2 texcoord;

uniform sampler2D colortex1;
uniform sampler2D colortex7;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform vec3 sunPosition;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform int worldTime;
uniform int isEyeInWater;

uniform ivec2 eyeBrightness;

uniform float near;
uniform float far;
uniform float sunAngle;
uniform float rainStrength;
uniform float nightVision;
uniform float blindness;

#include "lib/timeArray.glsl"


#ifdef GODRAYS

	vec3 renderGodrays(vec3 fragpos, vec2 lPos, vec3 color, vec3 sunColor) {

		const int	godraysSamples = 14;

		float grSample = 0.0;

		vec2 grCoord = texcoord.st;
		vec2 deltaTextCoord	 = texcoord.st - lPos.xy;
			 	 deltaTextCoord	/= float(godraysSamples);

		float sunVector = max(dot(normalize(fragpos), normalize(sunPosition)), 0.0);
		float sun	= pow(sunVector, 12.0) * (1.0 - time[6]);

	  float moonVector = max(dot(normalize(fragpos), normalize(-sunPosition)), 0.0);
		float moon	= pow(moonVector, 12.0) * time[5];

		for (int i = 0; i < godraysSamples; i++) {

			grCoord	-= deltaTextCoord * 0.7;
	    grSample += texture2D(colortex4, grCoord).a;

		}

		grSample /= float(godraysSamples);

		if (isEyeInWater == 1) grSample *= eyeBrightness.y / 240.0;

		return color + sunColor * grSample * (sun + moon) * 0.4;

	}

#endif

vec3 underwaterFog(vec3 fragpos, vec3 color, vec3 waterColor) {

  float fogFactor = 1.0 - exp(-pow(length(fragpos) * 0.03, 1.0));

  return mix(color, waterColor * vec3(0.6, 1.0, 0.8) * 0.2, fogFactor);

}

vec3 blindnessFog(vec3 fragpos, vec3 color) {

  float fogFactor = 1.0 - exp(-pow(length(fragpos) * 0.4, 1.0));

  return color * (1.0 - blindness * fogFactor);

}

#ifdef DISTANCE_BLUR

	vec3 distanceBlur(vec2 coord, vec3 fragpos) {

		const bool colortex4MipmapEnabled = true;

		float depth = 1.0 - exp(-pow(length(fragpos.xyz) * 0.005, 2.0));

	  return texture2DLod(colortex4, coord, depth).rgb;

	}

#endif

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

	bool hand = depth.x < 0.56;

  bool water = mat > 0.09 && mat < 0.11;
	bool gbuffers_water = mat > 0.09 && mat < 0.2;

	vec4 raindrops = texture2D(colortex7, texcoord);
	vec2 refraction = vec2(0.0);

	#ifdef RAINDROP_REFRACTION
		refraction = vec2(0.0, 0.015 * raindrops.a);
	#endif

  vec3 color = texture2D(colortex4, texcoord + refraction).rgb;

  #ifdef DISTANCE_BLUR
   	color = distanceBlur(texcoord + refraction, fragposition1.xyz);
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

	#ifdef GODRAYS
		color = renderGodrays(fragposition1.xyz, lightPos, color, sunColor);
	#endif

	if (!hand) color += raindrops.rgb * 0.2;

	color = blindnessFog(fragposition1.xyz, color);

/* DRAWBUFFERS:4 */

  gl_FragData[0] = vec4(color, float(texture2D(depthtex1, lightPos).x > comp));

}
