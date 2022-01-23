#version 120

varying vec2 texcoord;
varying vec4 color;

uniform sampler2D texture;
uniform sampler2D gaux4;

void main() {

  vec4 baseColor = texture2D(texture, texcoord) * color;

/* DRAWBUFFERS:0 */

  gl_FragData[0] = baseColor;

}