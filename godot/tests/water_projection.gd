extends SceneTree
## Run with a rendering window: godot --path godot --script res://tests/water_projection.gd

var failures: Array[String] = []
var checks: int = 0
var scene: Node2D
var camera: Camera2D
var water: HeronWaterSurface

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _glints() -> Dictionary:
	water.water_material.set_shader_parameter("highlight_strength", 0.0)
	var plain: Image = await _capture()
	water.water_material.set_shader_parameter("highlight_strength", 0.6)
	var lit: Image = await _capture()
	var pixels: Dictionary = {}
	for y: int in range(550, 716):
		for x: int in range(40, 1240):
			if lit.get_pixel(x, y).g - plain.get_pixel(x, y).g > 0.025:
				pixels[Vector2i(x, y)] = true
	return pixels

func _overlap(first: Dictionary, second: Dictionary, shift: Vector2i) -> float:
	var shared: int = 0
	var total: int = 0
	for y: int in range(558, 678):
		for x: int in range(90, 1180):
			var point := Vector2i(x, y)
			var a: bool = first.has(point + shift)
			var b: bool = second.has(point)
			if a or b:
				total += 1
			if a and b:
				shared += 1
	return float(shared) / maxf(total, 1)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	scene = Node2D.new()
	root.add_child(scene)
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(-5000, -5000), Vector2(5000, -5000), Vector2(5000, 5000), Vector2(-5000, 5000)])
	backdrop.color = Color.BLACK
	scene.add_child(backdrop)
	camera = Camera2D.new()
	scene.add_child(camera)
	camera.force_update_scroll()
	water = HeronWaterSurface.new()
	scene.add_child(water)
	water.set_room(true, 0.75, true)
	await process_frame
	water.set_process(false)
	water.water_material.set_shader_parameter("water_time", 0.7)
	water.water_material.set_shader_parameter("ripple_strength", 0.0)
	water.water_material.set_shader_parameter("highlight_strength", 0.0)
	var marker := Polygon2D.new()
	marker.z_index = 4
	marker.color = Color.RED
	var screen_to_world: Transform2D = scene.get_global_transform_with_canvas().affine_inverse()
	marker.polygon = screen_to_world * PackedVector2Array([Vector2(480, 470), Vector2(520, 470), Vector2(520, 510), Vector2(480, 510)])
	scene.add_child(marker)
	marker.visible = false
	var baseline: Image = await _capture()
	marker.visible = true
	var reflected: Image = await _capture()
	var minimum := Vector2i(1280, 720)
	var maximum := Vector2i(-1, -1)
	for y: int in range(540, 720):
		for x: int in range(400, 600):
			if reflected.get_pixel(x, y).r - baseline.get_pixel(x, y).r > 0.025:
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	var extent: Vector2i = maximum - minimum + Vector2i.ONE
	_check(absi(extent.x - 40) <= 1 and absi(extent.y - 40) <= 1, "40px square retains width and height in its reflection: " + str(extent))
	_check(absi(minimum.y - 570) <= 1, "Reflection begins at equal distance below the waterline")
	marker.visible = false
	var original: Dictionary = await _glints()
	_check(original.size() > 200, "Fixture contains enough visible highlights")
	camera.position.x += 40
	camera.force_update_scroll()
	var horizontal: Dictionary = await _glints()
	var x_match: float = _overlap(original, horizontal, Vector2i(40, 0))
	var screen_match: float = _overlap(original, horizontal, Vector2i.ZERO)
	_check(x_match > 0.98 and x_match > screen_match + 0.5, "Highlights follow horizontal camera motion: %.3f vs stationary %.3f" % [x_match, screen_match])
	camera.position.y += 32
	camera.force_update_scroll()
	var vertical: Dictionary = await _glints()
	var y_match: float = _overlap(horizontal, vertical, Vector2i(0, 32))
	_check(y_match > 0.9, "Highlights follow vertical camera motion: %.3f" % y_match)
	water.water_material.set_shader_parameter("highlight_strength", 0.0)
	var stripes := Node2D.new()
	stripes.z_index = 4
	scene.add_child(stripes)
	screen_to_world = scene.get_global_transform_with_canvas().affine_inverse()
	for x: int in range(0, 1280, 32):
		var stripe := Polygon2D.new()
		stripe.color = Color.RED
		stripe.polygon = screen_to_world * PackedVector2Array([Vector2(x, 0), Vector2(x + 16, 0), Vector2(x + 16, 540), Vector2(x, 540)])
		stripes.add_child(stripe)
	water.water_material.set_shader_parameter("ripple_strength", 1.0)
	var rippled: Image = await _capture()
	camera.position.x += 20
	camera.force_update_scroll()
	var shifted: Image = await _capture()
	var differing: int = 0
	var samples: int = 0
	for y: int in range(554, 650):
		for x: int in range(100, 1150):
			samples += 1
			if absf(shifted.get_pixel(x, y).r - rippled.get_pixel(x + 20, y).r) > 0.02:
				differing += 1
	_check(float(differing) / samples < 0.01, "Ripple-distorted reflection moves with the scene: " + str(float(differing) / samples))
	stripes.queue_free()
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(camera, "position", Vector2(150, 70), 0.3)
	tween.tween_property(camera, "zoom", Vector2(1.3, 1.3), 0.3)
	var worst_corner_error: float = 0.0
	while tween.is_running():
		await RenderingServer.frame_post_draw
		var points: PackedVector2Array = water.surface.get_global_transform_with_canvas() * water.surface.polygon
		worst_corner_error = maxf(worst_corner_error, points[0].distance_to(Vector2(0, 540)))
		worst_corner_error = maxf(worst_corner_error, points[2].distance_to(Vector2(1280, 720)))
	_check(worst_corner_error < 0.1, "Water stays aligned during actual camera pan/zoom tween: " + str(worst_corner_error))
	scene.queue_free()
	await process_frame
	print("HERON_WATER_PROJECTION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
