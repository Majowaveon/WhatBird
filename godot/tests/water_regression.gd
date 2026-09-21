extends SceneTree

const WET_ROOMS: Array[String] = ["w0l1", "w0l2", "w0l3", "w0l4", "w0l5", "w0l6", "w1l5", "w1l6", "w1l7"]

var failures: Array[String] = []
var checks: int = 0
var main: Node
var world: HeronWorld

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame

func _check_screen_bounds(label: String) -> void:
	var water: HeronWaterSurface = world.foreground_water
	var points: PackedVector2Array = water.surface.get_global_transform_with_canvas() * water.surface.polygon
	var size: Vector2 = world.get_viewport_rect().size
	var top: float = size.y * water.waterline
	var expected := PackedVector2Array([Vector2(0, top), Vector2(size.x, top), size, Vector2(0, size.y)])
	_check(points.size() == 4, label + ": water is a rectangle")
	for index: int in mini(points.size(), 4):
		_check(points[index].distance_to(expected[index]) < 0.1, label + ": screen corner " + str(index))

func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _check_render() -> void:
	world.change_room("sublevel_w0l1", true)
	world.player.visible = false
	main.ui.visible = false
	await _settle()
	var water: HeronWaterSurface = world.foreground_water
	water.visible = false
	var dry: Image = await _capture()
	water.visible = true
	await _settle()
	var wet: Image = await _capture()
	var changed: int = 0
	var reeds: int = 0
	var preserved_reeds: int = 0
	var reed_color := Color8(46, 79, 77)
	var size: Vector2i = wet.get_size()
	for y: int in range(int(size.y * 0.76), size.y, 3):
		for x: int in range(0, size.x, 3):
			var before: Color = dry.get_pixel(x, y)
			var after: Color = wet.get_pixel(x, y)
			if before != after:
				changed += 1
			if before == reed_color:
				reeds += 1
				if after == before:
					preserved_reeds += 1
	_check(changed > 1000, "Rendered water fills the gaps between reeds")
	_check(reeds > 1000 and preserved_reeds == reeds, "Foreground reeds remain opaque above rendered water")
	_check(dry.get_pixel(size.x / 2, size.y / 4) == wet.get_pixel(size.x / 2, size.y / 4), "Water leaves the upper screen unchanged")
	water.set_process(false)
	water.water_material.set_shader_parameter("water_time", 0.0)
	water.water_material.set_shader_parameter("highlight_strength", 0.0)
	var unlit: Image = await _capture()
	water.water_material.set_shader_parameter("highlight_strength", 0.6)
	var lit: Image = await _capture()
	water.water_material.set_shader_parameter("water_time", 1.5)
	var later: Image = await _capture()
	var lit_pixels: int = 0
	var moving_pixels: int = 0
	for y: int in range(int(size.y * water.waterline) + 6, size.y, 3):
		for x: int in range(0, size.x, 3):
			if lit.get_pixel(x, y).g > unlit.get_pixel(x, y).g + 0.05:
				lit_pixels += 1
			if lit.get_pixel(x, y) != later.get_pixel(x, y):
				moving_pixels += 1
	_check(lit_pixels > 40, "Pixel highlights visibly brighten the water")
	_check(moving_pixels > 300, "Ripples and highlights change over time")
	water.set_process(true)
	world.change_room("sublevel_w2l1", true)
	await _settle()
	var dry_room: Image = await _capture()
	water.visible = false
	var hidden: Image = await _capture()
	_check(dry_room.get_pixel(size.x / 2, int(size.y * 0.9)) == hidden.get_pixel(size.x / 2, int(size.y * 0.9)), "Dry room has no residual water overlay")

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	world.player.frozen = true
	world.player.collision.set_deferred("disabled", true)
	await physics_frame
	_check(world.find_children("*", "HeronWaterSurface", true, false).size() == 1, "Only one foreground water renderer exists")
	for tag: String in world.rooms:
		world.change_room(tag, true)
		await _settle()
		var expected_wet: bool = tag.trim_prefix("sublevel_") in WET_ROOMS
		_check(world.foreground_water.visible == expected_wet, tag + ": explicit wet/dry room setting")
		if expected_wet:
			_check_screen_bounds(tag)
	_check(world.waters.is_empty() and not world.player.in_water, "Decorative water does not create swimming triggers")
	world.change_room("sublevel_w0l1", true)
	world.camera.position += Vector2(140, -95)
	world.camera.zoom *= 0.7
	await _settle()
	_check_screen_bounds("Camera panning and zooming")
	for size: Vector2i in [Vector2i(1024, 576), Vector2i(960, 720), Vector2i(1280, 720)]:
		root.size = size
		await _settle()
		_check_screen_bounds("Resized " + str(size))
	world.change_room("sublevel_w1l1")
	await create_timer(0.4).timeout
	_check(not world.foreground_water.visible, "Water disappears after entering a dry room")
	world.change_room("sublevel_w0l2")
	await create_timer(0.4).timeout
	_check(world.foreground_water.visible and is_equal_approx(world.foreground_water.opacity, 1.0), "Water returns when entering a wet room")
	world.change_room("sublevel_w2l1")
	world.change_room("sublevel_w0l1", true)
	await create_timer(0.4).timeout
	_check(world.foreground_water.visible, "Instant respawn cancels a pending fade-out")
	var room: HeronEditableRoom = world.rooms[world.room_tag]["node"] as HeronEditableRoom
	if room:
		room.foreground_water_enabled = false
		world.change_room(world.room_tag, true)
		_check(not world.foreground_water.visible, "Scene checkbox overrides the initial wet-room configuration")
		room.foreground_water_enabled = true
		room.foreground_waterline = 0.8
		world.change_room(world.room_tag, true)
		await _settle()
		_check(is_equal_approx(world.foreground_water.waterline, 0.8), "Scene waterline setting is honored")
		_check_screen_bounds("Edited waterline")
	if room:
		room.foreground_waterline = 0.8
	if "--render" in OS.get_cmdline_user_args():
		await _check_render()
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	for preview: String in ["w0l2", "w1l1"]:
		ProjectSettings.set_meta("heron_scene_preview", "res://scenes/rooms/" + preview + ".tscn")
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await _settle()
		world = main.world
		_check(world.rooms.size() == 1 and world.scene_preview, preview + ": isolated F6 scene preview")
		_check(world.foreground_water.visible == (preview in WET_ROOMS), preview + ": F6 honors wet/dry setting")
		main.audio.shutdown()
		main.queue_free()
		await create_timer(0.3).timeout
	ProjectSettings.remove_meta("heron_scene_preview")
	print("HERON_WATER_REGRESSION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
