extends SceneTree

var checks: Array[String] = []
var failures: Array[String] = []
var main: Node
var world: HeronWorld
var meeting: HeronEditableRoom
var puzzle: HeronEditableRoom

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		checks.append(label)
	else:
		failures.append(label)
		push_error("FROSTPASS CHECK FAILED: " + label)
		if is_instance_valid(world) and is_instance_valid(world.player):
			print("FROSTPASS_STATE position=", world.player.position, " velocity=", world.player.velocity, " room=", world.room_tag)

func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame

func _release() -> void:
	for action: String in ["move_left", "move_right", "jump", "action", "woodpecker", "penguin"]:
		Input.action_release(action)

func _move_to(x: float, limit: int = 240) -> bool:
	var direction: String = "move_right" if world.player.position.x < x else "move_left"
	var right: bool = direction == "move_right"
	Input.action_press(direction)
	for frame: int in limit:
		await _frames(1)
		if world.resetting or world.finished:
			break
		if (right and world.player.position.x >= x) or (not right and world.player.position.x <= x):
			Input.action_release(direction)
			return true
	Input.action_release(direction)
	return false

func _object(room: Node, name: String) -> HeronWorldObject:
	return room.get_node("Actors/" + name) as HeronWorldObject

func _layout_checks() -> void:
	_check(world.rooms.size() == 22 and not world.scene_preview, "Normal Start includes the original 20 rooms plus exactly two snow rooms")
	_check(world.player.bird == 0 and world.player.unlocked_birds == [0], "Campaign starts as heron and does not grant the penguin early")
	_check(not main.ui.has_signal("snow_requested"), "Snow has no separate menu entry")
	var goals: Array[HeronWorldObject] = []
	for object: HeronWorldObject in world.objects.values():
		if object.kind == "BP_PassGameTriggerVolume":
			goals.append(object)
	_check(goals.size() == 1 and puzzle.is_ancestor_of(goals[0]), "Only the end of the snow puzzle can finish the campaign")
	_check(_object(meeting, "LearnPenguin").unlock_form == 2, "Meeting the penguin awards the new form through the existing pickup mechanism")
	_check(_object(puzzle, "SpeedButterfly").required_form == 2 and is_equal_approx(_object(puzzle, "SpeedButterfly").minimum_horizontal_speed, 275.0), "The ice switch requires penguin momentum rather than woodpecker attacks")
	_check(_object(puzzle, "SpeedButterfly").linked_doors.is_empty() and _object(puzzle, "LandingButterfly").linked_doors.is_empty(), "Neither butterfly bypasses the two-switch AND condition")

func _snow_route() -> void:
	# Isolate the forest-to-snow handoff; the full original campaign is not replayed here.
	world.player.unlock_bird(1)
	world.player.unlock_bird(3)
	world.change_room("SubLevel_w2l7", true)
	world.player.reset_at(Vector2(-72, -222), 3)
	await _frames(15)
	_check(not world.finished and not world.player.is_bird_unlocked(2), "Forest's former endpoint no longer ends the game or grants penguin")
	var bounced: bool = false
	Input.action_press("move_right")
	for frame: int in 120:
		await _frames(1)
		bounced = bounced or world.player.velocity.y < -500.0
		if world.player.position.x >= meeting.global_position.x + 112:
			break
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _frames(8)
	Input.action_release("move_left")
	await _frames(40)
	_check(bounced and world.room_tag == "sublevel_w3l1" and world.player.on_ground, "Forest ascent physically reaches the snow encounter with no teleport after setup")
	_check(world.checkpoint_room == "sublevel_w3l1", "Arrival captures the safe snow checkpoint")
	_check(not world.player.is_bird_unlocked(2), "Penguin remains locked until the player meets the NPC")
	_check(await _move_to(meeting.global_position.x + 198), "Player physically meets the penguin")
	await _frames(4)
	_check(world.player.is_bird_unlocked(2) and not _object(meeting, "LearnPenguin").active, "NPC overlap unlocks penguin exactly once")
	_check(_object(meeting, "PenguinFriend").active and _object(meeting, "PenguinFriend").render.visible, "The penguin friend stays visible after teaching its form")
	Input.action_press("penguin")
	await _frames(2)
	Input.action_release("penguin")
	_check(world.player.bird == 2, "Normal form input can use the newly learned penguin")
	_check(await _move_to(meeting.global_position.x + 350), "Safe practice ice can be crossed without jumping")
	_check(world.player.on_ice and world.player.velocity.x > 275.0, "Encounter room provides a safe place to learn ice acceleration")
	world.restart()
	await _frames(15)
	_check(world.player.is_bird_unlocked(2) and not _object(meeting, "LearnPenguin").active, "Checkpoint retry keeps the learned form and consumed unlock")
	_check(await _move_to(puzzle.global_position.x + 30), "Encounter leads directly into the puzzle without a level select")
	await _frames(12)
	_check(world.room_tag == "sublevel_w3l2" and world.checkpoint_room == world.room_tag, "Puzzle entry sets its own checkpoint before all switches")
	var speed_button: HeronWorldObject = _object(puzzle, "SpeedButterfly")
	var landing_button: HeronWorldObject = _object(puzzle, "LandingButterfly")
	_check(world.player.bird == 3, "Encounter retry restored the arriving woodpecker form")
	_check(await _move_to(puzzle.global_position.x + 190), "Woodpecker can inspect the frozen switch")
	await _frames(3)
	_check(not speed_button.triggered, "Woodpecker walking through the ice switch does not activate it")
	Input.action_press("penguin")
	await _frames(2)
	Input.action_release("penguin")
	_check(await _move_to(puzzle.global_position.x + 156), "Player tries a short penguin approach to the switch")
	await _frames(2)
	_check(not speed_button.triggered, "A short low-speed approach does not activate the frozen switch")
	_check(await _move_to(puzzle.global_position.x + 28), "The ice path allows backing up for a longer run-up")
	await _frames(12)
	_check(await _move_to(puzzle.global_position.x + 260), "A full penguin run-up crosses the switch")
	await _frames(2)
	_check(speed_button.triggered and not landing_button.triggered, "Penguin momentum activates the first butterfly only")
	_check(_object(puzzle, "SnowGate1").active, "The gate stays closed until the second butterfly is reached")
	_check(await _move_to(puzzle.global_position.x + 308), "Run-up continues to the marked ice edge")
	Input.action_press("move_right")
	Input.action_press("jump")
	for frame: int in 45:
		await _frames(1)
		if frame == 30:
			Input.action_release("jump")
	_release()
	await _frames(8)
	_check(landing_button.triggered, "The ice jump lands beside the second butterfly")
	for index: int in range(1, 5):
		var gate: HeronWorldObject = _object(puzzle, "SnowGate%d" % index)
		_check(gate.triggered and not gate.active and gate.solid_shapes[0].disabled, "Both switches open snow gate segment %d" % index)
	Input.action_press("move_right")
	for frame: int in 90:
		await _frames(1)
		if world.finished:
			break
	_release()
	_check(world.finished and main.ui._mode == "victory", "The snow puzzle exit ends the continuous campaign")
	_check(world.deaths == 0, "Encounter and puzzle route complete without a death")

func _reset_checks() -> void:
	main._restart()
	world = main.world
	meeting = world.editable_scene.get_node("w3l1") as HeronEditableRoom
	puzzle = world.editable_scene.get_node("w3l2") as HeronEditableRoom
	await _frames(15)
	_check(world.room_tag == "sublevel_w0l1" and world.player.unlocked_birds == [0] and world.rooms.size() == 22, "Victory restart returns to the campaign beginning with fresh unlocks")
	world.player.unlock_bird(2)
	world.change_room("SubLevel_w3l2", true)
	world.player.reset_at(puzzle.global_position + Vector2(24, 208), 2)
	await _frames(15)
	_object(puzzle, "SpeedButterfly").activate_button()
	_object(puzzle, "LandingButterfly").activate_button()
	await _frames(3)
	world.restart()
	await _frames(12)
	_check(world.player.on_ground and world.player.position.distance_to(puzzle.global_position + Vector2(24, 210.8)) < 2.0, "Puzzle retry returns to a safe flag before the runway")
	_check(not _object(puzzle, "SpeedButterfly").triggered and not _object(puzzle, "LandingButterfly").triggered, "Retry restores both puzzle switches")
	_check(_object(puzzle, "SnowGate1").active and not _object(puzzle, "SnowGate1").solid_shapes[0].disabled, "Retry restores the gate collision")
	_check(world.player.is_bird_unlocked(2) and world.player.remaining_transforms == -1, "Retry cannot strand the player without penguin or transform charges")
	main.start_game("res://scenes/rooms/w3l2.tscn")
	world = main.world
	await _frames(20)
	_check(world.scene_preview and world.rooms.size() == 1 and world.player.bird == 2 and world.player.on_ground, "Puzzle still supports safe isolated F6 editing preview")
	main.show_menu()
	main.ui.start_requested.emit()
	world = main.world
	await _frames(15)
	_check(not world.scene_preview and world.rooms.size() == 22 and world.player.unlocked_birds == [0], "Returning from F6 then Start opens the full campaign without preview unlocks")

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(2)
	main.ui.start_requested.emit()
	world = main.world
	meeting = world.editable_scene.get_node("w3l1") as HeronEditableRoom
	puzzle = world.editable_scene.get_node("w3l2") as HeronEditableRoom
	await _frames(20)
	_layout_checks()
	await _snow_route()
	await _reset_checks()
	main.audio.shutdown()
	main.queue_free()
	main = null
	world = null
	await create_timer(0.5).timeout
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	await process_frame
	print("HERON_FROSTPASS ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "coverage": "Campaign scene topology, isolated snow-chapter input route with physical NPC unlock and two-switch puzzle, reset and F6 checks. Not a full original-campaign playthrough; no desktop automation."}))
	quit(0 if failures.is_empty() else 1)
