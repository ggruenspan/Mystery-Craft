#define FOGD 0.3  // [0.00 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.225 0.25 0.275 0.3 0.325 0.35 0.375 0.4 0.425 0.45 0.475 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
#define FOGSD 0.25  // [0.00 0.025 0.05 0.075 0.1 0.125 0.15 0.175 0.2 0.225 0.25 0.275 0.3 0.325 0.35 0.375 0.4 0.425 0.45 0.475 0.5 0.525 0.55 0.575 0.6 0.625 0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.875 0.9 0.925 0.95 0.975 1.0]
#define FOGY 0 // [ 0 1 ] 
#define FOGT 0 // [ 0 1 ]


vec3 renderFog(vec3 fragpos, vec3 color, vec3 ambientColor) {

  vec4 worldPos = gbufferModelViewInverse * vec4(fragpos, 1.0);
#if (FOGY == 0)
      float height = 1.0;
#elif (FOGY == 1)
      float height = pow(max(1.0 - ((worldPos.y + cameraPosition.y) * 2.0 - 240), 0.0), 2.0) * 0.00005;
#endif  


	    float fogDensity = (FOGD * 4) * 0.0023;
        fogDensity += fogDensity * rainStrength;
        fogDensity += height * fogDensity;

	float fogFactor = exp(-pow(length(fragpos.xyz) * fogDensity, -1.0 + (pow((FOGSD + 1), 4))));

	vec3 fogcolor = mix(ambientColor * (1.0 - rainStrength * time[5]), texture2D(colortex6, texcoord, 6.0).rgb, 1.0 - fogFactor * 0.5);

  return mix(color, fogcolor, 1.0 - fogFactor);

}
