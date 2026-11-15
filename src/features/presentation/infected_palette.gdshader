shader_type canvas_item;

instance uniform float night_readability : hint_range(0.0, 1.0) = 0.0;
// PROJECT_TEMP: specials have softer source contrast than the basic infected.
instance uniform float special_night_lift : hint_range(0.0, 0.5) = 0.0;
instance uniform float burst_sac_contrast : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 ink = COLOR;
	float value = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Keep the daytime grey-green; stop stacking the full palette dimmer on night tint.
	vec3 grey_green = value * vec3(0.88, 1.0, 0.92);
	float brightness = mix(0.72, 1.0, night_readability);
	vec3 palette = mix(ink.rgb, grey_green, 0.82);
	// Read the authored pigment before hit/telegraph/parent modulation changes its hue.
	vec3 source = texture(TEXTURE, UV).rgb;
	float source_value = dot(source, vec3(0.2126, 0.7152, 0.0722));
	float sacs = smoothstep(0.10, 0.24, source.r - source.b)
			* smoothstep(0.04, 0.12, source.g - source.b)
			* smoothstep(0.42, 0.62, source_value) * burst_sac_contrast;
	// Retain the drawn highlights/shadows: no flat emissive patches or extra geometry.
	palette = mix(palette, value * vec3(1.18, 1.22, 0.82), sacs);
	// Only relax special midtones at night; keep black ink and all daylight values.
	float detail_gain = min(1.65, pow(max(source_value, 0.10), -night_readability * special_night_lift));
	COLOR = vec4(palette * brightness * detail_gain, ink.a);
}
