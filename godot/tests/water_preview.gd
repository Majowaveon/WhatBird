extends SceneTree
## Requires a rendering window; --headless cannot validate the screen-texture shader.
## Usage: godot --path godot --script res://tests/water_preview.gd -- --rooms=w0l1,w0l4 --snap-dir=<dir>

var main: Node
var world: HeronWorld

func _initialize() -> void:
	call_deferred("_run")

func _option(key: String, fallback: String = "") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="):
			return argument.substr(key.length() + 1)
	return fallback

func _run() -> void:
	var target: String = _option("--shot")
	var directory: String = _option("--snap-dir")
	if target.is_empty() and directory.is_empty():
		push_error("Pass --shot=<png> or --snap-dir=<directory>")
		quit(1)
		return
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	var dimensions: PackedStringArray = _option("--size", "1280x720").split("x")
	root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	world.player.frozen = true
	world.player.collision.set_deferred("disabled", true)
	world.player.visible = "--hide-player" not in OS.get_cmdline_user_args()
	main.ui.visible = false
	await physics_frame
	var failed: bool = false
	for room: String in _option("--rooms", "w0l1").split(","):
		var tag: String = "sublevel_" + room
		if not world.rooms.has(tag):
			push_error("Unknown room: " + room)
			failed = true
			continue
		world.change_room(tag, true)
		var room_node: Node2D = world.rooms[tag]["node"]
		var spawn: Marker2D = room_node.get_node_or_null("PlayerStart") as Marker2D
		world.player.global_position = spawn.global_position if spawn else world.rooms[tag]["rect"].get_center()
		if "--without-water" in OS.get_cmdline_user_args():
			for node: Node in world.find_children("*", "HeronWaterSurface", true, false):
				node.visible = false
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = directory.path_join(room + ".png") if not directory.is_empty() else target
		var image: Image = root.get_texture().get_image()
		var error: Error = image.save_png(path)
		if error != OK:
			push_error("Cannot save preview: " + path)
			failed = true
		print("WATER_PREVIEW ", room, " ", path, " ", image.get_size())
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	quit(1 if failed else 0)
