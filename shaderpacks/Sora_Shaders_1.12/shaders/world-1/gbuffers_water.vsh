#version 120

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 color;
varying vec4 position2;
varying vec4 worldposition;
varying vec3 tangent;
varying vec4 normal;
varying vec3 binormal;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 at_tangent;

void main() {

  color = gl_Color;
  texcoord = gl_MultiTexCoord0.st;
  lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
  normal = vec4(normalize(gl_NormalMatrix * gl_Normal), 0.15);

	vec4 position = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;

  position2 = gl_ModelViewMatrix * gl_Vertex;

  worldposition = position + vec4(cameraPosition.xyz, 0.0);

	gl_Position = gl_ProjectionMatrix * gbufferModelView * position;

  if (mc_Entity.x == 10008.0) normal.a = 0.1;
  if (mc_Entity.x == 10090.0) normal.a = 0.17;

  tangent			= normalize(gl_NormalMatrix * at_tangent.xyz );
	binormal		= normalize(gl_NormalMatrix * -cross(gl_Normal, at_tangent.xyz));

}
