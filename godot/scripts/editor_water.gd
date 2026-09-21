@tool
class_name HeronEditorWater
extends Node2D

@export var depth_position: float = 10.0
@export var plane_width: float = 250.0:
	set(value):
		plane_width = value
		queue_redraw()
@export var plane_depth: float = 10000.0

func _draw() -> void:
	if Engine.is_editor_hint():
		draw_line(Vector2(-plane_width * 0.5, 0), Vector2(plane_width * 0.5, 0), Color(0.2, 0.65, 1), 2)
