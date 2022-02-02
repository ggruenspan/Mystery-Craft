#version 120
#extension GL_ARB_shader_texture_lod : enable

#define TONEMAPPING		// Disable it, when you want to keep the originals colors.
	#define SATURATION 1.0		// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define EXPOSURE 1.0		// [0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define CONTRAST 1.0		// [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
//#define CHROMATIC_ABERRATION
//#define VIGNETTE
#define LENS_FLARE
//#define DEPTH_OF_FIELD
//#define FILM_GRAIN
//#define CINEMATIC_MODE

varying vec2 texcoord;

uniform sampler2D colortex4;

uniform float aspectRatio;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;

float ditherGradNoise() {
  return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y));
}

#ifdef TONEMAPPING

	vec3 tonemapping(vec3 clr) {

		// Saturation
		clr = mix(clr, vec3(dot(clr, vec3(0.3333))), -SATURATION * 1.15 + 1.0);

		clr = pow(clr, vec3(2.2));

		// Contrast
		clr = pow(clr, vec3(1.1 * CONTRAST)) * CONTRAST;

		// Exposure
		clr *= 2.4 * EXPOSURE;

		clr = 1.0 - exp(-clr);
		clr = pow(clr, vec3(0.4545));

		return clr;

	}

#endif

#ifdef FILM_GRAIN

	uniform float frameTimeCounter;

	float rand(vec2 coord) {
	  return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 43758.5453);
	}

	vec3 filmgrain(vec3 color) {

		vec2 coord = texcoord + frameTimeCounter * 0.01;

		vec3 noise = vec3(0.0);
				 noise.r = rand(coord + 0.1);
				 noise.g = rand(coord);
				 noise.b = rand(coord - 0.1);

		return color * (0.95 + noise * 0.1) + noise * 0.05;

	}

#endif

#ifdef VIGNETTE

	vec3 vignette(vec3 color) {

		float vignetteStrength	= 1.0;
		float vignetteSharpness	= 3.0;

		float dist = 1.0 - pow(distance(texcoord.st, vec2(0.5)), vignetteSharpness) * vignetteStrength;

		return color * dist;

	}

#endif

#ifdef CHROMATIC_ABERRATION

	vec3 doChromaticAberration(vec2 coord) {

		const float offsetMultiplier	= 0.004;

		float dist = pow(distance(coord.st, vec2(0.5)), 2.5);

		vec3 color = vec3(0.0);

		color.r = texture2D(colortex4, coord.st + vec2(offsetMultiplier * dist, 0.0)).r;
		color.g = texture2D(colortex4, coord.st).g;
		color.b = texture2D(colortex4, coord.st - vec2(offsetMultiplier * dist, 0.0)).b;

		return color;

	}

#endif

#ifdef LENS_FLARE

	uniform mat4 gbufferProjection;
	uniform vec3 sunPosition;
	uniform ivec2 eyeBrightness;
	uniform int isEyeInWater;
	uniform int worldTime;

	#include "lib/timeArray.glsl"

	float drawCircle(float radius, float edge, float lensDist) {

		vec4 tpos = vec4(sunPosition, 1.0) * gbufferProjection;
				 tpos = vec4(tpos.xyz / tpos.w, 1.0);
		vec2 pos = tpos.xy / tpos.z * lensDist;
		vec2 lightPos = pos * 0.5 + 0.5;

		vec2 coord = (texcoord - lightPos) / radius;

		float circle = 1.0 - clamp(pow(coord.x * aspectRatio, 2.0) + pow(coord.y, 2.0), 0.0, 1.0);

		return smoothstep(0.0, 1.0 - edge, circle);

	}

	mat2 rotate2d(float angle){
	  return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
	}

	float drawHorizontal(float size, float angle, float edge, float lensDist) {

		vec4 tpos = vec4(sunPosition, 1.0) * gbufferProjection;
				 tpos = vec4(tpos.xyz / tpos.w, 1.0);
		vec2 pos = tpos.xy / tpos.z * lensDist;
		vec2 lightPos = pos * 0.5 + 0.5;

		vec2 coord = (texcoord - lightPos) * rotate2d(angle);

		return 1.0 - clamp(abs(0.0 - coord.y * 2.0 / size), 0.0, 1.0);

	}

	vec3 lensFlare(vec3 color) {

		float lensPower = 0.2;

		vec4 tpos = vec4(sunPosition, 1.0) * gbufferProjection;
				 tpos = vec4(tpos.xyz / tpos.w, 1.0);
		vec2 pos = tpos.xy / tpos.z;
		vec2 lightPos = pos * 0.5 + 0.5;

		float distof = min(clamp(1.2 - lightPos.x, 0.0, lightPos.x), clamp(1.2 - lightPos.y, 0.0, lightPos.y));
		float sunVisibility = texture2D(colortex4, vec2(0.0)).a * distof;

		lensPower *= (1.0 - time[5]) * (1.0 - time[6]) * (1.0 - rainStrength) * float(sunPosition.z < 0.0);
		if (isEyeInWater == 1) lensPower *= eyeBrightness.y / 240.0;

		vec3 flare12  = drawHorizontal(0.023, 0.6, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 += drawHorizontal(0.015, -0.3, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 += drawHorizontal(0.021, -0.6, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 += drawHorizontal(0.022, 1.0, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 += drawHorizontal(0.012, 1.3, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 += drawHorizontal(0.016, -1.3, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 += drawHorizontal(0.015, -1.5, 0.0, 1.0) * vec3(1.0, 0.7, 0.4);
				 flare12 *= drawCircle(0.3, -0.5, 1.0) * 0.25;

		float flare13 = drawCircle(0.1, 0.0, 1.0);

		vec3 flare1 = max(drawCircle(0.3, 0.8, -0.5) - drawCircle(0.3, 0.8, -0.45), 0.0) * vec3(1.0, 0.5, 0.0);
		vec3 flare2 = max(drawCircle(0.3, 0.8, -0.55) - drawCircle(0.3, 0.8, -0.5), 0.0) * vec3(0.5, 1.0, 0.5);
		vec3 flare3 = max(drawCircle(0.3, 0.8, -0.6) - drawCircle(0.3, 0.8, -0.55), 0.0) * vec3(0.2, 0.5, 1.0);

		vec3 flare10 = drawCircle(0.02, 0.3, 0.2) * drawCircle(0.02, 0.3, 0.22) * vec3(1.0, 1.0, 0.0) * 0.5;
		vec3 flare9 = drawCircle(0.04, 0.5, 0.1) * drawCircle(0.04, 0.5, 0.15) * vec3(0.3, 1.0, 0.0) * 0.5;

		vec3 flare8 = drawCircle(0.01, 0.0, -0.1) * drawCircle(0.01, 0.0, -0.11) * vec3(0.0, 1.0, 0.0);

		vec3 flare4 = drawCircle(0.007, 0.0, -0.2) * drawCircle(0.007, 0.0, -0.21) * vec3(1.0, 0.5, 0.0);

		vec3 flare11 = drawCircle(0.07, 0.7, -0.15) * drawCircle(0.07, 0.7, -0.25) * vec3(0.0, 0.6, 1.0) * 0.5;

		vec3 flare5 = max(drawCircle(0.1, 0.7, -0.3) - drawCircle(0.13, 0.3, -0.25), 0.0) * vec3(1.0, 0.5, 0.0);
		vec3 flare6 = drawCircle(0.01, 0.2, -0.4) * drawCircle(0.01, 0.2, -0.41) * vec3(0.0, 1.0, 1.0);
		vec3 flare7 = max(drawCircle(0.07, 0.7, -0.5) - drawCircle(0.1, 0.2, -0.45), 0.0) * vec3(0.2, 0.5, 1.0);

		return color + ((flare1 + flare2 + flare3 + flare4 + flare5 + flare6 + flare7 + flare8 + flare9 + flare10 + flare11) * sunVisibility + (flare12 * (1.0 - flare13)) * texture2D(colortex4, vec2(0.0)).a) * lensPower;

	}

#endif

#ifdef CINEMATIC_MODE

	vec3 blackBars(vec3 clr) {

		if (texcoord.t > 0.9 || texcoord.t < 0.1) clr.rgb = vec3(0.0);

		return clr;

	}

#endif

#ifdef DEPTH_OF_FIELD

	uniform sampler2D depthtex1;
	uniform float centerDepthSmooth;

	vec3 renderDOF(vec3 color, float depth) {

		const bool colortex4MipmapEnabled = true;
		const float blurFactor = 1.0;
		const float maxBlurFactor = 0.05;

		float focus	= depth - centerDepthSmooth;
		float factor = clamp(focus * blurFactor, -maxBlurFactor, maxBlurFactor);

		bool hand = depth < 0.56;
		if (hand) factor = 0.0;

		vec2 aspectcorrect = vec2(1.0, aspectRatio);

		vec2 offsets[4] = vec2[4](vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(0.0, -1.0));

		vec3 blurSamples = vec3(0.0);

		for (int i = 0; i < 4; i++) {

			#ifdef CHROMATIC_ABERRATION

				blurSamples.r += texture2DLod(colortex4, texcoord + (offsets[i] + vec2(0.5, 0.0)) * factor * 0.05 * aspectcorrect, abs(factor) * 60.0).r;
				blurSamples.g += texture2DLod(colortex4, texcoord + offsets[i] * factor * 0.05 * aspectcorrect, abs(factor) * 60.0).g;
				blurSamples.b += texture2DLod(colortex4, texcoord + (offsets[i] - vec2(0.5, 0.0)) * factor * 0.05 * aspectcorrect, abs(factor) * 60.0).b;

			#else

				blurSamples += texture2DLod(colortex4, texcoord + offsets[i] * factor * 0.05 * aspectcorrect, abs(factor) * 60.0).rgb;

			#endif

		}

		return blurSamples * 0.25;

	}

#endif



void main() {

  vec3 color = texture2D(colortex4, texcoord).rgb;

	#ifdef CHROMATIC_ABERRATION
		color = doChromaticAberration(texcoord);
	#endif

	#ifdef DEPTH_OF_FIELD
		color = renderDOF(color, texture2D(depthtex1, texcoord).x);
	#endif

	#ifdef FILM_GRAIN
		color = filmgrain(color);
	#endif

	#ifdef LENS_FLARE
		color = lensFlare(color);
	#endif

	#ifdef TONEMAPPING
		color = tonemapping(color);
	#endif

	#ifdef VIGNETTE
		color = vignette(color);
	#endif

	#ifdef CINEMATIC_MODE
		color = blackBars(color);
	#endif

	color += ditherGradNoise() / 255.0;

  gl_FragColor = vec4(color, 1.0);

}
