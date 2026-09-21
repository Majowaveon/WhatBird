extends RefCounted

static var _tileset_cache: Dictionary[String, TileSet] = {}
static var _saved_directories: Dictionary[String, bool] = {}


static func make_map(ref: String, save_directory: String = "res://resources/tilesets") -> Node2D:
	var key: String = HeronPaperAssets.resolve_ref(ref)
	var maps: Dictionary = HeronPaperAssets.load_catalog().get("tilemaps", {})
	var data: Dictionary = maps.get(key, {})
	if data.is_empty():
		push_error("Unknown PaperTileMap: " + ref)
		return null
	if save_directory.is_empty():
		push_error("Native tile maps require a TileSet save directory.")
		return null
	var directory: String = save_directory.simplify_path()
	var path: String = directory.path_join(_safe_name(key) + "_" + key.sha256_text().left(16) + ".tres")
	var tile_set: TileSet = _tileset_cache.get(path) as TileSet
	if tile_set == null:
		tile_set = _make_tileset(key, data)
		if tile_set == null:
			return null
		if not _saved_directories.has(directory):
			var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			if directory_error != OK:
				push_error("Cannot create TileSet directory %s: %s" % [directory, error_string(directory_error)])
				return null
			_saved_directories[directory] = true
		tile_set.take_over_path(path)
		var save_error: Error = ResourceSaver.save(tile_set, path, ResourceSaver.FLAG_CHANGE_PATH)
		if save_error != OK:
			push_error("Cannot save native TileSet %s: %s" % [path, error_string(save_error)])
			return null
		_tileset_cache[path] = tile_set

	var bounds: Array = data.get("rect", [0, 0, 0, 0])
	var ppu: float = maxf(float(data.get("ppu", 1.0)), 0.000001)
	var cell_size: Vector2i = tile_set.tile_size
	var source_ids: Dictionary = tile_set.get_meta("source_ids", {})
	var atlas_sources: Array = tile_set.get_meta("atlas_sources", [])
	var terrain_textures: PackedStringArray = tile_set.get_meta("terrain_textures", PackedStringArray())
	var result: Node2D = Node2D.new()
	result.name = key.get_file().get_slice(".", 0).validate_node_name()
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.set_meta("source_ref", key)
	result.set_meta("original_bounds", Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3])))
	result.set_meta("map_size", Vector2i(int(data.get("width", 0)), int(data.get("height", 0))))
	result.set_meta("tile_size", cell_size)
	result.set_meta("ppu", ppu)
	result.set_meta("tileset_path", path)
	result.set_meta("source_ids", source_ids)
	result.set_meta("atlas_sources", atlas_sources)
	result.set_meta("terrain_textures", terrain_textures)
	var sets: Dictionary = HeronPaperAssets.load_catalog().get("tilesets", {})
	var layers: Array = data.get("layers", [])
	var collision_enabled: bool = String(data.get("collision_domain", "Use3DPhysics")) != "None"
	for index: int in range(layers.size()):
		var layer_data: Dictionary = layers[index]
		var layer: TileMapLayer = TileMapLayer.new()
		var display_name: String = String(layer_data.get("display_name", layer_data.get("name", "Layer")))
		layer.name = display_name.validate_node_name()
		if String(layer.name).is_empty():
			layer.name = "Layer%d" % index
		layer.tile_set = tile_set
		# Keep the returned root unscaled so room placement can set its transform freely.
		layer.scale = Vector2.ONE / ppu
		layer.position = -Vector2(cell_size) * 0.5 / ppu
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.z_index = clampi(-roundi(index * float(data.get("separation_per_layer", 4))), -4096, 4096)
		var tint: Array = layer_data.get("color", [1, 1, 1, 1])
		layer.modulate = Color(float(tint[0]), float(tint[1]), float(tint[2]), float(tint[3]))
		layer.visible = not bool(layer_data.get("hidden_in_game", false))
		layer.collision_enabled = collision_enabled and bool(layer_data.get("collides", true))
		layer.set_meta("source_ref", key)
		layer.set_meta("original_layer_index", index)
		layer.set_meta("original_name", display_name)
		layer.set_meta("map_size", Vector2i(int(layer_data.get("width", data.get("width", 0))), int(layer_data.get("height", data.get("height", 0)))))
		result.add_child(layer, true)
		layer.owner = result
		for cell: Array in layer_data.get("cells", []):
			if cell.size() < 5:
				push_error("Invalid PaperTileMap cell in " + key)
				result.free()
				return null
			var set_ref: String = HeronPaperAssets.resolve_ref(String(cell[2]))
			if not source_ids.has(set_ref):
				push_error("Missing native atlas for " + set_ref)
				result.free()
				return null
			var source_id: int = int(source_ids[set_ref])
			var set_data: Dictionary = sets.get(set_ref, {})
			var columns: int = maxi(int(set_data.get("columns", 1)), 1)
			var tile: int = int(cell[3])
			var coords: Vector2i = Vector2i(tile % columns, floori(float(tile) / columns))
			var atlas: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
			if tile < 0 or atlas == null or not atlas.has_tile(coords):
				push_error("Invalid atlas tile %d in %s" % [tile, set_ref])
				result.free()
				return null
			layer.set_cell(Vector2i(int(cell[0]), int(cell[1])), source_id, coords, _alternative(int(cell[4])))
	return result


static func _make_tileset(ref: String, data: Dictionary) -> TileSet:
	var cell_size: Vector2i = Vector2i(_vector(data.get("tile_size", [32, 32])))
	if cell_size.x <= 0 or cell_size.y <= 0:
		push_error("Invalid PaperTileMap grid: " + ref)
		return null
	var sets: Dictionary = HeronPaperAssets.load_catalog().get("tilesets", {})
	var refs: Array[String] = []
	# Matching atlases also make blank layers and maps useful immediately in the editor.
	for set_ref: String in sets:
		var set_data: Dictionary = sets[set_ref]
		if Vector2i(_vector(set_data.get("tile_size", [32, 32]))) == cell_size:
			refs.append(set_ref)
	for layer: Dictionary in data.get("layers", []):
		for cell: Array in layer.get("cells", []):
			if cell.size() < 5:
				push_error("Invalid PaperTileMap cell in " + ref)
				return null
			var set_ref: String = HeronPaperAssets.resolve_ref(String(cell[2]))
			if not refs.has(set_ref):
				refs.append(set_ref)
	refs.sort()
	var result: TileSet = TileSet.new()
	result.resource_name = ref.get_file().get_slice(".", 0)
	result.tile_size = cell_size
	var collision_enabled: bool = String(data.get("collision_domain", "Use3DPhysics")) != "None"
	if collision_enabled:
		result.add_physics_layer()
		result.set_physics_layer_collision_layer(0, 1)
		result.set_physics_layer_collision_mask(0, 2)
	var source_ids: Dictionary[String, int] = {}
	var atlas_sources: Array[Dictionary] = []
	var terrain_textures: PackedStringArray = PackedStringArray()
	for source_id: int in range(refs.size()):
		var set_ref: String = refs[source_id]
		var set_data: Dictionary = sets.get(set_ref, {})
		if set_data.is_empty():
			push_error("Unknown PaperTileSet: " + set_ref)
			return null
		var descriptor: Dictionary = _add_atlas(result, set_ref, set_data, source_id, collision_enabled)
		if descriptor.is_empty():
			return null
		source_ids[set_ref] = source_id
		atlas_sources.append(descriptor)
		var texture_path: String = String(descriptor["texture"])
		if bool(descriptor["has_collision"]) and not terrain_textures.has(texture_path):
			terrain_textures.append(texture_path)
	result.set_meta("source_ref", ref)
	result.set_meta("source_ids", source_ids)
	result.set_meta("atlas_sources", atlas_sources)
	result.set_meta("terrain_textures", terrain_textures)
	return result


static func _add_atlas(target: TileSet, ref: String, data: Dictionary, source_id: int, collision_enabled: bool) -> Dictionary:
	var texture_path: String = String(data.get("texture", ""))
	var texture: Texture2D = HeronPaperAssets.texture(texture_path)
	if texture == null:
		push_error("Missing native TileSet texture: " + texture_path)
		return {}
	var size: Vector2i = Vector2i(_vector(data.get("tile_size", [32, 32])))
	if size.x <= 0 or size.y <= 0:
		push_error("Invalid PaperTileSet tile size: " + ref)
		return {}
	var margin: Array = data.get("margin", [0, 0, 0, 0])
	var spacing: Vector2i = Vector2i(_vector(data.get("spacing", [0, 0])))
	var drawing_offset: Vector2 = _vector(data.get("drawing_offset", [0, 0]))
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.resource_name = ref.get_file().get_slice(".", 0)
	atlas.texture = texture
	atlas.texture_region_size = size
	atlas.margins = Vector2i(int(margin[0]), int(margin[1]))
	atlas.separation = spacing
	atlas.use_texture_padding = false
	var grid: Vector2i = atlas.get_atlas_grid_size()
	var columns: int = maxi(int(data.get("columns", grid.x)), 1)
	grid.x = mini(grid.x, columns)
	grid.y = mini(grid.y, maxi(int(data.get("rows", grid.y)), 0))
	if grid.x <= 0 or grid.y <= 0:
		push_error("Empty PaperTileSet atlas grid: " + ref)
		return {}
	target.add_source(atlas, source_id)
	var cell_size: Vector2 = Vector2(target.tile_size)
	var alignment: Vector2 = Vector2((size.x - cell_size.x) * 0.5, (cell_size.y - size.y) * 0.5)
	# Godot subtracts texture_origin; Paper aligns the sprite's bottom-left to the cell.
	var texture_origin: Vector2i = Vector2i(-(drawing_offset + alignment))
	var authored_tiles: Dictionary = data.get("tiles", {})
	var has_collision: bool = false
	for y: int in range(grid.y):
		for x: int in range(grid.x):
			var coords: Vector2i = Vector2i(x, y)
			var tile: int = y * columns + x
			atlas.create_tile(coords)
			var tile_data: TileData = atlas.get_tile_data(coords, 0)
			tile_data.texture_origin = texture_origin
			var authored_tile: Dictionary = authored_tiles.get(str(tile), {})
			var authored_collision: Array = authored_tile.get("collision", [])
			has_collision = has_collision or not authored_collision.is_empty()
			if not collision_enabled:
				continue
			var shapes: Array = HeronTileMap._tile_shapes(ref, data, tile, 0)
			tile_data.set_collision_polygons_count(0, shapes.size())
			for shape_index: int in range(shapes.size()):
				var shape: ConvexPolygonShape2D = shapes[shape_index] as ConvexPolygonShape2D
				var polygon: PackedVector2Array = shape.points.duplicate()
				# Collision deliberately excludes Paper's drawing_offset, as in the mesh path.
				for point_index: int in range(polygon.size()):
					polygon[point_index] += alignment
				tile_data.set_collision_polygon_points(0, shape_index, polygon)
	var descriptor: Dictionary = {
		"source_id": source_id,
		"source_ref": ref,
		"texture": texture_path,
		"tile_size": size,
		"grid_size": grid,
		"columns": columns,
		"margins": atlas.margins,
		"separation": spacing,
		"drawing_offset": drawing_offset,
		"has_collision": has_collision,
	}
	atlas.set_meta("source_ref", ref)
	atlas.set_meta("atlas_info", descriptor)
	return descriptor


static func _alternative(flags: int) -> int:
	var alternative: int = 0
	if (flags & 4) != 0:
		alternative |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if (flags & 2) != 0:
		alternative |= TileSetAtlasSource.TRANSFORM_FLIP_V
	if (flags & 1) != 0:
		alternative |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
	return alternative


static func _safe_name(ref: String) -> String:
	var base: String = ref.get_file().get_slice(".", 0)
	var result: String = ""
	for index: int in range(mini(base.length(), 64)):
		var code: int = base.unicode_at(index)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95:
			result += base.substr(index, 1)
		elif not result.ends_with("_"):
			result += "_"
	return "TileMap" if result.is_empty() else result


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
