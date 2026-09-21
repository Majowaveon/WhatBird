class_name HeronPaperAssets
extends RefCounted

const CATALOG_PATH: String = "res://data/paper2d.json"
const FRAME_REFS: StringName = &"heron_frame_refs"
const GEOMETRY_PPU: StringName = &"heron_geometry_ppu"

static var _catalog: Dictionary = {}
static var _atlases: Dictionary = {}
static var _textures: Dictionary = {}
static var _frames: Dictionary = {}
static var _player_frames: SpriteFrames


static func load_catalog() -> Dictionary:
	if _catalog.is_empty():
		if not FileAccess.file_exists(CATALOG_PATH):
			push_error("Missing Paper2D catalog: " + CATALOG_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if not parsed is Dictionary:
			push_error("Invalid Paper2D catalog: " + CATALOG_PATH)
			return {}
		_catalog = parsed
	return _catalog


static func resolve_ref(ref: String) -> String:
	var key: String = ref.strip_edges()
	if key.contains("'"):
		key = key.get_slice("'", 1)
	if key.begins_with("/Game/") and not key.contains("."):
		key += "." + key.get_file()
	var aliases: Dictionary = load_catalog().get("aliases", {})
	var visited: Dictionary = {}
	while aliases.has(key):
		if visited.has(key):
			push_error("Paper2D reference cycle: " + key)
			return ""
		visited[key] = true
		key = String(aliases[key])
	return key


static func sprite(ref: String) -> Dictionary:
	return load_catalog().get("sprites", {}).get(resolve_ref(ref), {})


static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		var loaded: Texture2D = load(path) as Texture2D
		if loaded == null:
			push_error("Missing Paper2D texture: " + path)
			return null
		_textures[path] = loaded
	return _textures[path] as Texture2D


static func atlas(ref: String) -> AtlasTexture:
	var key: String = resolve_ref(ref)
	if _atlases.has(key):
		return _atlases[key] as AtlasTexture
	var data: Dictionary = sprite(key)
	if data.is_empty():
		if not key.is_empty():
			push_error("Unknown PaperSprite: " + key)
		return null
	var result := AtlasTexture.new()
	result.atlas = texture(String(data.get("texture", "")))
	result.region = Rect2(_vector(data.get("uv", [0, 0])), _vector(data.get("size", [0, 0])))
	result.filter_clip = true
	_atlases[key] = result
	return result


static func _add_animation(target: SpriteFrames, animation: StringName, ref: String) -> void:
	if not target.has_animation(animation):
		target.add_animation(animation)
	else:
		target.clear(animation)
	var key: String = resolve_ref(ref)
	var data: Dictionary = load_catalog().get("flipbooks", {}).get(key, {})
	var entries: Array = data.get("frames", [])
	if data.is_empty() and not sprite(key).is_empty():
		entries = [{"sprite": key, "duration": 1}]
	elif data.is_empty():
		push_error("Unknown PaperFlipbook or PaperZD sequence: " + ref)
	target.set_animation_speed(animation, float(data.get("fps", 15.0)))
	target.set_animation_loop(animation, true)
	var refs: Array[String] = []
	for entry: Dictionary in entries:
		var sprite_ref: String = String(entry.get("sprite", ""))
		# FrameRun is a relative duration at the original flipbook's FPS.
		target.add_frame(animation, atlas(sprite_ref), float(entry.get("duration", 1)))
		refs.append(sprite_ref)
	var metadata: Dictionary = target.get_meta(FRAME_REFS, {})
	metadata[String(animation)] = refs
	target.set_meta(FRAME_REFS, metadata)


static func frames(ref: String) -> SpriteFrames:
	var key: String = resolve_ref(ref)
	if not _frames.has(key):
		var result := SpriteFrames.new()
		_add_animation(result, &"default", key)
		_frames[key] = result
	return _frames[key] as SpriteFrames


static func player_frames() -> SpriteFrames:
	if _player_frames == null:
		_player_frames = SpriteFrames.new()
		_player_frames.remove_animation(&"default")
		var animations: Dictionary = load_catalog().get("player_animations", {})
		for animation: String in animations:
			_add_animation(_player_frames, StringName(animation), String(animations[animation]))
	return _player_frames


static func make_flipbook(ref: String) -> AnimatedSprite2D:
	var result := AnimatedSprite2D.new()
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.sprite_frames = frames(ref)
	var update: Callable = apply_frame_geometry.bind(result)
	result.frame_changed.connect(update)
	result.animation_changed.connect(update)
	result.sprite_frames_changed.connect(update)
	apply_frame_geometry(result)
	result.play(&"default")
	return result


static func apply_frame_geometry(anim: AnimatedSprite2D, ref: String = "") -> void:
	if anim.sprite_frames == null:
		return
	var sprite_ref: String = ""
	var metadata: Dictionary = anim.sprite_frames.get_meta(FRAME_REFS, {})
	var refs: Array = metadata.get(String(anim.animation), [])
	if anim.frame >= 0 and anim.frame < refs.size():
		sprite_ref = String(refs[anim.frame])
	elif not ref.is_empty():
		var key: String = resolve_ref(ref)
		if not sprite(key).is_empty():
			sprite_ref = key
		else:
			var entries: Array = load_catalog().get("flipbooks", {}).get(key, {}).get("frames", [])
			if anim.frame >= 0 and anim.frame < entries.size():
				sprite_ref = String(entries[anim.frame].get("sprite", ""))
	var data: Dictionary = sprite(sprite_ref)
	if data.is_empty():
		return
	anim.centered = true
	anim.offset = _vector(data.get("offset", [0, 0]))
	_apply_ppu(anim, float(data.get("ppu", 1.0)))


static func configure_sprite(node: Sprite2D, ref: String) -> void:
	var data: Dictionary = sprite(ref)
	if data.is_empty():
		return
	node.texture = atlas(ref)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.centered = true
	node.offset = _vector(data.get("offset", [0, 0]))
	_apply_ppu(node, float(data.get("ppu", 1.0)))


static func _apply_ppu(node: Node2D, ppu: float) -> void:
	ppu = maxf(ppu, 0.000001)
	var previous: float = float(node.get_meta(GEOMETRY_PPU, 1.0))
	# Preserve external scaling, including mirroring, across frame changes.
	node.scale *= previous / ppu
	node.set_meta(GEOMETRY_PPU, ppu)


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
