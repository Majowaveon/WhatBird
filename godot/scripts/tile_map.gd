class_name HeronTileMap
extends Node2D

# Paper2D's UV order is bottom-left, bottom-right, top-right, top-left.
const UV_PERMUTATIONS: Array = [
	[0, 1, 2, 3], [2, 1, 0, 3], [3, 2, 1, 0], [3, 0, 1, 2],
	[1, 0, 3, 2], [1, 2, 3, 0], [2, 3, 0, 1], [0, 3, 2, 1],
]
const TRIANGLE_CORNERS: Array[int] = [1, 2, 0, 2, 3, 0]

static var _map_cache: Dictionary = {}
static var _shape_cache: Dictionary = {}

var _pixels: Node2D
var _rect: Rect2 = Rect2()


func setup(ref: String) -> void:
	if is_instance_valid(_pixels):
		remove_child(_pixels)
		_pixels.queue_free()
	_rect = Rect2()
	var key: String = HeronPaperAssets.resolve_ref(ref)
	var data: Dictionary = HeronPaperAssets.load_catalog().get("tilemaps", {}).get(key, {})
	if data.is_empty():
		push_error("Unknown PaperTileMap: " + ref)
		return
	var bounds: Array = data.get("rect", [0, 0, 0, 0])
	_rect = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
	_pixels = Node2D.new()
	_pixels.name = "PaperPixels"
	_pixels.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixels.scale = Vector2.ONE / maxf(float(data.get("ppu", 1)), 0.000001)
	add_child(_pixels)
	if not _map_cache.has(key):
		_map_cache[key] = _bake_map(data)
	for layer: Dictionary in _map_cache[key]:
		var drawing := Node2D.new()
		drawing.name = String(layer["name"]).validate_node_name()
		drawing.z_index = int(layer["z"])
		drawing.modulate = layer["color"]
		drawing.visible = not bool(layer["hidden"])
		_pixels.add_child(drawing)
		for batch: Dictionary in layer["batches"]:
			var mesh := MeshInstance2D.new()
			mesh.mesh = batch["mesh"] as ArrayMesh
			mesh.texture = HeronPaperAssets.texture(String(batch["texture"]))
			drawing.add_child(mesh)
		var collisions: Array = layer["collisions"]
		if not collisions.is_empty():
			var body := StaticBody2D.new()
			body.name = "TerrainCollision"
			body.collision_layer = 1
			body.collision_mask = 2
			drawing.add_child(body)
			# Shape owners avoid creating a node for every painted cell.
			for cell: Dictionary in collisions:
				var owner_id: int = body.create_shape_owner(body)
				body.shape_owner_set_transform(owner_id, Transform2D(0.0, cell["position"]))
				for shape: Shape2D in cell["shapes"]:
					body.shape_owner_add_shape(owner_id, shape)


func local_rect() -> Rect2:
	return _rect


static func _bake_map(data: Dictionary) -> Array:
	var result: Array = []
	var sets: Dictionary = HeronPaperAssets.load_catalog().get("tilesets", {})
	var cell_size: Vector2 = _vector(data.get("tile_size", [32, 32]))
	var layers: Array = data.get("layers", [])
	for index: int in range(layers.size()):
		var layer: Dictionary = layers[index]
		var batches: Array = []
		var collisions: Array = []
		var collides: bool = bool(layer.get("collides", true)) and String(data.get("collision_domain", "Use3DPhysics")) != "None"
		for cell: Array in layer.get("cells", []):
			var set_ref: String = String(cell[2])
			var tileset: Dictionary = sets.get(set_ref, {})
			if tileset.is_empty():
				continue
			var tile: int = int(cell[3])
			var flags: int = int(cell[4]) & 7
			var size: Vector2 = _vector(tileset.get("tile_size", [32, 32]))
			var center := Vector2(float(cell[0]) * cell_size.x, float(cell[1]) * cell_size.y)
			var columns: int = maxi(int(tileset.get("columns", 1)), 1)
			var margin: Array = tileset.get("margin", [0, 0, 0, 0])
			var spacing: Vector2 = _vector(tileset.get("spacing", [0, 0]))
			var uv := Vector2(float(margin[0]), float(margin[1]))
			uv += Vector2(tile % columns, floori(float(tile) / columns)) * (size + spacing)
			var origin: Vector2 = center - cell_size * 0.5
			origin += _vector(tileset.get("drawing_offset", [0, 0]))
			origin.y += cell_size.y - size.y
			_append_quad(batches, String(tileset.get("texture", "")), origin, size, uv, flags)
			if collides:
				var shapes: Array = _tile_shapes(set_ref, tileset, tile, flags)
				if not shapes.is_empty():
					# UE collision aligns the unflipped tile's bottom-left to its cell.
					var offset := Vector2((size.x - cell_size.x) * 0.5, (cell_size.y - size.y) * 0.5)
					collisions.append({"position": center + offset, "shapes": shapes})
		var finished_batches: Array = []
		for batch: Dictionary in batches:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array(batch["vertices"])
			arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(batch["uvs"])
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			finished_batches.append({"texture": batch["texture"], "mesh": mesh})
		var tint: Array = layer.get("color", [1, 1, 1, 1])
		result.append({
			"name": layer.get("name", "Layer"),
			"z": clampi(-roundi(index * float(data.get("separation_per_layer", 4))), -4096, 4096),
			"color": Color(float(tint[0]), float(tint[1]), float(tint[2]), float(tint[3])),
			"hidden": layer.get("hidden_in_game", false),
			"batches": finished_batches, "collisions": collisions,
		})
	return result


static func _append_quad(batches: Array, path: String, origin: Vector2, size: Vector2, uv: Vector2, flags: int) -> void:
	var texture: Texture2D = HeronPaperAssets.texture(path)
	if texture == null:
		return
	# Keep consecutive atlas runs separate so overlapping tiles retain source order.
	if batches.is_empty() or String(batches.back()["texture"]) != path:
		batches.append({"texture": path, "vertices": [], "uvs": []})
	var batch: Dictionary = batches.back()
	var drawn_size: Vector2 = Vector2(size.y, size.x) if (flags & 1) != 0 else size
	var positions: Array[Vector2] = [
		origin + Vector2(0, drawn_size.y), origin + drawn_size,
		origin + Vector2(drawn_size.x, 0), origin,
	]
	var texture_size: Vector2 = texture.get_size()
	var source_uvs: Array[Vector2] = [
		(uv + Vector2(0, size.y)) / texture_size, (uv + size) / texture_size,
		(uv + Vector2(size.x, 0)) / texture_size, uv / texture_size,
	]
	var permutation: Array = UV_PERMUTATIONS[flags]
	for corner: int in TRIANGLE_CORNERS:
		batch["vertices"].append(positions[corner])
		batch["uvs"].append(source_uvs[int(permutation[corner])])


static func _tile_shapes(ref: String, data: Dictionary, tile: int, flags: int) -> Array:
	var key: String = "%s:%d:%d" % [ref, tile, flags]
	if _shape_cache.has(key):
		return _shape_cache[key]
	var result: Array = []
	var tile_data: Dictionary = data.get("tiles", {}).get(str(tile), {})
	for geometry: Dictionary in tile_data.get("collision", []):
		if bool(geometry.get("negative", false)):
			push_error("Unsupported subtractive tile collision: " + key)
			continue
		var polygon := PackedVector2Array()
		var size: Vector2 = _vector(geometry.get("size", [0, 0]))
		var center: Vector2 = _vector(geometry.get("position", [0, 0]))
		var rotation: float = deg_to_rad(float(geometry.get("rotation", 0)))
		var kind: String = String(geometry.get("type", "Polygon"))
		if kind == "Box":
			polygon = PackedVector2Array([
				Vector2(-size.x, -size.y) * 0.5, Vector2(size.x, -size.y) * 0.5,
				size * 0.5, Vector2(-size.x, size.y) * 0.5,
			])
		elif kind == "Circle":
			for point_index: int in range(32):
				var angle: float = TAU * point_index / 32.0
				polygon.append(Vector2(cos(angle), sin(angle)) * size * 0.5)
		else:
			for vertex: Array in geometry.get("vertices", []):
				polygon.append(_vector(vertex))
		if polygon.size() < 3:
			continue
		for point_index: int in range(polygon.size()):
			polygon[point_index] = _flip_point(polygon[point_index].rotated(rotation) + center, flags)
		if Geometry2D.is_polygon_clockwise(polygon):
			polygon.reverse()
		for convex: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(polygon):
			var shape := ConvexPolygonShape2D.new()
			shape.points = convex
			result.append(shape)
	_shape_cache[key] = result
	return result


static func _flip_point(point: Vector2, flags: int) -> Vector2:
	# Same diagonal-first transform as UPaperTileLayer::GetTileTransform.
	if (flags & 1) != 0:
		point = Vector2(point.y, point.x)
	if (flags & 4) != 0:
		point.x = -point.x
	if (flags & 2) != 0:
		point.y = -point.y
	return point


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
