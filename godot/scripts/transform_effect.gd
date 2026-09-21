class_name HeronTransformEffect
extends Node2D

var age: float = 0.0
var duration: float = 0.35

func _process(delta: float) -> void:
	age += delta
	if age >= duration:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var t: float = age / duration
	var tint := Color(0.88, 0.96, 1.0, 1.0 - t)
	for i: int in 16:
		var angle: float = TAU * i / 16.0
		var radius: float = 7.0 + 19.0 * t
		var point: Vector2 = Vector2(cos(angle), sin(angle)) * radius
		point = point.round()
		draw_rect(Rect2(point - Vector2.ONE, Vector2.ONE * 2.0), tint)
