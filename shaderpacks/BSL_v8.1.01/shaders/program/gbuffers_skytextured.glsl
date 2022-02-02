/* 
BSL Shaders v8 Series by Capt Tatsu 
https://bitslablab.com 
*/ 

//Settings//
#include "/lib/settings.glsl"

//Fragment Shader///////////////////////////////////////////////////////////////////////////////////
#ifdef FSH

//Varyings//
varying vec2 texCoord;

varying vec3 upVec, sunVec;

varying vec4 color;

//Uniforms//
uniform float nightVision;
uniform float rainStrength;
uniform float timeAngle, timeBrightness;
uniform float viewWidth, viewHeight;

uniform ivec2 eyeBrightnessSmooth;

uniform mat4 gbufferProjectionInverse;

uniform sampler2D texture;
uniform sampler2D gaux1;

//Common Variables//
float eBS = eyeBrightnessSmooth.y / 240.0;
float sunVisibility  = clamp((dot( sunVec, upVec) + 0.05) * 10.0, 0.0, 1.0);
float moonVisibility = clamp((dot(-sunVec, upVec) + 0.05) * 10.0, 0.0, 1.0);

//Common Functions//
float GetLuminance(vec3 color) {
	return dot(color,vec3(0.299, 0.587, 0.114));
}

//Includes//
#include "/lib/color/dimensionColor.glsl"

//Program//
void main() {
	vec4 albedo = texture2D(texture, texCoord);

	#ifdef OVERWORLD
	albedo *= color;
	albedo.rgb = pow(albedo.rgb,vec3(2.2)) * SKYBOX_BRIGHTNESS * albedo.a;

	#if CLOUDS == 1
	if (albedo.a > 0.0) {
		float cloudAlpha = texture2D(gaux1, gl_FragCoord.xy / vec2(viewWidth, viewHeight)).r;
		float alphaMult = 1.0 - 0.6 * rainStrength;
		albedo.a *= 1.0 - cloudAlpha / (alphaMult * alphaMult);
	}
	#endif
	
	#ifdef SKY_DESATURATION
    vec3 desat = GetLuminance(albedo.rgb) * pow(lightNight,vec3(1.6)) * 4.0;
	albedo.rgb = mix(desat, albedo.rgb, sunVisibility);
	#endif
	#endif

	#ifdef END
	albedo.rgb = pow(albedo.rgb,vec3(2.2));

	#ifdef SKY_DESATURATION
	albedo.rgb = GetLuminance(albedo.rgb) * endCol.rgb;
	#endif

	albedo.rgb *= SKYBOX_BRIGHTNESS * 0.02;
	#endif

	#if ALPHA_BLEND == 0
	albedo.rgb = pow(max(albedo.rgb, vec3(0.0)), vec3(1.0 / 2.2));
	#endif
	
    /* DRAWBUFFERS:0 */
	gl_FragData[0] = albedo;
}

#endif

//Vertex Shader/////////////////////////////////////////////////////////////////////////////////////
#ifdef VSH

//Varyings//
varying vec2 texCoord;

varying vec3 sunVec, upVec;

varying vec4 color;

//Uniforms//
uniform float timeAngle;

uniform mat4 gbufferModelView;

#ifdef TAA
uniform int frameCounter;

uniform float viewWidth;
uniform float viewHeight;
#include "/lib/util/jitter.glsl"
#endif

//Program//
void main() {
	texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	color = gl_Color;
	
	const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
	float ang = fract(timeAngle - 0.25);
	ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
	sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

	upVec = normalize(gbufferModelView[1].xyz);
	
	gl_Position = ftransform();
	
	#ifdef TAA
	gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
	#endif
}

#endif