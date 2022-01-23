vec3 renderFog(vec3 fragpos, vec3 color, vec3 ambientColor) {

  float fogDensity = 0.003;
        fogDensity += fogDensity * rainStrength;

	float fogFactor = exp(-pow(length(fragpos.xyz) * fogDensity, 1.5));

	vec3 fogcolor = ambientColor * 2.0;

  return mix(color, fogcolor, 1.0 - fogFactor);

}
