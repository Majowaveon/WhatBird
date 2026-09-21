@tool
class_name HeronEditableMap
extends Node2D

@export var initial_room_tag: String = "SubLevel_w0l1"
@export var preview_form: int = 0

func _ready() -> void:
	if not Engine.is_editor_hint() and get_parent() == get_tree().root:
		ProjectSettings.set_meta("heron_scene_preview", scene_file_path)
		_launch_preview.call_deferred()

func _launch_preview() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
