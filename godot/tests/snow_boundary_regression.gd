extends SceneTree

var checks: Array[String] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	var world: HeronWorld = main.world
	var snow: HeronEditableRoom = world.rooms["sublevel_w3l1"]["node"]
	var clip_shader: Shader = load("res://scripts/room_foreground.gdshader")
	for tag: String in ["sublevel_w2l7", "sublevel_w0l1"]:
		var room: HeronEditableRoom = world.rooms[tag]["node"]
		var bounds: Rect2 = room.world_bounds()
		_check(not bounds.intersects(snow.world_bounds()), tag + ": decorative clipping boundary stays outside snow")
		for group: String in ["Background", "Foreground"]:
			var scenery: Node = room.get_node(group)
			var layers: Array[Node] = scenery.find_children("*", "TileMapLayer", true, false)
			_check(not layers.is_empty(), tag + " " + group + ": checks actual authored artwork")
			for layer: TileMapLayer in layers:
				var material: ShaderMaterial = layer.material as ShaderMaterial
				_check(material != null and material.shader == clip_shader, tag + " " + group + ": artwork uses room clipping")
				if material != null:
					var expected := Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)
					_check(material.get_shader_parameter("room_bounds") == expected, tag + " " + group + ": clip uses transformed world bounds")
	var forest: HeronEditableRoom = world.rooms["sublevel_w2l7"]["node"]
	var sign: Label = forest.get_node("Actors/SnowTrailSign")
	var sign_bounds: Rect2 = sign.get_global_rect().grow(float(sign.get_theme_constant("outline_size")))
	_check(forest.world_bounds().encloses(sign_bounds), "Forest sign including its outline stays inside the forest")
	_check(not sign_bounds.intersects(snow.world_bounds()), "Forest sign cannot enter the snow viewport")
	var transition: HeronWorldObject = forest.get_node("Actors/EnterSnowChapter")
	_check(transition.target_room == "SubLevel_w3l1", "Forest transition still leads to the snow encounter")
	_check(transition.material == null and forest.get_node("Actors").material == null, "Cross-room gameplay triggers are not clipped")
	main.audio.shutdown()
	main.queue_free()
	await create_timer(0.3).timeout
	print("HERON_SNOW_BOUNDARY_REGRESSION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "coverage": "Runtime scene materials, transformed clipping bounds, forest sign and transition configuration; no rendered-image verification."}))
	quit(0 if failures.is_empty() else 1)
