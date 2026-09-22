extends SceneTree
## Use -- --render with a real window to check seams and the mallard pool obstruction.

var main: Node
var world: HeronWorld
var checks: int = 0
var failures: Array[String] = []
var foreground_colors: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _remember_foregrounds() -> void:
	foreground_colors.clear()
	for tag: String in world.rooms:
		var foreground: Node2D = world.rooms[tag]["node"].get_node_or_null("Foreground") as Node2D
		if foreground:
			foreground_colors[tag] = foreground.modulate

func _foregrounds_unchanged() -> bool:
	for tag: String in foreground_colors:
		var foreground: Node2D = world.rooms[tag]["node"].get_node("Foreground") as Node2D
		if not foreground.visible or not foreground.modulate.is_equal_approx(foreground_colors[tag]):
			return false
	return true

func _scenery(room: Node, group: String) -> Node2D:
	var container: Node = room.get_node_or_null(group)
	if container:
		for node: Node in container.get_children():
			if node is Node2D and node.has_meta("original_bounds"):
				for layer: TileMapLayer in node.find_children("*", "TileMapLayer", true, false):
					if not layer.get_used_cells().is_empty():
						return node as Node2D
	return null

func _same_tiles(a: Node2D, b: Node2D) -> bool:
	var a_layers: Array[Node] = a.find_children("*", "TileMapLayer", true, false)
	var b_layers: Array[Node] = b.find_children("*", "TileMapLayer", true, false)
	if a_layers.size() != b_layers.size():
		return false
	for i: int in a_layers.size():
		var left: TileMapLayer = a_layers[i] as TileMapLayer
		var right: TileMapLayer = b_layers[i] as TileMapLayer
		if left.get_used_cells() != right.get_used_cells():
			return false
		for cell: Vector2i in left.get_used_cells():
			if left.get_cell_source_id(cell) != right.get_cell_source_id(cell) or left.get_cell_atlas_coords(cell) != right.get_cell_atlas_coords(cell) or left.get_cell_alternative_tile(cell) != right.get_cell_alternative_tile(cell):
				return false
	return true

func _check_seam_layout() -> void:
	for tag: String in world.rooms:
		var left_room: Node2D = world.rooms[tag]["node"]
		var left_rect: Rect2 = world.rooms[tag]["rect"]
		for next: String in world.rooms:
			var right_rect: Rect2 = world.rooms[next]["rect"]
			if not is_equal_approx(left_rect.end.x, right_rect.position.x) or not is_equal_approx(left_rect.position.y, right_rect.position.y):
				continue
			for group: String in ["Background", "Foreground"]:
				var a: Node2D = _scenery(left_room, group)
				var b: Node2D = _scenery(world.rooms[next]["node"], group)
				if a == null or b == null or a.get_meta("source_ref") != b.get_meta("source_ref"):
					continue
				var a_bounds: Rect2 = a.get_meta("original_bounds")
				var b_bounds: Rect2 = b.get_meta("original_bounds")
				var a_world: Rect2 = a.global_transform * a_bounds
				var b_world: Rect2 = b.global_transform * b_bounds
				var label: String = tag + " / " + next + " " + group
				_check(is_equal_approx(a_world.end.x, left_rect.end.x) and is_equal_approx(b_world.position.x, left_rect.end.x), label + ": exact shared edge")
				_check(is_equal_approx(a_world.position.y, b_world.position.y) and is_equal_approx(a_world.size.y, b_world.size.y), label + ": vertical alignment")
				_check(a.global_transform.x.is_equal_approx(-b.global_transform.x) and a.global_transform.y.is_equal_approx(b.global_transform.y), label + ": mirrored artwork")
				_check(_same_tiles(a, b), label + ": matching tile artwork")

func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _check_mallard_render() -> void:
	world.change_room("sublevel_w1l1", true)
	var neighbor: Node2D = world.rooms["sublevel_w1l2"]["node"].get_node("Foreground") as Node2D
	var actual: Image = await _capture()
	neighbor.hide()
	var isolated: Image = await _capture()
	neighbor.show()
	var layers: Array[Node] = neighbor.find_children("*", "TileMapLayer", true, false)
	var materials: Array[Material] = []
	for layer: TileMapLayer in layers:
		materials.append(layer.material)
		layer.material = null
	var leaking: Image = await _capture()
	for i: int in layers.size():
		layers[i].material = materials[i]
	var reproduced: int = 0
	var residual: int = 0
	for y: int in range(590, 720, 2):
		for x: int in range(70, 610, 2):
			if leaking.get_pixel(x, y) != isolated.get_pixel(x, y):
				reproduced += 1
			if actual.get_pixel(x, y) != isolated.get_pixel(x, y):
				residual += 1
	_check(reproduced > 1000, "Unclipped neighboring reeds reproduce the mallard pool obstruction")
	_check(residual == 0, "Opaque neighboring reeds stay out of the mallard pool")

func _check_mirrored_render(left: String, right: String, group: String) -> void:
	var visibility: Dictionary = {}
	for tag: String in world.rooms:
		var room: Node2D = world.rooms[tag]["node"]
		for child: Node in room.get_children():
			if child is CanvasItem:
				visibility[child] = child.visible
				child.visible = tag in [left, right] and String(child.name) == group
	for particles: CPUParticles2D in world.find_children("*", "CPUParticles2D", true, false):
		visibility[particles] = particles.visible
		particles.hide()
	world.change_room(left, true)
	world.foreground_water.hide()
	var left_rect: Rect2 = world.rooms[left]["rect"]
	world.camera.position.x = left_rect.end.x
	# Two screen pixels per source texel avoid nearest-filter tie breaks at fractional texel boundaries.
	world.camera.zoom = Vector2.ONE * (32.0 / 15.0)
	var image: Image = await _capture()
	var center: int = image.get_width() / 2
	var differences: int = 0
	for x: int in range(0, 160):
		for y: int in range(100, image.get_height() - 100, 2):
			if image.get_pixel(center - 1 - x, y) != image.get_pixel(center + x, y):
				differences += 1
	_check(differences == 0, left + " / " + right + " " + group + ": rendered pixels mirror across the seam (differences=" + str(differences) + ")")
	for child: CanvasItem in visibility:
		child.visible = visibility[child]

func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	world.set_physics_process(false)
	world.player.frozen = true
	world.player.collision.set_deferred("disabled", true)
	world.player.visible = false
	main.ui.visible = false
	await physics_frame
	_remember_foregrounds()
	_check_seam_layout()
	for tag: String in world.rooms:
		world.change_room(tag, true)
		_check(_foregrounds_unchanged(), tag + ": room selection preserves all foreground colors")
	for target: String in ["sublevel_w0l2", "sublevel_w0l3", "sublevel_w0l4", "sublevel_w0l6", "sublevel_w1l1"]:
		world.change_room(target)
		world.camera_tween.pause()
		for step: float in [0.12, 0.25, 0.63]:
			world.camera_tween.custom_step(step)
			await process_frame
			_check(_foregrounds_unchanged(), target + ": foreground stays opaque during camera movement")
	world.change_room("sublevel_w1l2")
	world.change_room("sublevel_w0l6")
	world.change_room("sublevel_w1l1", true)
	await create_timer(0.4).timeout
	_check(_foregrounds_unchanged(), "Rapid transitions and instant respawn preserve foreground colors")
	_check(not world.foreground_water.visible, "Mallard tutorial retains its gameplay pool without decorative foreground water")
	if "--render" in OS.get_cmdline_user_args():
		await _check_mallard_render()
		for pair: Array in [["w0l1", "w0l2"], ["w0l2", "w0l3"], ["w0l3", "w0l4"], ["w0l6", "w0l5"], ["w1l7", "w1l6"], ["w2l4", "w2l5"]]:
			for group: String in ["Background", "Foreground"]:
				await _check_mirrored_render("sublevel_" + pair[0], "sublevel_" + pair[1], group)
		if world.rooms.has("sublevel_w3l1") and world.rooms.has("sublevel_w3l2"):
			await _check_mirrored_render("sublevel_w3l1", "sublevel_w3l2", "Background")
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	ProjectSettings.set_meta("heron_scene_preview", "res://scenes/rooms/w0l2.tscn")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	world = main.world
	_remember_foregrounds()
	_check(world.rooms.size() == 1 and _foregrounds_unchanged(), "Standalone F6 preview retains the room's authored foreground")
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	ProjectSettings.remove_meta("heron_scene_preview")
	print("HERON_FOREGROUND_REGRESSION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
