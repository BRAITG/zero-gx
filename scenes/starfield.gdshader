shader_type canvas_item;
render_mode unshaded;

uniform vec2 streak = vec2(0.0);
varying vec2 offset;
varying flat float radius;

void vertex() {
	radius = INSTANCE_CUSTOM.x;
	// Keep the quad and its antialiasing fringe around the head and either tail direction.
	offset = VERTEX * (vec2(radius + 1.0) + abs(streak) * 0.5) + streak * 0.5;
	VERTEX = offset;
}

void fragment() {
	float aa = max(length(fwidth(offset)) * 0.5, 0.001);
	float head = 1.0 - smoothstep(radius - aa, radius + aa, length(offset));
	float tail = 0.0;
	float length_squared = dot(streak, streak);
	// A moving ship smears each star back along the track it came from.
	if (length_squared >= 0.25) {
		float along = clamp(dot(offset, streak) / length_squared, 0.0, 1.0);
		float distance = length(offset - along * streak);
		tail = (1.0 - smoothstep(radius - aa, radius + aa, distance)) * (1.0 - along);
	}
	float head_alpha = COLOR.a * head;
	float tail_alpha = COLOR.a * tail;
	COLOR.a = tail_alpha + head_alpha * (1.0 - tail_alpha);
}
