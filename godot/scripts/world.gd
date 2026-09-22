class_name HeronWorld
extends Node2D

signal room_changed(label: String)
signal message_requested(text: String)
signal completed(elapsed: float, deaths: int)
signal player_changed(player: HeronPlayer)
signal sound_requested(kind: String)

var player: HeronPlayer
var camera: Camera2D
var map_data: Dictionary = {}
var objects: Dictionary = {}
var rooms: Dictionary = {}
var limits: Dictionary = {}
var room_tag: String = ""
var checkpoint: Vector2
var checkpoint_room: String = ""
var checkpoint_bird: int = 0
var deaths: int = 0
var elapsed: float = 0.0
var finished: bool = false
var resetting: bool = false
var death_velocity: Vector2 = Vector2.ZERO
var camera_tween: Tween
var waters: Dictionary = {}
var ice: Dictionary = {}
var initial_spawn: Vector2 = Vector2.ZERO
var source_data: Dictionary = {}
var initial_room: String = ""
var loaded_map: String = ""
var depth_layers: Array[Dictionary] = []
var editable_scene: Node2D
var foreground_water: HeronWaterSurface
var scene_preview: bool = false

func load_map(data: Dictionary, map_name: String = "Map/TestYxh1") -> void:
	source_data = data
	loaded_map = map_name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var preview_path: String = String(ProjectSettings.get_meta("heron_scene_preview", ""))
	var scene_path: String = preview_path if not preview_path.is_empty() else "res://scenes/maps/testyxh1.tscn"
	scene_preview = not preview_path.is_empty()
	var use_scene: bool = (scene_preview or map_name == "Map/TestYxh1") and "--data-driven" not in OS.get_cmdline_user_args() and ResourceLoader.exists(scene_path)
	if use_scene:
		_load_editable_scene(scene_path)
	else:
		map_data = data.get("maps", {}).get(map_name, {})
		if map_data.is_empty():
			push_error("Missing original map: " + map_name)
			return
		var gm: Dictionary = map_data.get("game_mode", {})
		for limit: Dictionary in gm.get("TileMapTransformLimits", []):
			limits[String(limit.get("TileMapTag", "")).to_lower()] = int(limit.get("MaxTransformCount", -1))
		initial_room = String(gm.get("DefaultTileMapTag", "SubLevel_w0l1")).to_lower()
		for actor: Dictionary in map_data.get("actors", []):
			var cls: String = actor.get("class", "")
			if cls.ends_with("PaperTileMapActor"):
				_create_tile_map(actor)
			elif cls.ends_with("PlayerStart"):
				initial_spawn = HeronWorldObject.vector(actor.get("position", [0, 0]))
			elif cls.begins_with("/Game/"):
				_create_object(actor)
	camera = Camera2D.new()
	camera.name = "RoomCamera"
	add_child(camera)
	camera.position_smoothing_enabled = false
	foreground_water = HeronWaterSurface.new()
	foreground_water.name = "ForegroundWater"
	add_child(foreground_water)
	player = HeronPlayer.new()
	player.name = "Heron"
	player.z_index = 4
	add_child(player)
	player.setup({
		"speed": 200.0, "jump_speed": 200.0, "gravity": 980.0,
		"jump_hold_time": 0.32, "jump_hold_gravity_scale": 0.5,
		"jump_release_multiplier": 0.5,
		"collision_radius": 8.5, "collision_height": 26.4,
		"sprite_offset": Vector2(0, 14.4), "sprite_scale": Vector2.ONE,
		"glide_speed": 200.0, "glide_gravity_scale": 0.4,
		"max_glide_fall_speed": 100.0,
	}, HeronPaperAssets.player_frames())
	player.died.connect(_on_death)
	player.attack_requested.connect(_on_attack)
	player.form_changed.connect(func(_bird: int) -> void: player_changed.emit(player))
	player.transform_count_changed.connect(func(_remaining: int, _maximum: int) -> void: player_changed.emit(player))
	player.sound_requested.connect(_on_player_sound)
	if scene_preview:
		for form: int in range(4):
			player.unlock_bird(form)
		checkpoint_bird = int(editable_scene.get("preview_form"))
	checkpoint = initial_spawn
	checkpoint_room = initial_room
	player.reset_at(checkpoint, checkpoint_bird)
	change_room(initial_room, true)
	player_changed.emit(player)
	get_viewport().size_changed.connect(_fit_camera)

func _load_editable_scene(path: String) -> void:
	editable_scene = (load(path) as PackedScene).instantiate() as Node2D
	add_child(editable_scene)
	var nodes: Array[Node] = [editable_scene]
	nodes.append_array(editable_scene.find_children("*", "", true, false))
	for node: Node in nodes:
		if node is HeronEditableRoom:
			var room: HeronEditableRoom = node
			var tag: String = room.room_tag.to_lower()
			rooms[tag] = {"rect": room.world_bounds(), "node": room, "label": room.room_tag}
			limits[tag] = room.transform_limit
		if node is HeronWorldObject:
			var object: HeronWorldObject = node
			if object.object_id.is_empty() or objects.has(object.object_id):
				object.object_id = String(editable_scene.get_path_to(object))
			objects[object.object_id] = object
		if node is Node2D and node.has_meta("perspective_depth"):
			depth_layers.append({"node": node, "position": node.global_position, "scale": node.global_scale, "depth": float(node.get_meta("perspective_depth")), "global": true})
	for object: HeronWorldObject in objects.values():
		object.bind_loaded()
		object.entered.connect(_on_object_entered)
		object.exited.connect(_on_object_exited)
	if editable_scene is HeronEditableRoom:
		initial_room = editable_scene.room_tag.to_lower()
	else:
		initial_room = String(editable_scene.get("initial_room_tag")).to_lower()
	var spawn: Marker2D = editable_scene.get_node_or_null("PlayerStart") as Marker2D
	if spawn:
		initial_spawn = spawn.global_position
	elif rooms.has(initial_room):
		var room_node: Node = rooms[initial_room]["node"]
		spawn = room_node.get_node_or_null("PlayerStart") as Marker2D
		initial_spawn = spawn.global_position if spawn else rooms[initial_room]["rect"].get_center()

func _create_tile_map(actor: Dictionary) -> void:
	var p: Dictionary = actor.get("components", {}).get("RenderComponent", {}).get("properties", {})
	var ref: String = p.get("TileMap", "")
	if ref.is_empty():
		return
	var node := HeronTileMap.new()
	node.name = String(actor.get("label", "TileMap")).validate_node_name()
	add_child(node)
	node.position = HeronWorldObject.vector(actor.get("position", [0, 0]))
	node.scale = HeronWorldObject.vector(actor.get("scale", [1, 1]))
	node.rotation = deg_to_rad(float(actor.get("rotation", 0)))
	var depth: int = clampi(roundi(float(actor.get("depth", 0))), -1000, 1000)
	if node.name.begins_with("TileMap_") and node.name.ends_with("_Terrain") and depth <= -12:
		depth = -8
	node.z_index = depth
	node.setup(ref)
	if absf(float(actor.get("depth", 0))) > 100.0:
		depth_layers.append({"node": node, "position": node.position, "scale": node.scale, "depth": float(actor.get("depth", 0))})
	for tag: String in actor.get("tags", []):
		if tag.to_lower().begins_with("sublevel"):
			rooms[tag.to_lower()] = {"rect": node.global_transform * node.local_rect(), "node": node, "label": tag}

func _create_object(actor: Dictionary) -> void:
	var object := HeronWorldObject.new()
	add_child(object)
	object.setup(actor)
	objects[String(actor["id"])] = object
	object.entered.connect(_on_object_entered)
	object.exited.connect(_on_object_exited)
	if object.kind.begins_with("BP_WBP_Tip"):
		var components: Dictionary = actor.get("components", {})
		var p: Dictionary = components.get("Widget", {}).get("properties", {})
		var widget: String = p.get("WidgetClass", "")
		var node: Node2D = object.component_nodes.get("Widget", object)
		var art: Node2D = HeronUI.make_world_tip(widget)
		node.add_child(art)
	elif object.kind == "BP_ItemAddHenshinTimes" and not object.render:
		var label := Label.new()
		label.text = "+%d" % int(object.properties.get("添加次数", 1))
		label.add_theme_font_size_override("font_size", 12)
		label.position = Vector2(-7, -16)
		object.add_child(label)

func _process(_delta: float) -> void:
	if not camera:
		return
	for layer: Dictionary in depth_layers:
		var ratio: float = 1500.0 / maxf(1.0, 1500.0 - float(layer.depth))
		var node: Node2D = layer.node
		if bool(layer.get("global", false)):
			node.global_scale = layer.scale * ratio
			node.global_position = camera.global_position + (Vector2(layer.position) - camera.global_position) * ratio
		else:
			node.scale = layer.scale * ratio
			node.position = camera.position + (Vector2(layer.position) - camera.position) * ratio

func _physics_process(delta: float) -> void:
	if finished or not is_instance_valid(player):
		return
	elapsed += delta
	if resetting:
		death_velocity.y += player.gravity * delta
		player.position += death_velocity * delta
	for object: HeronWorldObject in objects.values():
		object.cooldown = maxf(0.0, object.cooldown - delta)
	_update_doors()
	if not resetting and not player.frozen and rooms.has(room_tag):
		var bounds: Rect2 = rooms[room_tag]["rect"]
		if player.global_position.y > bounds.end.y + 80.0:
			_on_death()

func _on_object_entered(object: HeronWorldObject, body: Node2D) -> void:
	if body != player or not object.active or finished:
		return
	_interact.call_deferred(object)

func _interact(object: HeronWorldObject) -> void:
	if not is_instance_valid(object) or not object.active or finished or resetting:
		return
	match object.kind:
		"BP_CheckPoint":
			checkpoint = object.global_position
			checkpoint_room = room_tag
			checkpoint_bird = player.bird
		"BP_ChangeSubLevelVolume":
			change_room(String(object.properties.get("改为的关卡名", "")))
		"BP_Button":
			if not object.triggered and object.can_press_button(player):
				object.activate_button()
				for path: NodePath in object.linked_doors:
					var door: HeronWorldObject = object.get_node_or_null(path) as HeronWorldObject
					if door:
						door.open_door()
				for key: String in object.properties:
					if key.begins_with("BPDoorRef"):
						for ref: String in object.properties[key]:
							var id: String = ref.get_slice(".", ref.count("."))
							if objects.has(id):
								objects[id].open_door()
				_update_doors()
		"BP_DestructibleWood", "BP_Door", "BP_空气墙":
			pass
		"BP_WaterTriggerVolume":
			waters[object.name] = object
			_update_environment()
		"BP_IceTriggerVolume":
			ice[object.name] = object
			_update_environment()
		"BP_UpVolume":
			if -player.velocity.y > absf(player.velocity.x):
				player.bounce(object.launch_speed)
		"BP_PassGameTriggerVolume":
			finished = true
			player.frozen = true
			completed.emit(elapsed, deaths)
		_:
			if object.kind.begins_with("BP_Spring") and object.cooldown <= 0.0:
				object.cooldown = 0.15
				player.bounce(object.launch_speed)
				object.play_spring()
				sound_requested.emit("spring")
			elif object.kind.begins_with("BP_ItemUnlockBird"):
				var form: int = _bird_id(object.properties.get("BirdType", "EBirdType::Default"))
				player.unlock_bird(form)
				object.set_active(false)
				message_requested.emit("学会了%s的本领" % ["夜鹭", "绿头鸭", "企鹅", "啄木鸟"][form])
				player_changed.emit(player)
			elif object.kind == "BP_ItemAddHenshinTimes":
				player.add_transform_count(int(object.properties.get("添加次数", 1)))
				object.set_active(false)

func _on_object_exited(object: HeronWorldObject, body: Node2D) -> void:
	if body != player:
		return
	if object.kind == "BP_WaterTriggerVolume":
		waters.erase(object.name)
		_update_environment.call_deferred()
	elif object.kind == "BP_IceTriggerVolume":
		ice.erase(object.name)
		_update_environment.call_deferred()

func _update_environment() -> void:
	if is_instance_valid(player):
		player.set_environment(waters.size(), ice.size())

func _update_doors() -> void:
	for object: HeronWorldObject in objects.values():
		if object.kind != "BP_Door" or object.triggered:
			continue
		var all_pressed: bool = true
		for id: String in object.door_buttons:
			if not objects.has(id) or not objects[id].triggered:
				all_pressed = false
		if all_pressed:
			object.open_door()

func _on_player_sound(kind: String) -> void:
	sound_requested.emit(kind)
	if kind.begins_with("transform_"):
		var effect := HeronTransformEffect.new()
		add_child(effect)
		effect.position = player.position
		effect.z_index = 6

func _on_attack(origin: Vector2, facing: int) -> void:
	for height: float in [0.0, 16.0, -16.0]:
		var from: Vector2 = origin + Vector2(0, height)
		var to: Vector2 = from + Vector2(facing * 20.0, 0)
		var candidates: Array[HeronWorldObject] = []
		for object: HeronWorldObject in objects.values():
			if object.kind == "BP_DestructibleWood" and object.active:
				var box: Rect2 = object.world_box().grow(8.0)
				if box.has_point(from) or box.has_point(to) or box.intersects(Rect2(from.min(to), Vector2(absf(to.x - from.x), 0.01))):
					candidates.append(object)
		if not candidates.is_empty():
			candidates.sort_custom(func(a: HeronWorldObject, b: HeronWorldObject) -> bool: return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
			candidates[0].break_wood()
			player.confirm_attack(true)
			return

func change_room(tag: String, instant: bool = false) -> void:
	var canonical: String = tag.to_lower()
	if not rooms.has(canonical):
		push_warning("Unknown original room tag: " + tag)
		return
	if room_tag == canonical and not instant:
		return
	room_tag = canonical
	var room: HeronEditableRoom = rooms[room_tag]["node"] as HeronEditableRoom
	foreground_water.set_room(room.foreground_water_enabled if room else false, room.foreground_waterline if room else 0.78, instant)
	player.set_transform_limit(int(limits.get(room_tag, -1)))
	var rect: Rect2 = rooms[room_tag]["rect"]
	var zoom_value: float = _room_zoom(rect)
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	if instant:
		camera.position = rect.get_center()
		camera.zoom = Vector2.ONE * zoom_value
	else:
		camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		camera_tween.tween_property(camera, "position", rect.get_center(), 1.0)
		camera_tween.tween_property(camera, "zoom", Vector2.ONE * zoom_value, 1.0)
	room_changed.emit(String(rooms[room_tag]["label"]).trim_prefix("SubLevel_").trim_prefix("Sublevel_"))

func _room_zoom(rect: Rect2) -> float:
	var viewport: Vector2 = get_viewport_rect().size
	return minf(viewport.x / maxf(1, rect.size.x), viewport.y / maxf(1, rect.size.y))

func _fit_camera() -> void:
	if camera and rooms.has(room_tag):
		camera.zoom = Vector2.ONE * _room_zoom(rooms[room_tag]["rect"])

func restart() -> void:
	if resetting or finished:
		return
	_respawn()

func _on_death() -> void:
	if resetting or finished:
		return
	resetting = true
	deaths += 1
	player.frozen = true
	player.velocity = Vector2.ZERO
	death_velocity = Vector2(100, -100)
	player.collision.set_deferred("disabled", true)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(player) and is_inside_tree():
		_respawn()

func _respawn() -> void:
	for object: HeronWorldObject in objects.values():
		if object.kind in ["BP_Button", "BP_Door", "BP_DestructibleWood", "BP_ItemAddHenshinTimes"]:
			object.reset_object()
	waters.clear()
	ice.clear()
	death_velocity = Vector2.ZERO
	player.collision.set_deferred("disabled", false)
	player.reset_at(checkpoint, checkpoint_bird)
	change_room(checkpoint_room if rooms.has(checkpoint_room) else initial_room, true)
	resetting = false
	player_changed.emit(player)

static func _bird_id(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var name: String = String(value).get_slice("::", 1).to_lower()
	return {"default": 0, "mallard": 1, "penguin": 2, "woodpecker": 3}.get(name, 0)
