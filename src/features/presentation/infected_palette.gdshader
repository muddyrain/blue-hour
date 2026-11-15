shader_type canvas_item;

void fragment() {
	vec4 ink = COLOR;
	float value = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
	// A muted grey-green silhouette also receives the world's night lighting.
	vec3 grey_green = value * vec3(0.88, 1.0, 0.92);
	COLOR = vec4(mix(ink.rgb, grey_green, 0.82) * 0.72, ink.a);
}
