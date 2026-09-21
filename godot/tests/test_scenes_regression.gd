extends SceneTree

var checks: Array[String] = []
var failures: Array[String] = []
var world: HeronWorld

func _initialize() -> void:
	for action: String in ["move_left", "move_right", "jump", "action", "heron", "mallard", "penguin", "woodpecker"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		checks.append(label)
	else:
		failures.append(label)
		push_error("TEST SCENE CHECK FAILED: " + label)

func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame

func _release() -> void:
	for action: String in ["move_left", "move_right", "jump", "action"]:
		Input.action_release(action)

func _load_scene(path: String) -> void:
	ProjectSettings.set_meta("heron_scene_preview", path)
	world = HeronWorld.new()
	root.add_child(world)
	world.load_map({})
	await _frames(30)
	_check(world.scene_preview and world.rooms.size() == 1, path + " loads only its own preview room")
	_check(world.player.bird == HeronPlayer.Bird.PENGUIN, path + " starts as penguin")
	_check(world.player.unlocked_birds.size() == 4 and world.player.max_transforms == -1, path + " allows unlimited form comparisons")
	_check(world.player.on_ground and not world.player.dead, path + " has a safe grounded spawn")

func _unload_scene() -> void:
	_release()
	world.queue_free()
	world = null
	await _frames(3)

func _walk_to_x(target: float, max_frames: int = 240) -> bool:
	Input.action_press("move_right")
	for frame: int in max_frames:
		await _frames(1)
		if world.player.position.x >= target:
			Input.action_release("move_right")
			return true
	Input.action_release("move_right")
	return false

func _penguin_course() -> void:
	await _load_scene("res://scenes/tests/penguin_ice.tscn")
	_check(not world.player.on_ice and is_equal_approx(world.player.current_speed, 200.0), "Snow-covered dry ground keeps normal speed")
	_check(await _walk_to_x(300.0), "Player can walk from spawn onto the ice runway")
	_check(world.player.on_ice and world.player.on_ground, "Saved ice Area2D detects a grounded player")
	_check(is_equal_approx(world.player.velocity.x, 300.0) and world.player.sprite.animation == &"penguin_slide", "Real movement reaches speed 300 and uses the slide animation")
	var release_x: float = world.player.position.x
	await _frames(20)
	_check(world.player.on_ground and world.player.velocity.x > 200.0 and world.player.position.x > release_x + 60.0, "Penguin coasts across the ice after movement is released")
	world.player.try_transform(HeronPlayer.Bird.HERON)
	await _frames(2)
	_check(world.player.on_ice and is_equal_approx(world.player.current_speed, 200.0), "Changing to heron on ice removes the penguin speed bonus")
	world.player.try_transform(HeronPlayer.Bird.PENGUIN)
	await _frames(2)
	_check(is_equal_approx(world.player.current_speed, 300.0), "Changing back to penguin restores the ice speed bonus")
	var takeoff_speed: float = world.player.velocity.x
	Input.action_press("jump")
	await _frames(14)
	_check(not world.player.on_ground and not world.player.on_ice, "Jumping clears the shallow ice trigger")
	_check(world.player.ice_sliding and world.player.sprite.animation == &"penguin_slide", "Leaving the ice trigger during a jump preserves the slide pose")
	_check(is_equal_approx(world.player.velocity.x, takeoff_speed), "Ice jump preserves the actual takeoff speed rather than forcing the speed cap")
	Input.action_release("jump")
	await _frames(55)
	_check(world.player.on_ground and world.player.on_ice, "Landing re-enters the ice trigger")
	_check(await _walk_to_x(680.0), "Player crosses from ice onto the right dry landing")
	await _frames(20)
	_check(not world.player.on_ice and is_equal_approx(world.player.current_speed, 200.0), "Exiting the runway clears ice speed and friction")
	world.restart()
	await _frames(20)
	_check(world.player.position.distance_to(Vector2(72, 386.8)) < 2.0 and not world.player.on_ice, "Restart returns to the dry spawn and clears ice state")
	_check(await _walk_to_x(720.0), "Player can approach the right jump platforms")
	Input.action_press("jump")
	Input.action_press("move_right")
	var landed_on_platform: bool = false
	for frame: int in 60:
		if frame == 24:
			Input.action_release("jump")
		await _frames(1)
		landed_on_platform = landed_on_platform or (world.player.position.x > 736.0 and world.player.on_ground and world.player.position.y < 360.0)
	_release()
	_check(landed_on_platform, "A held jump reaches the first raised platform")
	await _unload_scene()

func _snow_course() -> void:
	await _load_scene("res://scenes/tests/snow_playground.tscn")
	var button: HeronWorldObject = world.editable_scene.get_node("Actors/SnowButton") as HeronWorldObject
	var spring: HeronWorldObject = world.editable_scene.get_node("Actors/SnowSpring") as HeronWorldObject
	var doors: Array[HeronWorldObject] = []
	for part: String in ["Bottom", "Middle", "Top"]:
		var door: HeronWorldObject = world.editable_scene.get_node("Actors/SnowDoor" + part) as HeronWorldObject
		doors.append(door)
		_check(door.active and not door.triggered and not door.solid_shapes[0].disabled, "Snow door " + part + " starts closed with collision")
		_check(door.render.scale.is_equal_approx(Vector2(0.5, 0.5)), "Snow door " + part + " keeps its authored sprite scale")
	world.player.position = Vector2(568, 386)
	await _frames(5)
	Input.action_press("move_right")
	await _frames(30)
	_release()
	_check(world.player.position.x < 593.0 and world.player.on_ground, "Closed snow door physically blocks the player")
	world.restart()
	await _frames(20)
	var bounced: bool = false
	var spring_animated: bool = false
	var reached_platform: bool = false
	Input.action_press("move_right")
	for frame: int in 240:
		await _frames(1)
		bounced = bounced or world.player.velocity.y < -300.0
		spring_animated = spring_animated or spring.render.sprite_frames == spring.spring_animation
		reached_platform = reached_platform or (world.player.on_ground and world.player.position.x > 320.0 and world.player.position.y < 350.0)
		if button.triggered:
			break
	_release()
	_check(bounced and spring_animated, "Walking onto the snow spring launches the player and plays its pop frames")
	_check(reached_platform and button.triggered, "Holding right after the spring reaches the high platform and activates its button")
	await _frames(3)
	for door: HeronWorldObject in doors:
		_check(door.triggered and not door.active and door.solid_shapes[0].disabled, String(door.name) + " opens through the saved button NodePath")
	_check(await _walk_to_x(816.0), "Opened route reaches the final NPC without teleporting")
	await _frames(20)
	_check(not world.player.dead and world.player.on_ground and not world.player.on_ice, "Final snow landing is safe and clears ice state")
	world.restart()
	await _frames(30)
	_check(not button.triggered and button.render.sprite_frames == button.initial_frames, "Restart restores the unpressed button")
	for door: HeronWorldObject in doors:
		_check(door.active and not door.triggered and not door.solid_shapes[0].disabled, String(door.name) + " restores collision after restart")
	_check(world.player.position.distance_to(Vector2(72, 386.8)) < 2.0 and not world.player.on_ice, "Snow course restart returns to the original dry spawn")
	await _unload_scene()

func _run() -> void:
	await _penguin_course()
	await _snow_course()
	ProjectSettings.remove_meta("heron_scene_preview")
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	await process_frame
	print("HERON_TEST_SCENES ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
