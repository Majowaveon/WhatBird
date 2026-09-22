shader_type canvas_item;

uniform vec4 room_bounds;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (world_position.x < room_bounds.x || world_position.y < room_bounds.y
			|| world_position.x >= room_bounds.z || world_position.y >= room_bounds.w) {
		discard;
	}
}
