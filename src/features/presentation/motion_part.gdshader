shader_type canvas_item;
uniform vec2 grid = vec2(5.0, 7.0);
uniform float waist = 0.75;
uniform float crown = 0.5;
uniform int part = 0;
void fragment() {
	vec2 cell = fract(UV * grid);
	if ((part == 0 && cell.y < waist) || (part == 1 && cell.y >= waist)
			|| (part == 2 && cell.y >= crown)) { COLOR.a = 0.0; }
}
