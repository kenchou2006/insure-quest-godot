shader_type canvas_item;
// Tutorial dim: deep green-black over everything, with up to four rounded "holes" that keep the
// interface element being explained bright.

uniform vec4 shade : source_color = vec4(0.016, 0.125, 0.11, 0.6);
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform int hole_count = 0;
uniform vec4 holes[4];
uniform float radius = 14.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * rect_size;
	float a = shade.a;
	for (int i = 0; i < 4; i++) {
		if (i >= hole_count) {
			break;
		}
		vec4 h = holes[i];
		vec2 c = h.xy + h.zw * 0.5;
		float d = sd_round_box(px - c, h.zw * 0.5, radius);
		a *= smoothstep(-1.0, 2.0, d);
	}
	COLOR = vec4(shade.rgb, a);
}
