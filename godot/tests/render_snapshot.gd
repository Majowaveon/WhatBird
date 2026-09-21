extends SceneTree
## Renders every original room to PNG for pixel comparisons between renderers.
## Usage: godot --headless --path godot --script res://tests/render_snapshot.gd -- --snap-dir=<dir>

const ROOMS: Array[String] = [
	"sublevel_w0l1", "sublevel_w0l2", "sublevel_w0l3", "sublevel_w0l4", "sublevel_w0l5", "sublevel_w0l6",
	"sublevel_w1l1", "sublevel_w1l2", "sublevel_w1l3", "sublevel_w1l4", "sublevel_w1l5", "sublevel_w1l6", "sublevel_w1l7",
	"sublevel_w2l1", "sublevel_w2l2", "sublevel_w2l3", "sublevel_w2l4", "sublevel_w2l5", "sublevel_w2l6", "sublevel_w2l7",
]

var main: Node
var world: HeronWorld

func _initialize() -> void:
	call_deferred("_run")

func _dir() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--snap-dir="):
			return argument.substr("--snap-dir=".length())
	push_error("Missing --snap-dir argument")
	quit(1)
	return ""

func _hide_dynamic(root: Node) -> void:
	for node: Node in root.find_children("*", "HeronWorldObject", true, false):
		node.visible = false
	for node: Node in root.find_children("*", "HeronWaterSurface", true, false):
		node.visible = false
	for node: Node in root.find_children("*", "HeronTransformEffect", true, false):
		node.visible = false

func _run() -> void:
	var target: String = _dir()
	if target.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(target)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	await physics_frame
	world.player.sprite.visible = false
	main.ui.visible = false
	_hide_dynamic(world)
	await physics_frame
	for room: String in ROOMS:
		if not world.rooms.has(room):
			push_error("Missing room in snapshot run: " + room)
			continue
		world.change_room(room, true)
		await physics_frame
		await process_frame
		await process_frame
		var image: Image = root.get_texture().get_image()
		image.save_png(target.path_join(room + ".png"))
		print("SNAPSHOT ", room, " ", image.get_size())
	main.audio.shutdown()
	await create_timer(0.2).timeout
	main.queue_free()
	await create_timer(0.5).timeout
	world = null
	main = null
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	await process_frame
	quit(0)
