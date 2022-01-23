#version 120

varying vec4 color;

void main() {

  vec4 baseColor = color;

/* DRAWBUFFERS:0 */

  gl_FragData[0] = baseColor;

}
