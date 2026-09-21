extends SceneTree

const NativeTiles = preload("res://tools/native_tiles.gd")
const RoomScript = preload("res://scripts/editable_room.gd")
const MapScript = preload("res://scripts/editable_map.gd")
const ObjectScript = preload("res://scripts/world_object.gd")
const ROOM_DIRECTORY: String = "res://scenes/rooms"
const MAP_PATH: String = "res://scenes/maps/testyxh1.tscn"
# Seed settings for the original reed-lined rooms; later edits belong to the room scenes.
const FOREGROUND_WATERLINES: Dictionary = {
	"w0l1": 0.78, "w0l2": 0.78, "w0l3": 0.78, "w0l4": 0.82, "w0l5": 0.78,
	"w0l6": 0.82, "w1l5": 0.78, "w1l6": 0.78, "w1l7": 0.78,
}

var master: Node2D
var room_nodes: Dictionary = {}
var room_bounds: Dictionary = {}
var folder_rooms: Dictionary = {}
var actors_by_id: Dictionary = {}
var data: Dictionary
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_bake")

func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _ensure_directory(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

func _group(parent: Node, group_name: String) -> Node2D:
	var existing: Node2D = parent.get_node_or_null(NodePath(group_name)) as Node2D
	if existing:
		return existing
	var node := Node2D.new()
	node.name = group_name
	parent.add_child(node)
	return node

func _owner_children(node: Node, scene_owner: Node) -> void:
	for child: Node in node.get_children():
		if child.has_meta("world_object"):
			child.remove_meta("world_object")
		child.owner = scene_owner
		_owner_children(child, scene_owner)

func _save_scene(node: Node, path: String) -> bool:
	_owner_children(node, node)
	var scene := PackedScene.new()
	var result: Error = scene.pack(node)
	if result == OK:
		result = ResourceSaver.save(scene, path)
	if result != OK:
		failures.append("Cannot save %s: %s" % [path, error_string(result)])
		return false
	return true

func _room_for(actor: Dictionary) -> Node2D:
	var point: Vector2 = _vector(actor.get("position", [0, 0]))
	var folder: String = String(actor.get("properties", {}).get("FolderGuid", ""))
	if folder_rooms.has(folder):
		var assigned: String = folder_rooms[folder]
		var assigned_bounds: Rect2 = room_bounds[assigned]
		if assigned_bounds.grow(64).has_point(point):
			return room_nodes[assigned]
	var nearest: String = ""
	var distance: float = INF
	for tag: String in room_nodes:
		var rect: Rect2 = room_bounds[tag]
		var current: float = rect.get_center().distance_squared_to(point)
		if rect.grow(8).has_point(point):
			current *= 0.01
		if current < distance:
			distance = current
			nearest = tag
	return room_nodes[nearest]

func _export_frames() -> void:
	_ensure_directory("res://resources/animations")
	var catalog: Dictionary = HeronPaperAssets.load_catalog()
	for ref: String in catalog.get("flipbooks", {}):
		var frames: SpriteFrames = HeronPaperAssets.frames(ref)
		var basename: String = ref.get_file().get_slice(".", 0).validate_filename()
		var path: String = "res://resources/animations/" + basename + "_" + ref.sha256_text().left(8) + ".tres"
		frames.take_over_path(path)
		var result: Error = ResourceSaver.save(frames, path, ResourceSaver.FLAG_CHANGE_PATH)
		if result != OK:
			failures.append("Cannot save animation: " + ref)

func _bake() -> void:
	if FileAccess.file_exists(MAP_PATH) and "--overwrite" not in OS.get_cmdline_user_args():
		push_error("Editable map already exists. Back up designer edits; use --overwrite only to regenerate deliberately.")
		quit(1)
		return
	_ensure_directory(ROOM_DIRECTORY)
	_ensure_directory("res://scenes/maps")
	_export_frames()
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var map_data: Dictionary = data["maps"]["Map/TestYxh1"]
	var source_actors: Array = map_data["actors"]
	var gm: Dictionary = map_data["game_mode"]
	var limits: Dictionary = {}
	for item: Dictionary in gm.get("TileMapTransformLimits", []):
		limits[String(item.TileMapTag).to_lower()] = int(item.MaxTransformCount)
	master = Node2D.new()
	master.set_script(MapScript)
	master.name = "TestYxh1"
	master.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	master.set("initial_room_tag", String(gm.get("DefaultTileMapTag", "SubLevel_w0l1")))
	for actor: Dictionary in source_actors:
		if not String(actor.get("class", "")).ends_with("PaperTileMapActor"):
			continue
		for tag: String in actor.get("tags", []):
			if not tag.to_lower().begins_with("sublevel"):
				continue
			var room := Node2D.new()
			room.set_script(RoomScript)
			var short_name: String = tag.get_slice("_", 1).to_lower()
			room.name = short_name
			room.position = _vector(actor.position)
			room.set("room_tag", tag)
			room.set("transform_limit", int(limits.get(tag.to_lower(), -1)))
			room.set("foreground_water_enabled", FOREGROUND_WATERLINES.has(short_name))
			room.set("foreground_waterline", float(FOREGROUND_WATERLINES.get(short_name, 0.78)))
			room.set("preview_form", 1 if short_name.begins_with("w1") else (3 if short_name.begins_with("w2") else 0))
			master.add_child(room)
			var ref: String = actor.components.RenderComponent.properties.TileMap
			var native: Node2D = NativeTiles.make_map(ref)
			if not native:
				failures.append("Native terrain conversion failed: " + ref)
				continue
			native.free()
			var catalogue: Dictionary = HeronPaperAssets.load_catalog().tilemaps[HeronPaperAssets.resolve_ref(ref)]
			var rect_values: Array = catalogue.rect
			var local := Rect2(float(rect_values[0]), float(rect_values[1]), float(rect_values[2]), float(rect_values[3]))
			var transform := Transform2D(deg_to_rad(float(actor.rotation)), _vector(actor.scale), 0.0, Vector2.ZERO)
			local = transform * local
			room.set("camera_bounds", local)
			room_nodes[tag.to_lower()] = room
			room_bounds[tag.to_lower()] = Rect2(room.position + local.position, local.size)
			var folder: String = String(actor.properties.get("FolderGuid", ""))
			if not folder.is_empty():
				folder_rooms[folder] = tag.to_lower()

	var spawn_position := Vector2(146, -176)
	var tile_count: int = 0
	for actor: Dictionary in source_actors:
		var cls: String = String(actor.get("class", ""))
		if cls.ends_with("PlayerStart"):
			spawn_position = _vector(actor.position)
			continue
		if not cls.ends_with("PaperTileMapActor") and not cls.begins_with("/Game/"):
			continue
		var room: Node2D = _room_for(actor)
		if cls.ends_with("PaperTileMapActor"):
			var ref: String = actor.components.RenderComponent.properties.get("TileMap", "")
			var node: Node2D = NativeTiles.make_map(ref)
			if not node:
				failures.append("Native tile conversion failed: " + ref)
				continue
			var label: String = String(actor.label)
			var category: String = "Background" if label.begins_with("BG_") else ("Foreground" if label.begins_with("FG_") else "Terrain")
			_group(room, category).add_child(node)
			node.name = label.validate_node_name()
			node.position = _vector(actor.position) - room.position
			node.scale = _vector(actor.scale)
			node.rotation = deg_to_rad(float(actor.rotation))
				var depth: int = clampi(roundi(float(actor.depth)), -1000, 1000)
				if label.begins_with("Terrain") and label.ends_with("_0") and depth <= -12:
					depth = -8
				node.z_index = depth
			if absf(float(actor.depth)) > 100:
				node.set_meta("perspective_depth", float(actor.depth))
			tile_count += 1
		elif cls.ends_with("BP_WaterPlane_C"):
			continue
		else:
			var object := Node2D.new()
			object.set_script(ObjectScript)
			_group(room, "Actors").add_child(object)
			object.call("setup", actor)
			object.name = String(actor.label).validate_node_name()
			object.position = _vector(actor.position) - room.position
			actors_by_id[String(actor.id)] = object
			if String(object.get("kind")).begins_with("BP_WBP_Tip"):
				var p: Dictionary = actor.components.get("Widget", {}).get("properties", {})
				var node: Node2D = object.get_node_or_null("Widget") as Node2D
				if node:
					node.add_child(HeronUI.make_world_tip(String(p.get("WidgetClass", ""))))
			elif String(object.get("kind")) == "BP_ItemAddHenshinTimes" and object.get("render") == null:
				var label := Label.new()
				label.name = "AmountLabel"
				label.text = "+%d" % int(object.get("pickup_amount"))
				label.position = Vector2(-7, -16)
				label.add_theme_font_size_override("font_size", 12)
				object.add_child(label)

	for actor: Dictionary in source_actors:
		var id: String = String(actor.get("id", ""))
		if not actors_by_id.has(id):
			continue
		var object: Node2D = actors_by_id[id]
		var buttons: Array[NodePath] = []
		for ref: String in object.get("properties").get("BPButtonRef", []):
			var target: String = ref.get_slice(".", ref.count("."))
			if actors_by_id.has(target):
				buttons.append(object.get_path_to(actors_by_id[target]))
		object.set("linked_buttons", buttons)
		var doors: Array[NodePath] = []
		for key: String in object.get("properties"):
			if key.begins_with("BPDoorRef"):
				for ref: String in object.get("properties")[key]:
					var target: String = ref.get_slice(".", ref.count("."))
					if actors_by_id.has(target):
						doors.append(object.get_path_to(actors_by_id[target]))
		object.set("linked_doors", doors)

	var player_start := Marker2D.new()
	player_start.name = "PlayerStart"
	player_start.position = spawn_position
	master.add_child(player_start)
	var room_paths: Dictionary = {}
	for tag: String in room_nodes:
		var room: Node2D = room_nodes[tag]
		var start := Marker2D.new()
		start.name = "PlayerStart"
		var local: Rect2 = room.get("camera_bounds")
		start.position = local.get_center() - Vector2(0, local.size.y * 0.25)
		var nearest: float = INF
		for actor: Node2D in actors_by_id.values():
			if room.is_ancestor_of(actor) and String(actor.get("kind")) == "BP_CheckPoint":
				var dist: float = actor.position.distance_squared_to(local.get_center())
				if dist < nearest:
					nearest = dist
					start.position = actor.position
		if tag == String(master.get("initial_room_tag")).to_lower():
			start.position = spawn_position - room.position
		room.add_child(start)
		var placement: Vector2 = room.position
		room.position = Vector2.ZERO
		var path: String = ROOM_DIRECTORY.path_join(String(room.name) + ".tscn")
		_save_scene(room, path)
		room.position = placement
		room_paths[tag] = {"path": path, "position": placement, "name": String(room.name)}

	for room: Node in room_nodes.values():
		master.remove_child(room)
		room.free()
	var master_text: String = "[gd_scene load_steps=%d format=3]\n\n" % (room_paths.size() + 2)
	master_text += '[ext_resource type="Script" path="res://scripts/editable_map.gd" id="1_map"]\n'
	var sorted_tags: Array = room_paths.keys()
	sorted_tags.sort()
	for tag: String in sorted_tags:
		var entry: Dictionary = room_paths[tag]
		master_text += '[ext_resource type="PackedScene" path="%s" id="room_%s"]\n' % [entry.path, entry.name]
	master_text += '\n[node name="TestYxh1" type="Node2D"]\ntexture_filter = 1\nscript = ExtResource("1_map")\n'
	master_text += '\n[node name="PlayerStart" type="Marker2D" parent="."]\nposition = Vector2(%s, %s)\n' % [spawn_position.x, spawn_position.y]
	for tag: String in sorted_tags:
		var entry: Dictionary = room_paths[tag]
		var placement: Vector2 = entry.position
		master_text += '\n[node name="%s" parent="." instance=ExtResource("room_%s")]\nposition = Vector2(%s, %s)\n' % [entry.name, entry.name, placement.x, placement.y]
	var master_file := FileAccess.open(MAP_PATH, FileAccess.WRITE)
	if master_file:
		master_file.store_string(master_text)
		master_file.close()
	else:
		failures.append("Cannot write master map")
	var report: Dictionary = {"scene": MAP_PATH, "rooms": room_paths.size(), "tilemap_actors": tile_count, "objects": actors_by_id.size(), "generated": failures.is_empty(), "tests_run": false, "failures": failures}
	FileAccess.open("res://scenes/maps/generation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HERON_EDITABLE_GENERATION ", JSON.stringify(report))
	master.free()
	actors_by_id.clear()
	room_nodes.clear()
	NativeTiles._tileset_cache.clear()
	HeronPaperAssets._frames.clear()
	HeronPaperAssets._atlases.clear()
	HeronPaperAssets._textures.clear()
	HeronTileMap._shape_cache.clear()
	HeronTileMap._map_cache.clear()
	quit(0 if failures.is_empty() else 1)
