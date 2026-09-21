extends SceneTree

var checks: Array[String] = []
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var player: HeronPlayer
var floor_body: StaticBody2D
var world: HeronWorld

func _initialize() -> void:
	for action: String in ["move_left", "move_right", "jump", "action", "heron", "mallard", "penguin", "woodpecker"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		checks.append(label)
	else:
		failures.append(label)
		push_error("JUMP CHECK FAILED: " + label)

func _frames(count: int) -> void:
	for i: int in count:
		await physics_frame
		await process_frame

func _release() -> void:
	for action: String in ["move_left", "move_right", "jump", "action"]:
		Input.action_release(action)

func _make_body(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	root.add_child(body)
	return body

func _reset_flat() -> void:
	_release()
	player.reset_at(Vector2.ZERO)
	await _frames(20)
	_check(player.on_ground, "Jump trial starts grounded")

func _height(hold_seconds: float) -> float:
	await _reset_flat()
	var origin: float = player.position.y
	var apex: float = origin
	var glided: bool = false
	var count: int = maxi(1, roundi(hold_seconds * Engine.physics_ticks_per_second))
	Input.action_press("jump")
	for frame: int in roundi(1.5 * Engine.physics_ticks_per_second):
		if frame == count:
			Input.action_release("jump")
		await _frames(1)
		apex = minf(apex, player.position.y)
		glided = glided or player.gliding
	_release()
	var height: float = origin - apex
	measurements.append({"trial": "vertical_jump", "physics_hz": Engine.physics_ticks_per_second, "hold_seconds": hold_seconds, "height": height, "glided": glided})
	_check(not glided, "A single held press does not secretly enable glide")
	_check(player.on_ground, "Jump lands normally after hold window expires")
	return height

func _first_pillar(hold_seconds: float) -> Dictionary:
	_release()
	world.player.reset_at(Vector2(260, -140))
	await _frames(30)
	var origin: Vector2 = world.player.position
	var apex: float = origin.y
	var max_x: float = origin.x
	var glided: bool = false
	Input.action_press("move_right")
	Input.action_press("jump")
	for frame: int in 75:
		if frame == maxi(1, roundi(hold_seconds * 60)):
			Input.action_release("jump")
		await _frames(1)
		apex = minf(apex, world.player.position.y)
		max_x = maxf(max_x, world.player.position.x)
		glided = glided or world.player.gliding
	_release()
	var result: Dictionary = {"trial": "original_first_wood_pillar", "hold_seconds": hold_seconds, "height": origin.y - apex, "max_x": max_x, "crossed": max_x > 325.0, "glided": glided, "start": [origin.x, origin.y]}
	measurements.append(result)
	return result

func _run() -> void:
	floor_body = _make_body(Vector2(0, 30), Vector2(2000, 16))
	player = HeronPlayer.new()
	root.add_child(player)
	player.setup({"jump_speed": 200.0, "gravity": 980.0}, SpriteFrames.new())
	var original_hz: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60
	var tap: float = await _height(1.0 / 60.0)
	var medium: float = await _height(0.1)
	var held: float = await _height(0.6)
	var extended: float = await _height(1.2)
	_check(tap < medium and medium < held, "Jump height increases with time held")
	_check(held > 32.0 and held < 45.0, "Held jump has clearance for the 28.3-unit tutorial pillar")
	_check(absf(extended - held) < 0.1, "Holding beyond the bounded window cannot add infinite height")
	var low_rate: float
	var high_rate: float
	Engine.physics_ticks_per_second = 30
	low_rate = await _height(0.6)
	Engine.physics_ticks_per_second = 120
	high_rate = await _height(0.6)
	_check(absf(low_rate - high_rate) < 3.5, "Held jump stays consistent at 30 and 120 physics ticks")
	Engine.physics_ticks_per_second = 60

	await _reset_flat()
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	await _frames(1)
	Input.action_press("jump")
	await _frames(1)
	_check(player.gliding, "A separate midair press still starts heron glide")
	_check(not player._variable_jump_active, "Jump hold is not stacked with glide")
	Input.action_release("jump")
	await _frames(1)
	_check(not player.gliding, "Releasing the second press ends glide")

	await _reset_flat()
	Input.action_press("jump")
	await _frames(3)
	player.bounce(390.0)
	Input.action_release("jump")
	await _frames(1)
	_check(player.velocity.y < -350.0 and not player._variable_jump_active, "Jump release does not cut a spring launch")

	await _reset_flat()
	Input.action_press("jump")
	await _frames(3)
	player.unlock_bird(1)
	player.set_transform_limit(-1)
	player.try_transform(1)
	_check(not player._variable_jump_active, "Changing form cancels the old jump hold")
	_release()
	player.reset_at(Vector2.ZERO)
	_check(not player._variable_jump_active and player._jump_hold_remaining == 0, "Reset clears remaining jump force")
	await _frames(20)
	Input.action_press("jump")
	await _frames(2)
	player.die()
	_check(not player._variable_jump_active, "Death cancels the jump hold")

	await _reset_flat()
	var ceiling := _make_body(Vector2(0, -29), Vector2(400, 8))
	await _frames(2)
	Input.action_press("jump")
	var touched_ceiling: bool = false
	var cancelled_at_ceiling: bool = false
	for frame: int in 60:
		await _frames(1)
		if player.is_on_ceiling():
			touched_ceiling = true
			cancelled_at_ceiling = not player._variable_jump_active
	_check(touched_ceiling and cancelled_at_ceiling, "Ceiling contact cancels upward hold immediately")
	_check(player.on_ground, "Holding jump does not repeat automatically on landing")
	_release()
	ceiling.queue_free()
	player.queue_free()
	floor_body.queue_free()
	await _frames(3)

	world = HeronWorld.new()
	root.add_child(world)
	world.load_map(JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json")))
	await _frames(30)
	var short_pillar: Dictionary = await _first_pillar(1.0 / 60.0)
	var long_pillar: Dictionary = await _first_pillar(0.6)
	_check(not short_pillar.crossed, "A tap stays low at the original pillar")
	_check(long_pillar.crossed and not long_pillar.glided, "One held jump clears the original first pillar without a second press or glide")
	_check(world.player.bird == 0 and world.player.remaining_transforms == 0, "Tutorial pillar test uses normal heron and zero transformation charges")
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "measurements": measurements, "tuning": {"jump_speed": 200, "hold_time": player.jump_hold_time if is_instance_valid(player) else 0.32, "hold_gravity_scale": 0.5, "release_multiplier": 0.5}}
	FileAccess.open("res://tests/jump_verification.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HERON_JUMP_REGRESSION ", JSON.stringify(report))
	world.queue_free()
	world = null
	await create_timer(0.4).timeout
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	Engine.physics_ticks_per_second = original_hz
	await process_frame
	quit(0 if failures.is_empty() else 1)
