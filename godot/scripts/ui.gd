class_name HeronUI
extends CanvasLayer

signal start_requested
signal restart_requested
signal menu_requested
signal resume_requested
signal quit_requested
signal form_requested(form: int)

const ASSETS := "res://assets/"
const PROMPTS := ASSETS + "Resources/1-bit-input-prompts-pixel-16/Tiles__White_/"
const CHOICE_BOX := ASSETS + "Resources/Ninja_Adventure_-_Asset_Pack/Ui/Dialog/ChoiceBox.png"
const FONT_BASE := ASSETS + "Fonts/fusion-pixel-10px-monospaced-zh_hans"
const BIRD_NAMES := ["夜鹭", "绿头鸭", "企鹅", "啄木鸟"]
const BIRD_ACTIONS := ["heron", "mallard", "penguin", "woodpecker"]
const DEFAULT_CONTROLS := {
	"move_left": "A / Left", "move_right": "D / Right",
	"jump": "W / Up / Space", "action": "E", "restart": "R",
	"heron": "1", "mallard": "2", "penguin": "3", "woodpecker": "4",
	"pause": "Escape",
}

var _root: Control
var _menu: Control
var _hud: Control
var _pause: Control
var _victory: Control
var _credits: Control
var _title: Label
var _menu_buttons: VBoxContainer
var _start_button: Button
var _credits_button: Button
var _resume_button: Button
var _victory_button: Button
var _victory_stats: Label
var _credits_image: TextureRect
var _credits_close: TextureButton
var _portrait: TextureButton
var _charges: HBoxContainer
var _form_picker: VBoxContainer
var _form_buttons: Array[Button] = []
var _toast: Label
var _toast_timer: Timer
var _controls: Dictionary = DEFAULT_CONTROLS.duplicate()
var _bird: int = 0
var _unlocked: Array = [0]
var _remaining: int = -1
var _maximum: int = -1
var _room_name: String = ""
var _mode: String = "menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_ensure_ui()
	show_menu()


func show_menu() -> void:
	_ensure_ui()
	_set_mode("menu")
	_room_name = ""
	_toast_timer.stop()
	_start_button.grab_focus()


func show_hud() -> void:
	_ensure_ui()
	_set_mode("hud")
	_refresh_player()


func update_player(bird: int, unlocked: Array, remaining: int, maximum: int) -> void:
	_bird = clampi(bird, 0, BIRD_NAMES.size() - 1)
	_unlocked = unlocked.duplicate()
	_remaining = remaining
	_maximum = maximum
	_ensure_ui()
	_refresh_player()


func update_room(label: String) -> void:
	_room_name = label
	if is_instance_valid(_portrait):
		_refresh_tooltips()


func show_pause() -> void:
	_ensure_ui()
	_set_mode("pause")
	_resume_button.grab_focus()


func show_victory(elapsed: float, deaths: int) -> void:
	_ensure_ui()
	var seconds := maxi(0, int(elapsed))
	_victory_stats.text = "用时 %02d:%02d   失误 %d" % [floori(seconds / 60.0), seconds % 60, maxi(0, deaths)]
	_set_mode("victory")
	_victory_button.grab_focus()


func notify(message: String) -> void:
	_ensure_ui()
	_toast.text = message
	_toast.visible = not message.is_empty() and _mode == "hud"
	if message.is_empty():
		_toast_timer.stop()
	else:
		_toast_timer.start(4.0)


func set_controls(config: Dictionary) -> void:
	_controls = DEFAULT_CONTROLS.duplicate()
	for action: String in DEFAULT_CONTROLS:
		if config.has(action):
			_controls[action] = config[action]
	if is_instance_valid(_portrait):
		_refresh_tooltips()


func _ensure_ui() -> void:
	if is_instance_valid(_root):
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "HeronInterface"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	for extension: String in [".otf", ".ttf"]:
		var font_path := FONT_BASE + extension
		if ResourceLoader.exists(font_path):
			var font := load(font_path) as Font
			if font != null:
				theme.default_font = font
				break
	theme.default_font_size = 24
	_root.theme = theme
	_build_menu()
	_build_hud()
	_build_pause()
	_build_victory()
	_build_credits()
	_toast = _label("", 24)
	_toast.name = "Notification"
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_left = 24.0
	_toast.offset_right = -24.0
	_toast.offset_top = -112.0
	_toast.offset_bottom = -24.0
	_toast.hide()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_toast.hide)
	add_child(_toast_timer)
	_root.resized.connect(_layout)
	_layout()


func _build_menu() -> void:
	_menu = _screen("MainMenu", true)
	var background := _image(ASSETS + "UI/T_background.png")
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_menu.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = _label("啥鸟?!", 86)
	_title.name = "Title"
	_title.add_theme_color_override("font_color", Color(1.0, 0.942085, 0.388535))
	_title.add_theme_constant_override("outline_size", 0)
	_menu.add_child(_title)
	_menu_buttons = VBoxContainer.new()
	_menu_buttons.add_theme_constant_override("separation", 4)
	_menu.add_child(_menu_buttons)
	_start_button = _button("开始", func() -> void: start_requested.emit(), Vector2(150, 50))
	_menu_buttons.add_child(_start_button)
	_credits_button = _button("致谢", _show_credits, Vector2(150, 50))
	_menu_buttons.add_child(_credits_button)
	_menu_buttons.add_child(_button("退出", func() -> void: quit_requested.emit(), Vector2(150, 50)))


func _build_hud() -> void:
	_hud = _screen("HUD")
	_portrait = TextureButton.new()
	_portrait.name = "Portrait"
	_portrait.ignore_texture_size = true
	_portrait.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.focus_mode = Control.FOCUS_NONE
	_portrait.position = Vector2(48, 16)
	_portrait.size = Vector2(88, 88)
	_portrait.pressed.connect(_toggle_forms)
	_hud.add_child(_portrait)
	_charges = HBoxContainer.new()
	_charges.name = "TransformationCharges"
	_charges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charges.position = Vector2(144, 34)
	_charges.add_theme_constant_override("separation", 8)
	_hud.add_child(_charges)
	_form_picker = VBoxContainer.new()
	_form_picker.name = "Forms"
	_form_picker.position = Vector2(48, 112)
	_form_picker.add_theme_constant_override("separation", 4)
	_hud.add_child(_form_picker)
	for form: int in range(BIRD_NAMES.size()):
		var button := _button(BIRD_NAMES[form], _request_form.bind(form), Vector2(192, 44))
		button.toggle_mode = true
		_form_picker.add_child(button)
		_form_buttons.append(button)
	_form_picker.hide()


func _build_pause() -> void:
	_pause = _screen("Pause", true)
	_dim(_pause)
	var column := _center_column(_pause, Vector2(320, 320))
	column.add_child(_label("暂停", 48))
	_resume_button = _button("继续", func() -> void: resume_requested.emit())
	column.add_child(_resume_button)
	column.add_child(_button("重新开始", func() -> void: restart_requested.emit()))
	column.add_child(_button("返回主菜单", func() -> void: menu_requested.emit()))
	column.add_child(_button("退出", func() -> void: quit_requested.emit()))


func _build_victory() -> void:
	_victory = _screen("Victory", true)
	_dim(_victory)
	var column := _center_column(_victory, Vector2(320, 310))
	column.add_child(_label("游戏已通关!", 48))
	_victory_stats = _label("", 24)
	_victory_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_victory_stats.custom_minimum_size.y = 48.0
	column.add_child(_victory_stats)
	_victory_button = _button("重新开始", func() -> void: restart_requested.emit())
	column.add_child(_victory_button)
	column.add_child(_button("返回主菜单", func() -> void: menu_requested.emit()))
	column.add_child(_button("退出", func() -> void: quit_requested.emit()))


func _build_credits() -> void:
	_credits = _screen("Credits", true)
	_dim(_credits)
	_credits_image = _image(ASSETS + "UI/T_credits.png")
	_credits.add_child(_credits_image)
	_credits_close = TextureButton.new()
	_credits_close.name = "CloseCredits"
	_credits_close.texture_normal = _texture(ASSETS + "UI/T_close.png")
	_credits_close.ignore_texture_size = true
	_credits_close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_credits_close.tooltip_text = "关闭"
	_credits_close.pressed.connect(_hide_credits)
	_credits_close.mouse_entered.connect(func() -> void: _credits_close.self_modulate = Color(0.8, 0.8, 0.8))
	_credits_close.mouse_exited.connect(func() -> void: _credits_close.self_modulate = Color.WHITE)
	_credits.add_child(_credits_close)
	_credits.hide()


func _set_mode(mode: String) -> void:
	_mode = mode
	_menu.visible = mode == "menu"
	_hud.visible = mode in ["hud", "pause", "victory"]
	_pause.visible = mode == "pause"
	_victory.visible = mode == "victory"
	_credits.hide()
	_set_menu_enabled(true)
	_form_picker.hide()
	_toast.hide()
	var focused := _root.get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()


func _layout() -> void:
	var viewport_size := _root.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# Preserve the original right-side menu without cropping its title on narrow windows.
	var title_width := minf(380.0, maxf(_title.get_minimum_size().x, viewport_size.x - 32.0))
	var title_center := clampf(viewport_size.x * 0.80, title_width * 0.5 + 16.0, viewport_size.x - title_width * 0.5 - 16.0)
	_title.position = Vector2(title_center - title_width * 0.5, minf(viewport_size.y * 0.30, viewport_size.y - 310.0))
	_title.size = Vector2(title_width, 112)
	_menu_buttons.position = Vector2(clampf(viewport_size.x * 0.90 - 75.0, 16.0, viewport_size.x - 166.0), minf(viewport_size.y * 0.55, viewport_size.y - 174.0))
	_menu_buttons.size = Vector2(150, 158)
	var credits_scale := minf(1.0, minf((viewport_size.x - 32.0) / 1080.0, (viewport_size.y - 32.0) / 705.0))
	var credits_size := Vector2(1080, 705) * maxf(0.01, credits_scale)
	_credits_image.size = credits_size
	_credits_image.position = (viewport_size - credits_size) * 0.5
	_credits_close.size = Vector2(48, 48) * credits_scale
	_credits_close.position = _credits_image.position + Vector2(995, 28) * credits_scale
	_refresh_charges()


func _refresh_player() -> void:
	_portrait.texture_normal = _texture(ASSETS + "UI/T_avatar_normal.png" if _bird == 0 else ASSETS + "UI/T_avatar_henshin.png")
	for form: int in range(_form_buttons.size()):
		var button := _form_buttons[form]
		button.disabled = (form != 0 and not _unlocked.has(form)) or form == _bird or _remaining == 0
		button.set_pressed_no_signal(form == _bird)
	_refresh_charges()
	_refresh_tooltips()


func _refresh_charges() -> void:
	for child: Node in _charges.get_children():
		_charges.remove_child(child)
		child.queue_free()
	# Unlimited rooms have no bar in the original HUD. Pickups can exceed the room limit.
	if _remaining < 0:
		return
	var available := maxf(36.0, _root.size.x - _charges.position.x - 32.0)
	var capacity := maxi(1, mini(12, int((available - 88.0) / 36.0)))
	var count := mini(_remaining, capacity)
	for index: int in range(count):
		var icon := _image(ASSETS + "UI/T_avatar_henshin_icon.png")
		icon.custom_minimum_size = Vector2(28, 44)
		_charges.add_child(icon)
	if _remaining > count:
		var overflow := _label("+%d" % (_remaining - count), 24)
		overflow.custom_minimum_size = Vector2(80, 44)
		_charges.add_child(overflow)
	_charges.size = Vector2.ZERO


func _refresh_tooltips() -> void:
	var charges_text := "变身次数不限" if _remaining < 0 else "剩余变身次数 %d" % _remaining
	if _remaining >= 0 and _maximum >= 0:
		charges_text += " (初始 %d)" % _maximum
	_portrait.tooltip_text = "%s\n%s" % [BIRD_NAMES[_bird], charges_text]
	if not _room_name.is_empty():
		_portrait.tooltip_text += "\n" + _room_name
	for form: int in range(_form_buttons.size()):
		_form_buttons[form].text = "%s  %s" % [_binding(BIRD_ACTIONS[form]), BIRD_NAMES[form]]
		_form_buttons[form].tooltip_text = BIRD_NAMES[form] if form == 0 or _unlocked.has(form) else "尚未解锁"
	_resume_button.tooltip_text = _binding("pause")


func _binding(action: String) -> String:
	var value: Variant = _controls.get(action, "")
	if value is Array or value is PackedStringArray:
		var labels := PackedStringArray()
		for item: Variant in value:
			labels.append(str(item))
		return " / ".join(labels)
	return str(value)


func _toggle_forms() -> void:
	if _mode == "hud":
		_form_picker.visible = not _form_picker.visible
		if not _form_picker.visible:
			_portrait.release_focus()


func _request_form(form: int) -> void:
	if _mode != "hud" or _remaining == 0 or form == _bird:
		return
	if form != 0 and not _unlocked.has(form):
		return
	_form_picker.hide()
	_form_buttons[form].release_focus()
	form_requested.emit(form)


func _show_credits() -> void:
	if _mode == "menu":
		_set_menu_enabled(false)
		_credits.show()
		_credits_close.grab_focus()


func _hide_credits() -> void:
	_credits.hide()
	_set_menu_enabled(true)
	if _mode == "menu":
		_credits_button.grab_focus()


func _set_menu_enabled(enabled: bool) -> void:
	for child: Node in _menu_buttons.get_children():
		var button := child as Button
		if button != null:
			button.disabled = not enabled
			button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_root) or not event.is_action_pressed("pause") or event.is_echo():
		return
	# Only dismiss local popups here; main.gd owns Escape, gameplay input and tree.paused.
	if _credits.visible:
		_hide_credits()
		get_viewport().set_input_as_handled()
	elif _form_picker.visible:
		_form_picker.hide()
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and _form_picker.is_ancestor_of(focused):
			focused.release_focus()
		get_viewport().set_input_as_handled()


func _screen(node_name: String, blocks_mouse: bool = false) -> Control:
	var screen := Control.new()
	screen.name = node_name
	screen.mouse_filter = Control.MOUSE_FILTER_STOP if blocks_mouse else Control.MOUSE_FILTER_IGNORE
	_root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.hide()
	return screen


func _dim(parent: Control) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.3)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _center_column(parent: Control, dimensions: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.custom_minimum_size = dimensions
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	return column


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.10, 0.14, 0.12, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _image(path: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = _texture(path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _button(text: String, callback: Callable, dimensions: Vector2 = Vector2(256, 48)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = dimensions
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.65, 0.65, 0.65))
	button.add_theme_color_override("font_outline_color", Color(0.20, 0.20, 0.20))
	button.add_theme_constant_override("outline_size", 3)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxTexture.new()
		style.texture = _texture(CHOICE_BOX)
		style.texture_margin_left = 4.0
		style.texture_margin_right = 4.0
		style.texture_margin_top = 4.0
		style.texture_margin_bottom = 4.0
		style.content_margin_left = 14.0
		style.content_margin_right = 14.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
		style.modulate_color = Color(0.5, 0.5, 0.5) if state == "normal" else Color.WHITE
		if state == "disabled":
			style.modulate_color = Color(0.3, 0.3, 0.3)
		elif state == "pressed":
			style.modulate_color = Color(0.8, 0.8, 0.8)
		elif state == "focus":
			style.draw_center = false
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("Missing original UI texture: " + path)
	return null


static func make_world_tip(widget_ref: String, draw_size: Vector2 = Vector2(500, 500), pivot: Vector2 = Vector2(0.5, 0.5)) -> Node2D:
	var tip := Node2D.new()
	tip.name = "OriginalWorldTip"
	tip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Source WidgetTree slots, not stale generated _C trees. Widget component scales are external.
	# The render target origin is DrawSize * Pivot; individual images retain UMG pixel geometry.
	var origin := -draw_size * pivot
	if "WBP_TipHenshinBtn3" in widget_ref:
		_tip_image(tip, ASSETS + "UI/T_avatar_henshin.png", origin + Vector2(124, 0), Vector2(80, 80))
		_tip_image(tip, ASSETS + "UI/T_avatar_normal.png", origin + Vector2(4, 0), Vector2(80, 80))
		_tip_image(tip, PROMPTS + "tile_0359.png", origin + Vector2(40, 84), Vector2(70, 70))
		_tip_image(tip, ASSETS + "Resources/Interactable/Wood/Wood.png", origin + Vector2(112, 84), Vector2(60, 60), Rect2(96, 0, 32, 32))
		_tip_image(tip, PROMPTS + "tile_0326.png", origin + Vector2(72, 8), Vector2(70, 70))
	elif "WBP_TipHenshin" in widget_ref:
		_tip_image(tip, PROMPTS + "tile_0324.png", origin + Vector2(72, 44), Vector2(60, 60))
		_tip_image(tip, ASSETS + "UI/T_avatar_henshin.png", origin + Vector2(120, 32), Vector2(80, 80))
		_tip_image(tip, ASSETS + "UI/T_avatar_normal.png", origin + Vector2(0, 32), Vector2(80, 80))
	elif "WBP_TipMovement" in widget_ref:
		# The stretched dialogue brush has zero opacity in the source widget and is omitted.
		_tip_image(tip, PROMPTS + "tile_0509.png", origin + Vector2(268, 96), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0508.png", origin + Vector2(208, 96), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0507.png", origin + Vector2(148, 96), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0394.png", origin + Vector2(80, 92), Vector2(70, 70))
		_tip_image(tip, PROMPTS + "tile_0392.png", origin + Vector2(12, 92), Vector2(70, 70))
	elif "WBP_TipReset" in widget_ref:
		_tip_image(tip, PROMPTS + "tile_0360.png", origin + Vector2(40, 56), Vector2(70, 70))
		_tip_image(tip, PROMPTS + "tile_0574.png", origin + Vector2(128, 52), Vector2(70, 70))
		_tip_image(tip, PROMPTS + "tile_0572.png", origin + Vector2(168, 56), Vector2(70, 70))
	elif "WBP_TipSlide" in widget_ref:
		_tip_image(tip, ASSETS + "UI/T_avatar_normal.png", origin + Vector2(16, 100), Vector2(133.094208, 136.208435))
		_tip_image(tip, PROMPTS + "tile_0507.png", origin + Vector2(132, 140), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0508.png", origin + Vector2(192, 140), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0509.png", origin + Vector2(252, 140), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0509.png", origin + Vector2(432.395935, 140.616001), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0508.png", origin + Vector2(374.683945, 140.616001), Vector2(60, 60))
		_tip_image(tip, PROMPTS + "tile_0507.png", origin + Vector2(314.683945, 140.616001), Vector2(60, 60))
	elif not widget_ref.is_empty():
		push_warning("Unknown original tutorial widget: " + widget_ref)
	return tip


static func _tip_image(parent: Node2D, path: String, top_left: Vector2, dimensions: Vector2, atlas_region: Rect2 = Rect2()) -> void:
	var texture := _texture(path)
	if texture == null:
		return
	var sprite := Sprite2D.new()
	var texture_size := texture.get_size()
	if atlas_region.has_area():
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = atlas_region
		texture = atlas
		texture_size = atlas_region.size
	sprite.texture = texture
	sprite.centered = false
	sprite.position = top_left
	sprite.scale = dimensions / texture_size
	parent.add_child(sprite)
