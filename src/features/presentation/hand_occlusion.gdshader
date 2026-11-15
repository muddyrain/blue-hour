shader_type canvas_item;
uniform vec2 grid = vec2(8.0);
uniform vec2 hand_pixel = vec2(128.0, 144.0);
uniform float radius = 9.0;
void fragment() {
	vec2 pixel = fract(UV * grid) * vec2(256.0);
	COLOR.a *= 1.0 - smoothstep(radius - 1.0, radius, distance(pixel, hand_pixel));
}
