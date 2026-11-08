shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D field : hint_screen_texture, filter_nearest, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 bus_foot = vec2(-10000.0);
uniform float camera_zoom = 1.0;


void fragment() {
	vec3 source = textureLod(field, SCREEN_UV, 0.0).rgb;
	float peak = max(source.r, max(source.g, source.b));
	float low = min(source.r, min(source.g, source.b));
	float chroma = peak - low;

	// Preserve warm window spill, saturated ground signals and pale foot highlights.
	float warm = smoothstep(0.015, 0.24, source.r - source.b)
		* smoothstep(0.20, 0.54, source.r);
	float signal = smoothstep(0.42, 0.78, peak) * smoothstep(0.02, 0.20, chroma);
	float pale = smoothstep(0.61, 0.91, low);
	float retained = max(0.76 * warm, max(0.66 * signal, 0.60 * pale));

	// The soft pool covers the original bus sprite and its boarding approach.
	vec2 at_bus = ((UV * viewport_size - bus_foot) / max(camera_zoom, 0.01)
		+ vec2(0.0, 30.0)) / vec2(190.0, 120.0);
	float pool = 1.0 - smoothstep(0.20, 1.0, dot(at_bus, at_bus));
	float shade = amount * (1.0 - max(retained, 0.88 * pool));
	vec3 cool = source * vec3(0.57, 0.69, 0.88) + vec3(0.007, 0.013, 0.026);
	vec3 colour = mix(source, cool, shade);
	colour += vec3(0.058, 0.038, 0.018) * amount * pool * (1.0 - 0.55 * peak);
	COLOR = vec4(colour, 1.0);
}
