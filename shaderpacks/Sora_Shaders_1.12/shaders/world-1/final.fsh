#version 120
#extension GL_ARB_shader_texture_lod : enable

#define TONEMAPPING		// Disable it, when you want to keep the originals colors.
	#define SATURATION 1.0		// [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define EXPOSURE 1.0		// [0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
	#define CONTRAST 1.0		// [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]
//#define CHROMATIC_ABERRATION
//#define VIGNETTE
#define LENS_FLARE

varying vec2 texcoord;

uniform sampler2D colortex4;

uniform mat4 gbufferProjection;

uniform vec3 sunPosition;

uniform int worldTime;

uniform ivec2 eyeBrightness;

uniform float aspectRatio;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;

float luma(vec3 clr) {
	return dot(clr, vec3(0.3333));
}

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

#ifdef VIGNETTE

	vec3 vignette(vec3 color) {

		float vignetteStrength	= 1.0;
		float vignetteSharpness	= 3.0;

		float dist = 1.0 - pow(distance(texcoord.st, vec2(0.5)), vignetteSharpness) * vignetteStrength;

		return color * dist;

	}

#endif

#ifdef CHROMATIC_ABERRATION

	vec3 doChromaticAberration(vec3 clr, vec2 coord) {

		const float offsetMultiplier	= 0.004;

			float dist = pow(distance(coord.st, vec2(0.5)), 2.5);

			float rChannel = texture2D(colortex4, coord.st + vec2(offsetMultiplier * dist, 0.0)).r;
			float gChannel = texture2D(colortex4, coord.st).g;
			float bChannel = texture2D(colortex4, coord.st - vec2(offsetMultiplier * dist, 0.0)).b;

			clr = vec3(rChannel, gChannel, bChannel);

		return clr;

	}

#endif


void main() {

  vec3 color = texture2D(colortex4, texcoord).rgb;

	#ifdef CHROMATIC_ABERRATION
		color = doChromaticAberration(color, texcoord);
	#endif

	#ifdef TONEMAPPING
		color = tonemapping(color);
	#endif

	#ifdef VIGNETTE
		color = vignette(color);
	#endif

	color += ditherGradNoise() / 255.0;

  gl_FragColor = vec4(color, 1.0);

}
