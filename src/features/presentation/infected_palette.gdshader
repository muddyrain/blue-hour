shader_type canvas_item;

instance uniform float night_readability : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 ink = COLOR;
	float value = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Keep the daytime grey-green; stop stacking the full palette dimmer on night tint.
	vec3 grey_green = value * vec3(0.88, 1.0, 0.92);
	float brightness = mix(0.72, 1.0, night_readability);
	COLOR = vec4(mix(ink.rgb, grey_green, 0.82) * brightness, ink.a);
}
