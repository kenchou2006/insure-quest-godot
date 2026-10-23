shader_type canvas_item;
// Training hall backdrop: slight blur, dimmed and pulled toward the deep sea green so the UI leads.

uniform float blur_px = 2.5;
uniform float brightness : hint_range(0.0, 1.0) = 0.62;
uniform vec4 tint : source_color = vec4(0.024, 0.184, 0.165, 1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur_px;
	vec4 c = texture(TEXTURE, UV) * 0.25;
	c += texture(TEXTURE, UV + vec2(px.x, 0.0)) * 0.125;
	c += texture(TEXTURE, UV - vec2(px.x, 0.0)) * 0.125;
	c += texture(TEXTURE, UV + vec2(0.0, px.y)) * 0.125;
	c += texture(TEXTURE, UV - vec2(0.0, px.y)) * 0.125;
	c += texture(TEXTURE, UV + px) * 0.0625;
	c += texture(TEXTURE, UV - px) * 0.0625;
	c += texture(TEXTURE, UV + vec2(px.x, -px.y)) * 0.0625;
	c += texture(TEXTURE, UV + vec2(-px.x, px.y)) * 0.0625;
	COLOR = vec4(mix(c.rgb, tint.rgb, tint_mix) * brightness, 1.0);
}
