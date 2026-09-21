extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	var world: HeronWorld = main.world
	await physics_frame
	for tag: String in world.rooms:
		var room: Node2D = world.rooms[tag]["node"] as Node2D
		var background: Node2D = room.get_node_or_null("Background/BG_" + tag.trim_prefix("sublevel_")) as Node2D
		var terrain: Node2D = room.get_node_or_null("Terrain/TileMap_" + tag.trim_prefix("sublevel_")) as Node2D
		_check(background != null, tag + ": background node exists")
		_check(terrain != null, tag + ": terrain node exists")
		if not background or not terrain:
			continue
		var lowest_terrain_z: int = 100000
		for child: Node in terrain.get_children():
			if child is TileMapLayer:
				lowest_terrain_z = mini(lowest_terrain_z, child.z_index)
		_check(background.z_index < lowest_terrain_z, tag + ": background is behind every terrain layer (z=" + str(background.z_index) + ", terrain=" + str(lowest_terrain_z) + ")")
	world.change_room("sublevel_w1l1", true)
	await process_frame
	var mallard_room: Node2D = world.rooms["sublevel_w1l1"]["node"] as Node2D
	var mallard_bg: Node2D = mallard_room.get_node("Background/BG_w1l1") as Node2D
	var mallard_ground: TileMapLayer = mallard_room.get_node("Terrain/TileMap_w1l1/PaperTileLayer_0") as TileMapLayer
	_check(mallard_ground.z_index > mallard_bg.z_index, "Mallard tutorial mud is above its continuous background")
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	print("HERON_TERRAIN_REGRESSION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
