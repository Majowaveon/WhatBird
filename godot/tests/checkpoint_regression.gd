extends SceneTree

const ROOM_TAG: String = "sublevel_w1l1"
const ACTIONS: Array[String] = ["move_left", "move_right", "jump", "mallard", "heron"]

var world: HeronWorld
var checks: Array[String] = []
var failures: Array[String] = []
var events: Array[Dictionary] = []
var held: Array[String] = []
var room: HeronEditableRoom
var entry: HeronWorldObject
var upper: HeronWorldObject
var pickup: HeronWorldObject

func _initialize() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		checks.append(label)
	else:
		failures.append(label)
		print("CHECKPOINT CHECK FAILED: ", label)

func _step(actions: Array[String] = []) -> void:
	for action: String in ACTIONS:
		if action in actions and action not in held:
			Input.action_press(action)
		elif action not in actions and action in held:
			Input.action_release(action)
	held = actions.duplicate()
	await physics_frame
	await process_frame

func _frames(count: int) -> void:
	for frame: int in count:
		await _step()

func _local_position() -> Vector2:
	return room.to_local(world.player.global_position)

func _state(label: String) -> void:
	var point: Vector2 = world.player.global_position
	var saved: Vector2 = world.checkpoint
	events.append({"event": label, "position": [point.x, point.y], "checkpoint": [saved.x, saved.y], "room": world.room_tag, "checkpoint_room": world.checkpoint_room, "bird": world.player.bird, "duck_unlocked": world.player.is_bird_unlocked(HeronPlayer.Bird.MALLARD), "dead": world.player.dead})

func _walk_to(x: float, frames: int) -> bool:
	for frame: int in frames:
		var difference: float = x - _local_position().x
		if absf(difference) < 4.0:
			await _step()
			return true
		if world.resetting:
			return false
		await _step(["move_right" if difference > 0.0 else "move_left"])
	return false

func _miss_duck() -> void:
	for frame: int in 120:
		var local: Vector2 = _local_position()
		if local.x <= 88.0 or world.resetting:
			break
		var actions: Array[String] = ["move_left"]
		if local.y > 100.0 and local.x > 120.0:
			actions.append("jump")
		await _step(actions)
	await _frames(35)
	var landed: Vector2 = _local_position()
	_check(world.player.on_ground and landed.x > 60.0 and landed.x < 110.0 and landed.y > 200.0, "Missed-pickup route physically lands on the lower-left ledge")
	_check(not world.player.is_bird_unlocked(HeronPlayer.Bird.MALLARD), "Missed-pickup route keeps the duck locked")
	_check(world.checkpoint.is_equal_approx(entry.global_position), "Missing the duck does not replace the safe checkpoint with the lower-left ledge")
	_state("missed_duck")

func _drown() -> void:
	var deaths: int = world.deaths
	for frame: int in 100:
		if world.resetting:
			break
		await _step(["move_right"])
	_check(world.resetting and world.player.dead and world.deaths == deaths + 1, "Walking into water as heron starts the real death lifecycle")
	await _frames(110)
	_check(not world.resetting and not world.player.dead and world.player.on_ground, "Timed respawn settles alive on a platform")

func _reach_upper() -> void:
	_check(await _walk_to(285.0, 60), "Player reaches the right platform's takeoff point")
	await _frames(10)
	for frame: int in 140:
		if _local_position().x <= 112.0 or world.resetting:
			break
		var actions: Array[String] = ["move_left"]
		if frame != 20:
			actions.append("jump")
		await _step(actions)
	for frame: int in 12:
		if world.player.velocity.x >= -5.0:
			break
		await _step(["move_right"])
	await _frames(25)
	var landed: Vector2 = _local_position()
	_check(world.player.on_ground and landed.x > 60.0 and landed.x < 110.0 and landed.y < 110.0, "A jump and glide reach the duck's upper-left platform")
	_check(world.checkpoint.is_equal_approx(upper.global_position), "Physical contact saves the upper-left checkpoint")
	_check(not world.player.is_bird_unlocked(HeronPlayer.Bird.MALLARD), "Upper checkpoint is reachable before collecting the duck")
	_state("upper_checkpoint")

func _clear_world() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)
	held.clear()
	world.queue_free()
	world = null
	await _frames(3)

func _preview() -> void:
	await _clear_world()
	ProjectSettings.set_meta("heron_scene_preview", "res://scenes/rooms/w1l1.tscn")
	world = HeronWorld.new()
	root.add_child(world)
	world.load_map({})
	ProjectSettings.remove_meta("heron_scene_preview")
	room = world.editable_scene as HeronEditableRoom
	await _frames(12)
	_check(world.scene_preview and world.initial_spawn.is_equal_approx(Vector2(336, 44)), "Single-room preview keeps the upper-right PlayerStart")
	_check(world.player.bird == HeronPlayer.Bird.MALLARD and world.player.on_ground, "Single-room preview still starts grounded as the configured mallard")

func _run() -> void:
	world = HeronWorld.new()
	root.add_child(world)
	world.load_map(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	await _frames(3)
	room = world.rooms[ROOM_TAG]["node"]
	entry = room.get_node("Actors/BP_CheckPoint_w1l1_1")
	upper = room.get_node("Actors/BP_CheckPoint_w1l1_2")
	pickup = room.get_node("Actors/BP_ItemUnlockBird_Duck")
	_check(entry.position.is_equal_approx(Vector2(336, 44)) and upper.position.is_equal_approx(Vector2(88, 90)), "Both authored checkpoints are on the upper platforms")
	# Start below the previous room's exit doors; subsequent progress uses input and physical triggers.
	world.change_room("sublevel_w0l6", true)
	world.player.reset_at(Vector2(1344, 400), HeronPlayer.Bird.HERON)
	await _frames(60)
	_check(world.room_tag == ROOM_TAG and world.player.on_ground, "Falling through the previous room's exit naturally enters w1l1")
	_check(await _walk_to(336.0, 60), "Player walks from the arrival point to the entry checkpoint")
	await _frames(10)
	_check(world.checkpoint.is_equal_approx(entry.global_position) and world.checkpoint_room == ROOM_TAG, "Physical entry contact saves the upper-right checkpoint and correct room")
	_state("entry")
	await _miss_duck()
	world.restart()
	_check(world.player.global_position.is_equal_approx(entry.global_position), "Restart after missing the duck returns to the upper-right platform")
	await _frames(12)
	await _miss_duck()
	await _drown()
	_check(world.checkpoint.is_equal_approx(entry.global_position) and _local_position().y < 65.0, "Death before unlocking the duck returns to the upper-right platform")
	_state("entry_respawn")
	await _reach_upper()
	world.restart()
	_check(world.player.global_position.is_equal_approx(upper.global_position), "Restart at the second checkpoint returns to the duck's platform")
	await _frames(12)
	await _drown()
	_check(world.checkpoint.is_equal_approx(upper.global_position) and _local_position().y < 110.0 and not world.player.is_bird_unlocked(HeronPlayer.Bird.MALLARD), "Death before collecting the duck returns to the reachable upper-left platform")
	_check(await _walk_to(50.0, 60), "Player can walk to the duck after respawning")
	await _frames(5)
	_check(world.player.is_bird_unlocked(HeronPlayer.Bird.MALLARD) and not pickup.active, "Physical pickup unlocks the duck after respawn")
	await _step(["mallard"])
	await _frames(2)
	_check(world.player.bird == HeronPlayer.Bird.MALLARD and world.player.remaining_transforms == 2, "Duck transformation still consumes one room charge")
	_check(await _walk_to(160.0, 120), "Duck walks off the upper-left platform toward the water")
	await _frames(45)
	_check(world.player.in_water and not world.player.dead, "Duck survives physically entering the water")
	_check(world.checkpoint_bird == HeronPlayer.Bird.MALLARD, "Re-entering the upper checkpoint saves the current duck form")
	await _step(["jump", "move_right"])
	_check(await _walk_to(240.0, 100), "Duck swims across the pool")
	for frame: int in 100:
		var actions: Array[String] = ["move_right"]
		if frame < 24:
			actions.append("jump")
		await _step(actions)
		if _local_position().x >= 359.0:
			break
	await _frames(15)
	var button: HeronWorldObject = room.get_node("Actors/BP_Button_w1l1")
	_check(button.triggered, "Duck still reaches the exit button through actual movement")
	for suffix: String in ["1", "2", "3"]:
		var door: HeronWorldObject = room.get_node("Actors/BP_Door_w1l1_" + suffix)
		_check(not door.active, "Exit door " + suffix + " opens normally")
	world.restart()
	_check(world.player.global_position.is_equal_approx(upper.global_position) and world.player.bird == HeronPlayer.Bird.MALLARD, "Restart restores the upper checkpoint and saved duck form")
	_check(world.player.is_bird_unlocked(HeronPlayer.Bird.MALLARD) and not pickup.active and not button.triggered, "Restart preserves the unlock and resets the button")
	for suffix: String in ["1", "2", "3"]:
		var door: HeronWorldObject = room.get_node("Actors/BP_Door_w1l1_" + suffix)
		_check(door.active, "Restart closes exit door " + suffix)
	_state("duck_respawn")
	await _preview()
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "events": events, "coverage": "Isolated start below w0l6 exit doors, natural room entry, missed duck, restart and physical drowning, upper checkpoint, duck pickup and exit button, native room preview. Not a full campaign playthrough."}
	print("HERON_CHECKPOINT_REGRESSION ", JSON.stringify(report))
	await _clear_world()
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	await process_frame
	quit(0 if failures.is_empty() else 1)
