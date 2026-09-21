extends SceneTree

var failures: Array[String] = []
var checks: Array[String] = []
var world: HeronWorld
var main: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		checks.append(label)
	else:
		failures.append(label)
		push_error("CHECK FAILED: " + label)

func _frames(count: int) -> void:
	for i: int in count:
		await physics_frame

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	await _frames(60)
	_check(world.rooms.size() == 20, "All 20 original campaign rooms instantiated")
	_check(world.player.sprite.sprite_frames.get_animation_names().size() == 22, "Four birds have imported animation sets")
	_check(world.player.on_ground, "Original player spawn settles on real terrain")
	_check(world.room_tag == "sublevel_w0l1", "Original starting room selected")
	_check(world.player.max_transforms == 0, "Tutorial uses original zero-transform limit")
	var first_position: Vector2 = world.player.position
	Input.action_press("move_left")
	await _frames(12)
	Input.action_release("move_left")
	_check(world.player.position.x < first_position.x - 15, "Horizontal input moves over the open side of the spawn platform")
	var ground_y: float = world.player.position.y
	Input.action_press("jump")
	await _frames(4)
	Input.action_release("jump")
	_check(world.player.position.y < ground_y - 3, "Ground jump leaves terrain")
	await _frames(20)
	world.player.reset_at(first_position)
	world.player.unlock_bird(1)
	world.player.unlock_bird(2)
	world.player.unlock_bird(3)
	world.player.set_transform_limit(2)
	_check(world.player.try_transform(1), "Unlocked duck transform succeeds")
	_check(world.player.remaining_transforms == 1, "Transformation consumes one charge")
	_check(not world.player.try_transform(1), "Same-form selection does not consume charges")
	_check(world.player.remaining_transforms == 1, "Same-form charge is preserved")
	world.player.set_environment(2, 0)
	_check(world.player.in_water and not world.player.dead, "Mallard survives overlapping water regions")
	_check(is_equal_approx(world.player.current_speed, 160.0), "Mallard water speed uses source multiplier")
	world.player.set_environment(1, 0)
	_check(world.player.in_water, "Leaving one overlapping water region retains water state")
	world.player.set_environment(0, 0)
	_check(is_equal_approx(world.player.current_speed, 200.0), "Leaving water restores base movement")
	world.player.force_transform(2)
	world.player.set_environment(0, 1)
	_check(is_equal_approx(world.player.current_speed, 300.0), "Penguin ice speed uses source multiplier")
	world.player.force_transform(0)
	_check(is_equal_approx(world.player.current_speed, 200.0), "Changing form clears ice acceleration")
	world.player.set_environment(0, 0)
	world.player.set_transform_limit(-1)
	world.player.try_transform(3)
	_check(world.player.remaining_transforms == -1, "Unlimited transformations remain unlimited")
	var wood: HeronWorldObject
	var door: HeronWorldObject
	var checkpoint: HeronWorldObject
	var spring: HeronWorldObject
	var pickup: HeronWorldObject
	var goal: HeronWorldObject
	for object: HeronWorldObject in world.objects.values():
		match object.kind:
			"BP_DestructibleWood": wood = object
			"BP_Door":
				if not object.door_buttons.is_empty(): door = object
			"BP_CheckPoint": checkpoint = object
			"BP_ItemAddHenshinTimes": pickup = object
			"BP_PassGameTriggerVolume": goal = object
		if object.kind.begins_with("BP_Spring"): spring = object
		if object.kind == "BP_Door":
			for id: String in object.door_buttons:
				_check(world.objects.has(id), "Door reference resolves: " + String(object.record.label))
	_check(wood != null and door != null and checkpoint != null and spring != null and pickup != null and goal != null, "All campaign mechanism classes are present")
	if wood:
		world.player.reset_at(wood.global_position + Vector2(-16, 0), 3)
		var woods_before: int = 0
		for object: HeronWorldObject in world.objects.values():
			if object.kind == "BP_DestructibleWood" and not object.active: woods_before += 1
		world._on_attack(world.player.position, 1)
		var woods_after: int = 0
		for object: HeronWorldObject in world.objects.values():
			if object.kind == "BP_DestructibleWood" and not object.active: woods_after += 1
		print("ATTACK_DIAG ", wood.record.label, " at ", wood.global_position, " box ", wood.world_box(), " origin ", world.player.position, " count ", woods_before, " -> ", woods_after)
		_check(woods_after == woods_before + 1, "Woodpecker sweep destroys exactly one original breakable wood")
		wood.reset_object()
		_check(wood.active and not wood.triggered, "Room reset restores breakable wood")
	if door:
		for id: String in door.door_buttons:
			world.objects[id].activate_button()
		world._update_doors()
		_check(not door.active, "Original AND-wired door opens after all buttons")
		for id: String in door.door_buttons:
			world.objects[id].reset_object()
		door.reset_object()
		_check(door.active, "Reset closes door and clears button state")
	if spring:
		world.player.reset_at(first_position)
		world._interact(spring)
		_check(is_equal_approx(world.player.velocity.y, -390.0), "Spring launches at original SuperJumpSpeed")
	if pickup:
		world.player.set_transform_limit(1)
		world._interact(pickup)
		_check(world.player.remaining_transforms == 2 and not pickup.active, "Pickup increases charge and is consumed")
	world.checkpoint = first_position
	world.checkpoint_bird = 1
	world.checkpoint_room = world.initial_room
	world.player.force_transform(3)
	world.restart()
	_check(world.player.bird == 1 and world.player.position.is_equal_approx(first_position), "Restart restores checkpoint position and saved form")
	for room: String in world.rooms:
		world.change_room(room, true)
		var bounds: Rect2 = world.rooms[room].rect
		_check(bounds.has_area() and world.camera.position.is_equal_approx(bounds.get_center()), "Original room camera fits " + room)
		_check(world.player.max_transforms == int(world.limits.get(room, -1)), "Original transform budget matches " + room)
	world.player.reset_at(first_position, 0)
	world.change_room(world.initial_room, true)
	world.player.set_environment(1, 0)
	_check(world.player.dead and world.resetting, "Non-duck water entry starts death lifecycle")
	await create_timer(1.6).timeout
	_check(not world.resetting and not world.player.dead and world.player.bird == 1, "Timed respawn returns the saved checkpoint form")
	if goal:
		world._interact(goal)
		_check(world.finished and world.player.frozen, "Original goal trigger completes the campaign")
		main._restart()
		world = main.world
		await _frames(2)
		_check(not world.finished and world.room_tag == world.initial_room, "Victory restart creates a fresh campaign")
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "coverage": "Real map instantiation and physics smoke test; targeted mechanism state transitions. Not a manual full campaign playthrough."}
	var file := FileAccess.open("user://migration-test-report.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	print("HERON_INTEGRATION ", JSON.stringify(report))
	main.queue_free()
	world = null
	main = null
	await create_timer(0.8).timeout
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	await process_frame
	quit(0 if failures.is_empty() else 1)
