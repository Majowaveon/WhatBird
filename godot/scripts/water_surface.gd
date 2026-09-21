class_name HeronWaterSurface
extends Node2D

const WATER_SHADER := """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float mirror_y = 0.78;
uniform float opacity = 1.0;
uniform float water_time = 0.0;
uniform vec2 world_pixel_scale = vec2(1.0);
uniform float ripple_strength : hint_range(0.0, 1.0) = 1.0;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.6;
varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float depth = clamp((SCREEN_UV.y - mirror_y) / (1.0 - mirror_y), 0.0, 1.0);
	vec2 grid = floor(world_position);
	float row = grid.y;
	float wave = sin(row * 0.55 + water_time * 1.6) + 0.5 * sin(row * 0.17 - water_time * 1.1);
	float offset = round(wave * 1.5) * world_pixel_scale.x * SCREEN_PIXEL_SIZE.x * ripple_strength;
	vec2 sample_uv = vec2(SCREEN_UV.x + offset, 2.0 * mirror_y - SCREEN_UV.y);
	sample_uv = clamp(sample_uv, SCREEN_PIXEL_SIZE, vec2(1.0 - SCREEN_PIXEL_SIZE.x, max(SCREEN_PIXEL_SIZE.y, mirror_y - SCREEN_PIXEL_SIZE.y)));
	vec3 reflection = texture(screen_texture, sample_uv).rgb * vec3(0.72, 0.9, 0.95);
	vec3 water_color = mix(vec3(0.35, 0.57, 0.61), vec3(0.16, 0.35, 0.39), depth);
	float fade = pow(1.0 - depth, 1.4);
	vec3 rgb = mix(water_color, reflection, 0.72 * fade);
	float drift = floor(water_time * 0.8 + sin(grid.y * 0.22 + water_time * 0.6) * 1.5);
	vec2 streak_grid = vec2(grid.x + drift, grid.y);
	vec2 cell = floor(streak_grid / vec2(11.0, 4.0));
	vec2 within = mod(streak_grid, vec2(11.0, 4.0));
	float seed = hash(cell);
	float length = 2.0 + floor(seed * 5.0);
	float start = floor(hash(cell + vec2(3.0, 1.0)) * (10.0 - length));
	float stripe = step(start, within.x) * (1.0 - step(start + length, within.x));
	stripe *= 1.0 - step(1.0, abs(within.y - floor(hash(cell + vec2(7.0)) * 4.0)));
	float pulse = smoothstep(0.35, 0.95, sin(water_time * (1.0 + seed) + seed * 37.0));
	float glint = stripe * step(0.54, seed) * pulse;
	float shimmer = smoothstep(0.975, 1.0, sin(grid.y * 0.42 + grid.x * 0.025 + water_time * 0.8)) * 0.045;
	rgb += vec3(0.48, 0.88, 0.77) * (glint * highlight_strength + shimmer) * (1.0 - depth * 0.55);
	float shore = smoothstep(0.0, 0.035, depth);
	COLOR = vec4(rgb, opacity * shore * mix(0.86, 0.96, depth));
}
"""

var surface: Polygon2D
var water_material: ShaderMaterial
var waterline: float = 0.78
var opacity: float = 0.0
var water_time: float = 0.0
var transition: Tween

func _ready() -> void:
	# Capture the world and player (z 4) before the foreground reeds (z 6 and above).
	z_index = 5
	visible = false
	var copy := BackBufferCopy.new()
	copy.name = "SceneCopy"
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	surface = Polygon2D.new()
	surface.name = "Reflection"
	add_child(surface)
	var shader := Shader.new()
	shader.code = WATER_SHADER
	water_material = ShaderMaterial.new()
	water_material.shader = shader
	surface.material = water_material
	RenderingServer.frame_pre_draw.connect(_update_surface)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_update_surface):
		RenderingServer.frame_pre_draw.disconnect(_update_surface)

func set_room(enabled: bool, line_ratio: float, instant: bool = false) -> void:
	if transition and transition.is_valid():
		transition.kill()
	var target_line: float = clampf(line_ratio, 0.5, 0.95)
	var target_opacity: float = 1.0 if enabled else 0.0
	if instant:
		waterline = target_line
		opacity = target_opacity
		visible = enabled
		return
	if enabled and not visible:
		waterline = target_line
		visible = true
	transition = create_tween().set_parallel(true)
	transition.tween_property(self, "opacity", target_opacity, 0.3)
	if enabled:
		transition.tween_property(self, "waterline", target_line, 0.3)
	else:
		transition.chain().tween_callback(hide)

func _process(delta: float) -> void:
	if not visible:
		return
	water_time += delta
	water_material.set_shader_parameter("water_time", water_time)
	_update_surface()

func _update_surface() -> void:
	if not is_inside_tree() or not visible:
		return
	var size: Vector2 = get_viewport_rect().size
	var top: float = size.y * waterline
	# The camera tween runs after _process; resync immediately before drawing as well.
	var to_local: Transform2D = surface.get_global_transform_with_canvas().affine_inverse()
	surface.polygon = to_local * PackedVector2Array([
		Vector2(0, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(0, size.y)
	])
	var canvas: Transform2D = get_viewport_transform()
	water_material.set_shader_parameter("world_pixel_scale", Vector2(canvas.x.length(), canvas.y.length()))
	water_material.set_shader_parameter("mirror_y", waterline)
	water_material.set_shader_parameter("opacity", opacity)
