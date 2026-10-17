shader_type canvas_item;
// Training file cover opening on its left hinge: the free (right) edge swings toward the viewer,
// so it moves left (cos) and grows taller (perspective). open_amount 0 = closed, 1 = fully open.

uniform float open_amount = 0.0;
uniform float max_angle = 0.38; // about 22 degrees
uniform vec2 rect_size = vec2(220.0, 290.0);

void vertex() {
	float a = open_amount * max_angle;
	float t = clamp(VERTEX.x / max(rect_size.x, 1.0), 0.0, 1.0);
	float grow = 1.0 + t * sin(a) * 0.3;
	VERTEX = vec2(VERTEX.x * cos(a), (VERTEX.y - rect_size.y * 0.5) * grow + rect_size.y * 0.5);
}
