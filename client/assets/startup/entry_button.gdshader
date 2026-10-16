shader_type canvas_item;
render_mode unshaded;

uniform vec2 button_size = vec2(480.0, 100.0);
uniform float highlight = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * button_size;
	float radius = button_size.y * 0.29;
	vec2 q = abs(p) - (button_size * 0.5 - vec2(radius + 2.0));
	float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float inward = -edge;
	vec3 green = mix(vec3(0.005, 0.16, 0.13), vec3(0.02, 0.55, 0.36), pow(1.0 - UV.y, 2.0));
	float sweep = 1.0 - smoothstep(0.0, 0.012, abs(UV.y - (0.88 - 0.5 * UV.x + 0.08 * sin(UV.x * 6.0))));
	green += vec3(0.015, 0.10, 0.075) * sweep;
	float shine = exp(-UV.y * 17.0) * 0.22;
	green += vec3(0.25, 0.65, 0.45) * shine + vec3(highlight * 0.055);
	vec3 gold = mix(vec3(0.48, 0.28, 0.07), vec3(1.0, 0.88, 0.53), 0.5 + 0.5 * cos(UV.y * 9.0));
	vec3 color = green;
	if (inward < 2.5) { color = gold; }
	else if (inward < 4.5) { color = vec3(0.015, 0.14, 0.12); }
	else if (inward < 6.0) { color = vec3(0.91, 0.95, 0.73); }
	COLOR = vec4(color, 1.0 - smoothstep(-0.7, 0.7, edge));
}
