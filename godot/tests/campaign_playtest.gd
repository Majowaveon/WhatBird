extends SceneTree

const ACTIONS: Array[String] = ["move_left", "move_right", "jump", "action", "heron", "mallard", "penguin", "woodpecker"]
const REPORT_PATH: String = "res://tests/campaign_playtest.json"

var main: Node
var world: HeronWorld
var tick: int = 0
var scenario: String = "original_spawn"
var attempts: Array[Dictionary] = []
var events: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var interventions: Array[Dictionary] = []
var rooms_visited: Array[String] = []
var last_room: String = ""
var last_checkpoint: Vector2 = Vector2.INF
var last_deaths: int = 0
var last_unlocked: Array[int] = []
var held: Array[String] = []
var jump_age: int = -1
var background_audit: Array[Dictionary] = []
var original_result: Dictionary = {}
var isolated_results: Array[Dictionary] = []
var active_scenario_start: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _v(value: Vector2) -> Array:
	return [snappedf(value.x, 0.01), snappedf(value.y, 0.01)]

func _state() -> Dictionary:
	var p: HeronPlayer = world.player
	var contacts: Array[Dictionary] = []
	for i: int in p.get_slide_collision_count():
		var hit: KinematicCollision2D = p.get_slide_collision(i)
		var body: Object = hit.get_collider()
		contacts.append({"collider": str(body.get_path()) if body is Node else str(body), "normal": _v(hit.get_normal()), "position": _v(hit.get_position())})
	return {"tick": tick, "scenario": scenario, "position": _v(p.global_position), "velocity": _v(p.velocity), "room": world.room_tag, "grounded": p.on_ground, "gliding": p.gliding, "bird": p.bird, "unlocked": p.unlocked_birds.duplicate(), "transforms": p.remaining_transforms, "water": p.water_count, "dead": p.dead, "resetting": world.resetting, "deaths": world.deaths, "checkpoint": _v(world.checkpoint), "contacts": contacts}

func _set_inputs(actions: Array[String]) -> void:
	for action: String in ACTIONS:
		if action in actions and action not in held:
			Input.action_press(action)
		elif action not in actions and action in held:
			Input.action_release(action)
	if actions != held:
		events.append({"tick": tick, "scenario": scenario, "event": "input", "actions": actions.duplicate()})
	held = actions.duplicate()

func _step(actions: Array[String]) -> void:
	_set_inputs(actions)
	await physics_frame
	await process_frame
	tick += 1
	_observe()

func _observe() -> void:
	if world.room_tag != last_room:
		events.append({"event": "room_transition", "from": last_room, "to": world.room_tag, "state": _state()})
		last_room = world.room_tag
		if scenario == "original_spawn" and last_room not in rooms_visited:
			rooms_visited.append(last_room)
		print("CAMPAIGN_ROOM ", JSON.stringify(_state()))
	if world.checkpoint != last_checkpoint:
		last_checkpoint = world.checkpoint
		events.append({"event": "checkpoint", "state": _state()})
	if world.deaths != last_deaths:
		last_deaths = world.deaths
		events.append({"event": "death", "state": _state()})
	if world.player.unlocked_birds != last_unlocked:
		last_unlocked = world.player.unlocked_birds.duplicate()
		events.append({"event": "unlock", "state": _state()})
	if tick % 15 == 0:
		samples.append(_state())

func _wait(frames: int) -> void:
	for i: int in frames:
		await _step([])

func _chord(actions: Array[String], frames: int) -> void:
	for i: int in frames:
		await _step(actions)

func _vertical_glide() -> void:
	await _wait(12)
	await _chord(["jump"], 24)
	await _wait(1)
	await _chord(["jump"], 12)

func _check(ok: bool, label: String) -> void:
	checks.append({"passed": ok, "goal": label, "state": _state()})
	print("CAMPAIGN_CHECK ", ok, " ", label)

func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, 5, [world.player.get_rid()])
	return world.get_world_2d().direct_space_state.intersect_ray(query)

func _drive(x: float, max_frames: int, mode: String = "auto", expect_room: String = "", y_range: Array = []) -> bool:
	var before: Dictionary = _state()
	var start: int = tick
	var ok: bool = false
	var reason: String = "timeout"
	for i: int in max_frames:
		var p: HeronPlayer = world.player
		var delta_x: float = x - p.global_position.x
		var y_ok: bool = y_range.is_empty() or (p.global_position.y >= float(y_range[0]) and p.global_position.y <= float(y_range[1]))
		if absf(delta_x) < 6.0 and y_ok and (expect_room.is_empty() or world.room_tag == expect_room):
			ok = true
			reason = "position_and_room_reached"
			break
		if world.resetting or p.dead:
			reason = "death"
			break
		var actions: Array[String] = []
		var direction: float = signf(delta_x) if absf(delta_x) > 3.0 else 0.0
		if direction != 0:
			actions.append("move_right" if direction > 0 else "move_left")
		if mode == "attack" and i % 3 == 0:
			actions.append("action")
		if mode != "walk":
			if p.on_ground:
				jump_age = -1
				var feet: Vector2 = p.global_position + Vector2(0, 9)
				var obstacle: bool = not _ray(feet, feet + Vector2(direction * 28.0, 0)).is_empty() or not _ray(p.global_position, p.global_position + Vector2(direction * 28.0, 0)).is_empty() or p.is_on_wall()
				var gap: bool = _ray(p.global_position + Vector2(direction * 25.0, 8), p.global_position + Vector2(direction * 25.0, 38)).is_empty()
				if direction != 0 and (obstacle or gap or mode == "jump") and "jump" not in held:
					actions.append("jump")
					jump_age = 0
			else:
				if jump_age >= 0:
					jump_age += 1
				if jump_age >= 1 and jump_age <= 23:
					actions.append("jump")
				elif p.bird == 0 and mode in ["auto", "glide", "jump"] and (jump_age >= 25 or p.velocity.y < -210 or p.gliding):
					# Release only after the rising hold, then press separately for glide.
					actions.append("jump")
		await _step(actions)
	_set_inputs([])
	attempts.append({"scenario": scenario, "goal": {"x": x, "y_range": y_range, "room": expect_room, "mode": mode}, "passed": ok, "reason": reason, "frames": tick - start, "before": before, "after": _state()})
	print("CAMPAIGN_ATTEMPT ", JSON.stringify(attempts.back()))
	return ok

func _count_bodies(node: Node) -> int:
	var result: int = 1 if node is StaticBody2D else 0
	for child: Node in node.get_children():
		result += _count_bodies(child)
	return result

func _audit_background() -> void:
	for node: Node in world.get_children():
		if node is HeronTileMap and (String(node.name).begins_with("BG_") or String(node.name).begins_with("FG_")):
			background_audit.append({"name": String(node.name), "static_bodies": _count_bodies(node)})
	var total: int = 0
	for item: Dictionary in background_audit:
		total += int(item.static_bodies)
	_check(background_audit.size() == 40 and total == 0, "All 40 original decorative maps instantiate without collision bodies")

func _attach_observers() -> void:
	for object: HeronWorldObject in world.objects.values():
		object.entered.connect(func(item: HeronWorldObject, body: Node2D) -> void:
			if body == world.player:
				events.append({"tick": tick, "scenario": scenario, "event": "physical_trigger", "kind": item.kind, "label": item.record.get("label", ""), "position": _v(world.player.global_position)})
		)
	world.sound_requested.connect(func(kind: String) -> void:
		if kind in ["spring", "drum", "glide"]:
			events.append({"tick": tick, "scenario": scenario, "event": "ability", "kind": kind, "position": _v(world.player.global_position)})
	)

func _object(label: String) -> HeronWorldObject:
	for item: HeronWorldObject in world.objects.values():
		if String(item.record.get("label", "")) == label:
			return item
	return null

func _isolated_start(label: String, room: String, position: Vector2) -> void:
	_set_inputs([])
	scenario = label
	main.start_game()
	world = main.world
	_attach_observers()
	last_room = ""
	last_checkpoint = Vector2.INF
	last_deaths = 0
	last_unlocked = []
	jump_age = -1
	world.change_room(room, true)
	world.player.reset_at(position, 0)
	interventions.append({"scenario": scenario, "tick": tick, "methods": ["main.start_game", "world.change_room", "player.reset_at"], "position": _v(position), "room": room, "reason": "Isolated diagnostic start only; no direct unlock, interaction, attack, or object-state mutation"})
	active_scenario_start = tick
	await _wait(30)

func _finish_isolated() -> void:
	var observed: Array[Dictionary] = []
	for check: Dictionary in checks:
		if check.state.scenario == scenario:
			observed.append({"goal": check.goal, "passed": check.passed})
	isolated_results.append({"scenario": scenario, "teleported_start": true, "input_only_after_setup": true, "checks": observed, "frames": tick - active_scenario_start, "end": _state()})

func _duck_route() -> void:
	await _isolated_start("isolated_duck_unlock_and_water", "sublevel_w1l1", Vector2(1060, 617))
	await _drive(1010, 90, "walk")
	_check(world.player.is_bird_unlocked(1), "Duck pickup unlocks by physical overlap")
	await _step(["mallard"])
	await _wait(2)
	_check(world.player.bird == 1 and world.player.remaining_transforms == 2, "Mallard input consumes exactly one original room charge")
	await _drive(1120, 150, "walk")
	await _drive(1168, 180, "walk", "", [720, 780])
	await _wait(30)
	_check(world.player.in_water and world.player.bird == 1 and not world.player.dead, "Duck physically enters original water and survives")
	_check(is_equal_approx(world.player.current_speed, 160.0) and is_equal_approx(world.player.current_gravity, 294.0), "Physical water overlap applies source duck speed and gravity")
	var start_y: float = world.player.global_position.y
	await _chord(["jump"], 8)
	_check(world.player.global_position.y < start_y - 10 and not world.player.dead, "Duck jumps upward out of physical water without dying")
	await _drive(1319, 180, "walk")
	await _wait(45)
	_check(_object("BP_Button_w1l1").triggered, "Duck reaches w1l1 button through actual movement")
	_check(not _object("BP_Door_w1l1_1").active and not _object("BP_Door_w1l1_2").active and not _object("BP_Door_w1l1_3").active, "Natural button contact opens all w1l1 exit doors")
	await _drive(991, 300, "walk")
	await _drive(994, 240, "walk", "sublevel_w1l2", [815, 920])
	_check(world.room_tag == "sublevel_w1l2", "Duck route changes to w1l2 through original falling connector")
	_finish_isolated()

func _wood_route() -> void:
	await _isolated_start("isolated_wood_unlock_attack_button", "sublevel_w2l2", Vector2(-696, 589))
	await _drive(-661, 90, "walk")
	await _wait(3)
	_check(world.player.is_bird_unlocked(3), "Woodpecker pickup unlocks by physical overlap")
	await _step(["woodpecker"])
	await _wait(2)
	_check(world.player.bird == 3 and world.player.remaining_transforms == 0, "Woodpecker input uses sole original room charge")
	var before: Dictionary = _state()
	var start: int = tick
	for i: int in 180:
		var actions: Array[String] = ["move_left"]
		if i % 3 == 0:
			actions.append("action")
		await _step(actions)
		if _object("BP_Button_w2l2").triggered or world.resetting:
			break
	_set_inputs([])
	var broken: Array[String] = []
	for item: HeronWorldObject in world.objects.values():
		if item.kind == "BP_DestructibleWood" and not item.active:
			broken.append(String(item.record.label))
	attempts.append({"scenario": scenario, "goal": "Move left and press action through wood to original button", "passed": _object("BP_Button_w2l2").triggered, "frames": tick - start, "before": before, "after": _state(), "broken_wood": broken})
	_check(not broken.is_empty(), "Woodpecker E input breaks original solid wood during real traversal")
	_check(_object("BP_Button_w2l2").triggered, "Woodpecker physically reaches button behind destructible wood")
	await _wait(3)
	_check(not _object("BP_Door_w2l2_1").active and not _object("BP_Door_w2l2_2").active, "Wood room button physically opens both exit doors")
	await _drive(-848, 240, "attack")
	await _chord(["move_right"], 8)
	await _wait(45)
	await _drive(-985, 180, "walk", "sublevel_w2l3", [680, 755])
	_check(world.room_tag == "sublevel_w2l3", "Woodpecker route reaches w2l3 through original room trigger")
	_finish_isolated()

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	_attach_observers()
	await _wait(45)
	_check(world.initial_spawn.is_equal_approx(Vector2(146, -176)) and world.player.on_ground, "Original PlayerStart settles on real terrain")
	_audit_background()
	await _drive(270, 300)
	if not await _drive(350, 120):
		await _drive(266, 90, "walk")
		await _wait(30)
		await _vertical_glide()
		await _drive(350, 180)
	await _drive(510, 240, "auto", "sublevel_w0l2")
	_check(world.room_tag == "sublevel_w0l2", "Original-spawn route reaches w0l2 with input and natural room trigger only")
	original_result = {"rooms_visited": rooms_visited.duplicate(), "finished": world.finished, "end": _state(), "input_only": interventions.is_empty(), "stopped_reason": "Bounded QA scope: original spawn through first room transition; remainder not attempted"}
	await _duck_route()
	await _wood_route()
	await _finish()

func _finish() -> void:
	_set_inputs([])
	var failed_goals: Array[String] = []
	for check: Dictionary in checks:
		if not bool(check.passed):
			failed_goals.append(String(check.goal))
	var timed_out_routes: int = 0
	for attempt: Dictionary in attempts:
		if not bool(attempt.passed):
			timed_out_routes += 1
	var passed: bool = bool(original_result.get("finished", false)) and rooms_visited.size() == world.rooms.size() and interventions.is_empty() and failed_goals.is_empty()
	var report_data: Dictionary = {"passed": passed, "full_campaign_completed": passed, "coverage": "Original PlayerStart input-only route through w0l2, plus two explicitly teleported isolated starts followed by input-only duck and woodpecker traversal. Later campaign rooms and victory are unverified.", "goal_summary": {"satisfied": checks.size() - failed_goals.size(), "total": checks.size(), "failed_goals": failed_goals, "unsatisfied_route_attempts": timed_out_routes}, "confirmed_runtime_defects": [], "not_covered": ["Entire 22-room campaign from PlayerStart", "Final victory trigger via gameplay", "Penguin gameplay", "Isolated-room arrival and unlock approach from earlier campaign rooms", "Visual/rendered correctness; headless physics test only"], "engine": Engine.get_version_info(), "physics_ticks_per_second": Engine.physics_ticks_per_second, "original_spawn_run": original_result, "isolated_results": isolated_results, "route_timeouts_are_not_engine_defects": true, "interventions": interventions, "checks": checks, "attempts": attempts, "background_collision_audit": background_audit, "events": events, "samples": samples}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report_data, "\t"))
		file.close()
	else:
		push_error("Cannot write campaign report: " + REPORT_PATH)
	print("HERON_CAMPAIGN ", JSON.stringify({"passed": passed, "rooms": rooms_visited, "attempts": attempts.size(), "report": REPORT_PATH, "interventions": interventions.size()}))
	main.audio.shutdown()
	# Let audio release its mix-thread references before freeing the scene.
	await create_timer(0.25).timeout
	main.queue_free()
	await create_timer(0.8).timeout
	world = null
	main = null
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()
	await process_frame
	quit(0 if passed else 1)
