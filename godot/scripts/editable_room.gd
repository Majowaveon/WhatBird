@tool
class_name HeronEditableRoom
extends Node2D

@export var room_tag: String = "SubLevel_new_room"
@export var transform_limit: int = -1
@export var camera_bounds: Rect2 = Rect2(-8, -8, 480, 272):
	set(value):
		camera_bounds = value
		queue_redraw()
@export var preview_form: int = 0
@export var show_camera_bounds: bool = true:
	set(value):
		show_camera_bounds = value
		queue_redraw()

@export_group("Foreground Water")
@export var foreground_water_enabled: bool = false
@export_range(0.5, 0.95, 0.01) var foreground_waterline: float = 0.78

func _ready() -> void:
	if not Engine.is_editor_hint() and get_parent() == get_tree().root:
		ProjectSettings.set_meta("heron_scene_preview", scene_file_path)
		_launch_preview.call_deferred()

func _launch_preview() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _draw() -> void:
	if Engine.is_editor_hint() and show_camera_bounds:
		draw_rect(camera_bounds, Color(0.1, 0.9, 0.65, 0.8), false, 1.0)

func world_bounds() -> Rect2:
	return global_transform * camera_bounds
