extends SceneTree

var checks: Array[String] = []
var failures: Array[String] = []
var main: Node
var world: HeronWorld
var ui: HeronUI

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		checks.append(label)
	else:
		failures.append(label)
		print("DEBUG CHECK FAILED: ", label)

func _frames(count: int = 2) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	root.push_input(event)

func _control(node_name: String) -> Control:
	return ui.find_child(node_name, true, false) as Control

func _press(node_name: String) -> void:
	var button: BaseButton = _control(node_name) as BaseButton
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "Enabled button: " + node_name)
	if button != null and button.is_visible_in_tree() and not button.disabled:
		button.pressed.emit()

func _open_debug() -> void:
	if not paused:
		_key(KEY_ESCAPE)
	_press("OpenDebug")

func _select_room(tag: String) -> void:
	var selector: OptionButton = _control("DebugRoom") as OptionButton
	for index: int in selector.item_count:
		if String(selector.get_item_metadata(index)) == tag:
			selector.select(index)
			return
	_check(false, "Room selector contains " + tag)

func _ui_tests() -> void:
	_key(KEY_ESCAPE)
	_check(paused and _control("Pause").visible, "Escape opens pause menu")
	var point: Vector2 = world.player.global_position
	var elapsed: float = world.elapsed
	Input.action_press("move_right")
	await _frames(4)
	Input.action_release("move_right")
	_check(world.player.global_position.is_equal_approx(point) and world.elapsed == elapsed, "Pause freezes player and elapsed time")
	_press("OpenDebug")
	_check(paused and ui.is_debug_open() and not _control("Pause").visible, "Debug replaces pause without resuming")
	var selector: OptionButton = _control("DebugRoom") as OptionButton
	_check(selector.item_count == world.rooms.size() and selector.item_count == 22, "Debug selector includes all 22 loaded rooms")
	_check(String(selector.get_item_metadata(selector.selected)) == world.room_tag, "Debug selector defaults to current room")
	_check(root.gui_get_focus_owner() == selector, "Debug initially focuses room selector")
	var amount: SpinBox = _control("DebugFishAmount") as SpinBox
	_check(amount.min_value == 1.0 and amount.max_value == 999.0 and amount.step == 1.0 and amount.value == 10.0, "Fish input uses bounded integer amounts with default ten")
	var old_count: int = world.player.remaining_transforms
	amount.get_line_edit().text = "17"
	_press("DebugFishAdd")
	_check(world.player.remaining_transforms == old_count + 17 and paused and ui.is_debug_open(), "Add commits typed quantity and keeps gameplay paused")
	var balance: Label = _control("DebugBalance") as Label
	_check(str(world.player.remaining_transforms) in balance.text and ui._remaining == world.player.remaining_transforms, "Debug balance and HUD refresh after fish addition")
	_check(not String((_control("DebugStatus") as Label).text).is_empty(), "Fish operation reports status")
	_key(KEY_ESCAPE)
	_check(paused and not ui.is_debug_open() and _control("Pause").visible, "First Escape returns from debug to pause")
	_check(root.gui_get_focus_owner() == _control("OpenDebug"), "Returning restores debug button focus")
	_key(KEY_ESCAPE)
	_check(not paused and ui._mode == "hud", "Second Escape resumes gameplay")
	_open_debug()
	_key(KEY_ENTER)
	await process_frame
	_check(selector.get_popup().visible, "Keyboard opens the room selection popup")
	selector.get_popup().hide()
	_press("DebugBack")
	_check(paused and not ui.is_debug_open(), "Back button keeps the pause menu open")
	_press("OpenDebug")
	var debug_screen: Control = _control("Debug")
	for index: int in 10:
		_key(KEY_TAB)
		var focused: Control = root.gui_get_focus_owner()
		_check(focused != null and debug_screen.is_ancestor_of(focused), "Tab focus remains inside debug " + str(index))
	_select_room("sublevel_w3l2")
	_press("DebugJump")
	_check(not paused and not ui.is_debug_open() and world.room_tag == "sublevel_w3l2", "Menu jump to snow room resumes gameplay")
	_check(world.player.bird == HeronPlayer.Bird.PENGUIN, "Snow jump uses authored starting form")
	_open_debug()
	_check((_control("DebugFishAdd") as Button).disabled and world.player.remaining_transforms == -1, "Unlimited room disables fish addition")
	_check("不限" in balance.text, "Unlimited balance is shown explicitly")
	main._restart()
	_check(not paused and not ui.is_debug_open() and world.room_tag == "sublevel_w3l2", "Restart clears debug and stays in destination")

func _world_tests() -> void:
	paused = true
	world.resetting = false
	var options: Array[Dictionary] = world.debug_room_options()
	for option: Dictionary in options:
		var tag: String = option["tag"]
		var room: HeronEditableRoom = world.rooms[tag]["node"]
		var spawn: Marker2D = room.get_node("PlayerStart") as Marker2D
		_check(world.debug_jump_to_room(tag), "Jump succeeds: " + tag)
		_check(world.room_tag == tag and world.player.global_position.is_equal_approx(spawn.global_position), "Jump uses authored global spawn: " + tag)
		_check(world.player.bird == room.preview_form and not world.player.dead and not world.player.frozen and world.player.velocity == Vector2.ZERO, "Jump resets movement and form: " + tag)
		_check(world.player.max_transforms == room.transform_limit and world.player.remaining_transforms == room.transform_limit, "Jump uses target initial fish budget: " + tag)
		_check(world.checkpoint_room == tag and world.checkpoint.is_equal_approx(spawn.global_position) and world.checkpoint_bird == room.preview_form, "Jump replaces checkpoint: " + tag)
		var bounds: Rect2 = world.rooms[tag]["rect"]
		_check(world.camera.global_position.is_equal_approx(bounds.get_center()), "Jump immediately positions camera: " + tag)
		world.player.global_position += Vector2(10, -10)
		world.restart()
		_check(world.player.global_position.is_equal_approx(spawn.global_position) and world.room_tag == tag and world.player.bird == room.preview_form, "Restart restores debug checkpoint: " + tag)
	_check(world.player.unlocked_birds.size() == 4, "Debug jump unlocks all forms for this session")
	_check(world.debug_jump_to_room("SUBLEVEL_W1L1"), "Room tags are case insensitive")
	world.player.add_transform_count(30)
	_check(world.debug_jump_to_room(world.room_tag) and world.player.remaining_transforms == 3, "Same-room jump restores authored fish budget")
	var point: Vector2 = world.player.global_position
	var room_tag: String = world.room_tag
	var count: int = world.player.remaining_transforms
	_check(not world.debug_jump_to_room("missing_room"), "Unknown destination is rejected")
	_check(world.player.global_position == point and world.room_tag == room_tag and world.player.remaining_transforms == count, "Invalid jump does not mutate state")
	for amount: int in [-1, 0, 1000]:
		_check(not world.debug_add_fish(amount) and world.player.remaining_transforms == count, "Invalid fish amount is rejected: " + str(amount))
	_check(world.debug_add_fish(999) and world.player.remaining_transforms == count + 999, "Fish addition can exceed initial room budget")
	world.restart()
	_check(world.player.remaining_transforms == count, "Restart preserves normal checkpoint fish rollback")
	world.resetting = true
	_check(not world.debug_jump_to_room("sublevel_w0l1") and not world.debug_add_fish(1), "Debug mutations are rejected during respawn")
	world.resetting = false
	world.finished = true
	_check(not world.debug_jump_to_room("sublevel_w0l1") and not world.debug_add_fish(1), "Debug mutations are rejected after completion")
	world.finished = false
	var source_room: HeronEditableRoom = world.rooms[world.room_tag]["node"]
	var source_checkpoint: HeronWorldObject = source_room.get_node("Actors/BP_CheckPoint_w1l1_1") as HeronWorldObject
	world._on_object_entered(source_checkpoint, world.player)
	_check(world.debug_jump_to_room("sublevel_w3l1"), "Jump can supersede queued interactions")
	await process_frame
	_check(world.checkpoint_room == "sublevel_w3l1" and world.room_tag == "sublevel_w3l1", "Old deferred checkpoint cannot overwrite new destination")
	_check(not world.debug_add_fish(10) and world.player.remaining_transforms == -1, "Unlimited fish remains unlimited")
	_check(world.debug_jump_to_room("sublevel_w3l2"), "Prepare actual debug-checkpoint death")
	world.player.die()
	_check(world.resetting, "Death starts after debug jump")
	_check(not world.debug_jump_to_room("sublevel_w0l1"), "Actual pending death timer blocks jump")
	await create_timer(1.7).timeout
	_check(not world.resetting and not world.player.dead and world.checkpoint_room == "sublevel_w3l2" and world.player.bird == HeronPlayer.Bird.PENGUIN, "Timed death restores debug destination and form")

func _preview_and_cleanup_tests() -> void:
	main.start_game("res://scenes/rooms/w1l1.tscn")
	world = main.world
	await _frames(3)
	_open_debug()
	var selector: OptionButton = _control("DebugRoom") as OptionButton
	_check(world.scene_preview and selector.item_count == 1, "Single-room preview lists only its loaded destination")
	_press("DebugJump")
	_check(world.scene_preview and not paused and world.room_tag == "sublevel_w1l1", "Preview debug jump retains preview session")
	_open_debug()
	main.show_menu()
	_check(not paused and not ui.is_debug_open() and ui._mode == "menu", "Returning to main menu clears debug and pause")
	main.start_game()
	world = main.world
	_check(world.player.unlocked_birds.size() == 1 and world.room_tag == world.initial_room, "Fresh campaign does not retain debug unlocks or destination")
	var count: int = world.player.remaining_transforms
	main._debug_add_fish(10)
	main._debug_jump_to_room("sublevel_w3l2")
	_check(world.player.remaining_transforms == count and world.room_tag == world.initial_room, "Main ignores debug requests outside paused debug screen")

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_game()
	world = main.world
	ui = main.ui
	await _frames(10)
	await _ui_tests()
	await _world_tests()
	await _preview_and_cleanup_tests()
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "coverage": "Pause/debug input and focus, finite/unlimited fish, all authored campaign jump/checkpoint states, death, deferred interactions and room preview. Not a full campaign playthrough."}
	print("HERON_DEBUG_MENU_REGRESSION ", JSON.stringify(report))
	paused = false
	main.queue_free()
	world = null
	ui = null
	main = null
	await create_timer(0.8).timeout
	quit(0 if failures.is_empty() else 1)
