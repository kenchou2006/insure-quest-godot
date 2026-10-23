shader_type canvas_item;
// Soft gold-to-green radial light that follows the cursor inside a card (low alpha, no neon).
uniform vec2 center = vec2(0.5, 0.4);
uniform float radius = 0.6;
uniform float aspect = 0.7;
uniform float strength = 0.0;
uniform vec4 gold : source_color = vec4(0.776, 0.631, 0.357, 1.0);
uniform vec4 green : source_color = vec4(0.0, 0.659, 0.42, 1.0);

void fragment() {
	vec2 d = UV - center;
	d.x *= aspect;
	float g = 1.0 - smoothstep(0.0, radius, length(d));
	g = g * g;
	COLOR = vec4(mix(green.rgb, gold.rgb, g), g * strength);
}
