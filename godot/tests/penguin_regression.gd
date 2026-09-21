extends SceneTree

var checks: Array[String] = []
var failures: Array[String] = []
var player: HeronPlayer
var floor_body: StaticBody2D
var wall: StaticBody2D

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
		push_error("PENGUIN CHECK FAILED: " + label)

func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame

func _release() -> void:
	for action: String in ["move_left", "move_right", "jump", "action"]:
		Input.action_release(action)

func _body(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	return body

func _reset(ice: bool = true) -> void:
	_release()
	player.reset_at(Vector2(0, -20), HeronPlayer.Bird.PENGUIN)
	player.set_environment(0, 1 if ice else 0)
	await _frames(15)
	_check(player.on_ground, "Penguin trial starts on a real floor")

func _run_up() -> void:
	Input.action_press("move_right")
	await _frames(45)
	_check(is_equal_approx(player.velocity.x, 300.0), "Ice acceleration reaches speed 300")

func _start_slide_jump() -> float:
	await _reset()
	await _run_up()
	var takeoff_speed: float = player.velocity.x
	Input.action_release("move_right")
	Input.action_press("jump")
	await _frames(1)
	player.set_environment(0, 0)
	return takeoff_speed

func _pose_and_inertia() -> void:
	await _reset()
	var idle_offset: Vector2 = player.sprite.offset
	await _run_up()
	_check(player.ice_sliding and player.sprite.animation == &"penguin_slide", "Moving penguin on ice uses the slide pose")
	player.set_physics_process(false)
	var texture: Image = (load("res://assets/Resources/Player/Penguin/Penguin.png") as Texture2D).get_image()
	for frame: int in player.sprite.sprite_frames.get_frame_count(&"penguin_slide"):
		player.sprite.set_frame_and_progress(frame, 0.0)
		var atlas: AtlasTexture = player.sprite.sprite_frames.get_frame_texture(&"penguin_slide", frame) as AtlasTexture
		var visible: Rect2i = texture.get_region(Rect2i(atlas.region)).get_used_rect()
		var bottom: Vector2 = player.sprite.to_global(Vector2(0, -atlas.region.size.y * 0.5 + player.sprite.offset.y + visible.end.y))
		_check(absf(bottom.y) < 1.5, "Slide frame %d visible belly touches the floor" % frame)
		player.sprite.flip_h = true
		var flipped_bottom: Vector2 = player.sprite.to_global(Vector2(0, -atlas.region.size.y * 0.5 + player.sprite.offset.y + visible.end.y))
		_check(is_equal_approx(bottom.y, flipped_bottom.y), "Slide frame %d keeps the same height when facing left" % frame)
	player.set_physics_process(true)
	Input.action_release("move_right")
	var release_position: float = player.position.x
	await _frames(30)
	_check(player.velocity.x > 200.0 and player.velocity.x < 300.0, "Release keeps substantial speed after half a second")
	_check(player.position.x > release_position + 100.0 and player.ice_sliding, "Release continues visible sliding rather than instant braking")
	await _frames(150)
	_check(is_zero_approx(player.velocity.x) and not player.ice_sliding, "Ice friction eventually stops the penguin")
	_check(player.sprite.animation == &"penguin_idle" and player.sprite.offset == idle_offset, "Stopping restores the standing pivot without accumulated offset")
	await _run_up()
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _frames(6)
	_check(player.velocity.x > 200.0 and player.facing == 1, "Reverse input first brakes while retaining forward facing")
	await _frames(84)
	_check(is_equal_approx(player.velocity.x, -300.0) and player.facing == -1, "Sustained reverse input eventually slides left")
	_release()
	player.set_physics_process(false)
	var speeds: Array[float] = []
	for hz: int in [30, 60, 120]:
		player.velocity.x = 300.0
		for frame: int in hz:
			player._move_horizontal(0.0, 1.0 / hz)
		speeds.append(player.velocity.x)
	_check(absf(speeds[0] - speeds[2]) < 0.01, "One second of ice coasting is consistent at 30 and 120 Hz")
	player.set_physics_process(true)

func _airborne_slide() -> void:
	var takeoff_speed: float = await _start_slide_jump()
	var held_slide: bool = true
	var held_speed: bool = true
	var saw_rising: bool = false
	var saw_falling: bool = false
	for frame: int in 70:
		if frame == 10:
			Input.action_press("move_left")
		if frame == 24:
			Input.action_release("jump")
		await _frames(1)
		if player.on_ground:
			break
		held_slide = held_slide and player.ice_sliding and player.sprite.animation == &"penguin_slide"
		held_speed = held_speed and absf(player.velocity.x - takeoff_speed) < 0.01
		saw_rising = saw_rising or player.velocity.y < 0.0
		saw_falling = saw_falling or player.velocity.y > 0.0
	_check(saw_rising and saw_falling and held_slide, "Slide pose lasts through ascent and descent outside the ice trigger")
	_check(held_speed, "Ice jump retains takeoff velocity even when releasing or reversing input")
	_check(player.on_ground and not player.ice_sliding and is_equal_approx(player.current_speed, 200.0), "Landing on dry terrain ends the airborne slide")
	_release()
	await _frames(20)
	_check(is_zero_approx(player.velocity.x), "Dry ground restores ordinary braking")

	await _start_slide_jump()
	await _frames(5)
	player.set_environment(0, 1)
	Input.action_release("jump")
	for frame: int in 60:
		await _frames(1)
		if player.on_ground:
			break
	_check(player.on_ground and player.ice_sliding and player.velocity.x > 290.0, "Landing back on ice continues the slide without losing momentum")

	await _start_slide_jump()
	wall = _body(Vector2(player.position.x + 45, -80), Vector2(16, 160))
	await _frames(15)
	_check(absf(player.velocity.x) < 0.01, "A wall stops airborne slide momentum")
	wall.queue_free()
	await _frames(3)
	_check(absf(player.velocity.x) < 0.01, "Removing a wall does not resurrect the old slide speed")

	await _reset(false)
	Input.action_press("move_right")
	await _frames(10)
	Input.action_press("jump")
	await _frames(8)
	_check(not player.ice_sliding and player.sprite.animation == &"penguin_jump", "A dry-ground jump retains the ordinary penguin animation")

func _state_cleanup() -> void:
	await _start_slide_jump()
	player.unlock_bird(HeronPlayer.Bird.HERON)
	_check(player.try_transform(HeronPlayer.Bird.HERON), "Changing form succeeds during an ice jump")
	_check(not player.ice_sliding and not player._ice_slide_airborne and is_equal_approx(player.current_speed, 200.0), "Changing form clears carried ice state")
	player.force_transform(HeronPlayer.Bird.PENGUIN)
	_check(not player.ice_sliding, "Returning to penguin midair does not restore an old slide")
	await _start_slide_jump()
	player.die()
	_check(not player.ice_sliding and not player._ice_slide_airborne and player.velocity == Vector2.ZERO, "Death clears airborne ice momentum")
	await _reset(false)
	_check(not player.ice_sliding and not player.on_ice and player.sprite.animation == &"penguin_idle", "Respawn on dry ground starts without stale ice or pivot state")
	await _start_slide_jump()
	player.reset_at(Vector2(0, -20), HeronPlayer.Bird.PENGUIN)
	_check(not player._ice_slide_airborne and player.velocity == Vector2.ZERO, "Restart during an ice jump clears its velocity latch")

func _run() -> void:
	floor_body = _body(Vector2(0, 16), Vector2(10000, 32))
	player = HeronPlayer.new()
	root.add_child(player)
	player.setup({}, HeronPaperAssets.player_frames())
	await _pose_and_inertia()
	await _airborne_slide()
	await _state_cleanup()
	_release()
	player.queue_free()
	floor_body.queue_free()
	await _frames(3)
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	await process_frame
	print("HERON_PENGUIN_REGRESSION ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
