shader_type canvas_item;
// Preserve the authored silhouettes, alpha, skin and movement; recolour cool fabric/hair.
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float cool = smoothstep(0.015, 0.07, c.b - c.r) * smoothstep(0.005, 0.04, c.b - c.g);
	float light = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 copper = vec3(0.98, 0.61, 0.31) * light * 1.42;
	c.rgb = mix(c.rgb, copper, cool * 0.96);
	COLOR = c;
}
