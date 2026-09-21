extends SceneTree
## Use -- --render with a real window to check the mallard pool obstruction.

var main: Node
var world: HeronWorld
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _active_foregrounds_match() -> bool:
	for tag: String in world.foreground_colors:
		var node: Node2D = world.rooms[tag]["node"].get_node("Foreground") as Node2D
		var expected: Color = world.foreground_colors[tag]
		if tag != world.room_tag:
			expected.a = 0.0
		if not node.modulate.is_equal_approx(expected):
			return false
	return true

func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _check_mallard_render() -> void:
	world.change_room("sublevel_w1l1", true)
	world.player.visible = false
	main.ui.visible = false
	await process_frame
	await process_frame
	var actual: Image = await _capture()
	var neighbor: Node2D = world.rooms["sublevel_w1l2"]["node"].get_node("Foreground") as Node2D
	neighbor.hide()
	var isolated: Image = await _capture()
	neighbor.show()
	neighbor.modulate = world.foreground_colors["sublevel_w1l2"]
	var leaking: Image = await _capture()
	world.change_room("sublevel_w1l1", true)
	var reproduced: int = 0
	var residual: int = 0
	for y: int in range(590, 720, 2):
		for x: int in range(70, 610, 2):
			if leaking.get_pixel(x, y) != isolated.get_pixel(x, y):
				reproduced += 1
				if actual.get_pixel(x, y) != isolated.get_pixel(x, y):
					residual += 1
	_check(reproduced > 1000, "Neighbor foreground reproduces the reported mallard pool obstruction")
	_check(residual == 0, "Mallard pool renders exactly as with the neighboring reeds hidden")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	world.player.frozen = true
	world.player.collision.set_deferred("disabled", true)
	await physics_frame
	for tag: String in world.rooms:
		world.change_room(tag, true)
		_check(_active_foregrounds_match(), tag + ": only its own foreground is opaque")
	world.change_room("sublevel_w0l6", true)
	var previous: Node2D = world.rooms["sublevel_w0l6"]["node"].get_node("Foreground") as Node2D
	world.change_room("sublevel_w1l1")
	var fade: Tween = world.foreground_tweens["sublevel_w0l6"]
	fade.pause()
	fade.custom_step(0.12)
	_check(previous.modulate.a > 0.0 and previous.modulate.a < 1.0, "Outgoing foreground fades during the camera transition")
	fade.play()
	await create_timer(0.4).timeout
	_check(_active_foregrounds_match(), "Transition leaves no neighboring foreground behind")
	world.change_room("sublevel_w1l2")
	await create_timer(0.06).timeout
	world.change_room("sublevel_w0l6")
	await create_timer(0.06).timeout
	world.change_room("sublevel_w1l1", true)
	await create_timer(0.4).timeout
	_check(_active_foregrounds_match(), "Rapid transitions and instant respawn cancel old foreground fades")
	_check(not world.foreground_water.visible, "Mallard tutorial retains its gameplay pool without decorative foreground water")
	if "--render" in OS.get_cmdline_user_args():
		await _check_mallard_render()
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	ProjectSettings.set_meta("heron_scene_preview", "res://scenes/rooms/w1l1.tscn")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	world = main.world
	_check(world.rooms.size() == 1 and _active_foregrounds_match(), "Standalone F6 preview retains the room's own foreground state")
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	ProjectSettings.remove_meta("heron_scene_preview")
	print("HERON_FOREGROUND_REGRESSION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
