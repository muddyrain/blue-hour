shader_type canvas_item;
render_mode unshaded;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 edge = UV * 2.0 - 1.0;
	float vignette = smoothstep(0.20, 1.05, max(abs(edge.x), abs(edge.y)));
	// Edge framing must not erase the actor detail and warm light beneath this layer.
	COLOR = vec4(0.045, 0.035, 0.055, vignette * (0.035 + amount * 0.40));
}
