extends Node

var ui: HeronUI
var world: HeronWorld
var audio: HeronAudio
var data: Dictionary = {}
var quitting: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_configure_input()
	var file := FileAccess.open("res://data/world.json", FileAccess.READ)
	if not file:
		push_error("Missing converted original world data")
		get_tree().quit(1)
		return
	data = JSON.parse_string(file.get_as_text())
	audio = HeronAudio.new()
	add_child(audio)
	ui = HeronUI.new()
	add_child(ui)
	ui.start_requested.connect(start_game)
	ui.restart_requested.connect(_restart)
	ui.menu_requested.connect(show_menu)
	ui.resume_requested.connect(_resume)
	ui.quit_requested.connect(_quit_game)
	ui.form_requested.connect(func(form: int) -> void:
		if is_instance_valid(world):
			world.player.try_transform(form)
	)
	show_menu()
	if "--play" in OS.get_cmdline_user_args() or ProjectSettings.has_meta("heron_scene_preview"):
		start_game()
	if "--smoke-test" in OS.get_cmdline_user_args():
		start_game()
		await get_tree().create_timer(2.0).timeout
		print("HERON_RELEASE_SMOKE rooms=", world.rooms.size(), " grounded=", world.player.on_ground)
		_quit_game()

func _configure_input() -> void:
	var keys: Dictionary = {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_W, KEY_UP, KEY_SPACE], "move_down": [KEY_S, KEY_DOWN],
		"action": [KEY_E], "restart": [KEY_R], "pause": [KEY_ESCAPE],
		"heron": [KEY_1], "mallard": [KEY_2], "penguin": [KEY_3], "woodpecker": [KEY_4],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code: int in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
			var logical := InputEventKey.new()
			logical.keycode = code
			if not InputMap.action_has_event(action, logical):
				InputMap.action_add_event(action, logical)

func show_menu() -> void:
	get_tree().paused = false
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
		world = null
	audio.stop_environment()
	ui.show_menu()

func start_game() -> void:
	get_tree().paused = false
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = HeronWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.player_changed.connect(_refresh_hud)
	world.room_changed.connect(ui.update_room)
	world.message_requested.connect(ui.notify)
	world.sound_requested.connect(audio.play_sound)
	world.completed.connect(func(time: float, count: int) -> void: ui.show_victory(time, count))
	ui.show_hud()
	world.load_map(data)
	audio.start_music(true)

func _refresh_hud(player: HeronPlayer) -> void:
	ui.update_player(player.bird, player.unlocked_birds, player.remaining_transforms, player.max_transforms)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(world):
		return
	if event.is_action_pressed("pause") and not world.finished:
		if get_tree().paused:
			_resume()
		else:
			get_tree().paused = true
			ui.show_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and not get_tree().paused:
		world.restart()

func _resume() -> void:
	get_tree().paused = false
	ui.show_hud()
	if is_instance_valid(world):
		_refresh_hud(world.player)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

func _quit_game() -> void:
	if quitting:
		return
	quitting = true
	get_tree().paused = false
	audio.shutdown()
	if is_instance_valid(world):
		world.queue_free()
	ui.queue_free()
	audio.queue_free()
	await get_tree().create_timer(0.25).timeout
	_exit_tree()
	get_tree().quit()

func _exit_tree() -> void:
	HeronPaperAssets._player_frames = null
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._map_cache.clear()
	HeronTileMap._shape_cache.clear()

func _restart() -> void:
	get_tree().paused = false
	if is_instance_valid(world) and world.finished:
		start_game()
		return
	if is_instance_valid(world):
		world.restart()
	ui.show_hud()
