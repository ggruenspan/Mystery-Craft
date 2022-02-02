#version 120

varying vec2 texcoord;

uniform sampler2D colortex0;  // color

/* OptiFine constants
const int colortex0Format = R11F_G11F_B10F;
const int colortex1Format = RGBA16;
const int colortex4Format = RGBA16;
const bool colortex0Clear = false;
const bool colortex1Clear = false;
const bool colortex2Clear = true;
const bool colortex3Clear = false;
const bool colortex4Clear = true;
const bool colortex5Clear = false;
const bool colortex6Clear = false;
const bool colortex7Clear = true;
*/


const int	noiseTextureResolution = 1;

void main() {

  vec3 color = texture2D(colortex0, texcoord).rgb;


/* DRAWBUFFERS:4 */

  gl_FragData[0] = vec4(color, 1.0);

}
