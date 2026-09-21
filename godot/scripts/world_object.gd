@tool
class_name HeronWorldObject
extends Node2D

signal entered(object: HeronWorldObject, body: Node2D)
signal exited(object: HeronWorldObject, body: Node2D)

@export_group("Identity")
@export var object_id: String = ""
@export var display_name: String = ""
@export_enum("BP_Button", "BP_Door", "BP_DestructibleWood", "BP_CheckPoint", "BP_Spring", "BP_Spring针叶", "BP_Spring冰雪", "BP_WaterTriggerVolume", "BP_IceTriggerVolume", "BP_ChangeSubLevelVolume", "BP_UpVolume", "BP_PassGameTriggerVolume", "BP_ItemUnlockBird", "BP_ItemAddHenshinTimes", "BP_空气墙", "Decoration") var kind: String = ""
@export_group("Mechanism")
@export var linked_buttons: Array[NodePath] = []
@export var linked_doors: Array[NodePath] = []
@export var target_room: String = ""
@export_enum("Heron", "Mallard", "Penguin", "Woodpecker") var unlock_form: int = 0
@export var pickup_amount: int = 1
@export var launch_speed: float = 390.0
@export var break_delay: float = 1.0
@export_group("Appearance")
@export var spring_animation: SpriteFrames
@export var pressed_animation: SpriteFrames
@export var randomize_wood: bool = false
@export var wood_variants: Array[SpriteFrames] = []

var record: Dictionary = {}
var properties: Dictionary = {}
var active: bool = true
var triggered: bool = false
var render: AnimatedSprite2D
var component_nodes: Dictionary = {}
var collision_shapes: Array[CollisionShape2D] = []
var solid_shapes: Array[CollisionShape2D] = []
var base_flipbook: String = ""
var door_buttons: Array[String] = []
var cooldown: float = 0.0
var reset_generation: int = 0
var initial_frames: SpriteFrames

func initialize_editor_fields() -> void:
	object_id = String(record.get("id", String(name)))
	display_name = String(record.get("label", String(name)))
	target_room = String(properties.get("改为的关卡名", ""))
	pickup_amount = int(properties.get("添加次数", 1))
	break_delay = float(properties.get("DelayDestroy", 1.0))
	var form: String = String(properties.get("BirdType", "EBirdType::Default")).get_slice("::", 1).to_lower()
	unlock_form = int({"default": 0, "mallard": 1, "penguin": 2, "woodpecker": 3}.get(form, 0))
	launch_speed = 700.0 if kind == "BP_UpVolume" else 390.0
	if kind.begins_with("BP_Spring") and properties.has("AnimS"):
		spring_animation = HeronPaperAssets.frames(String(properties["AnimS"]))
	if kind == "BP_Button" and not base_flipbook.is_empty():
		pressed_animation = HeronPaperAssets.frames(base_flipbook.replace("FB_按钮_1", "FB_按钮_2"))
	if kind == "BP_DestructibleWood":
		randomize_wood = true
		for ref: String in properties.get("FlipbookList", []):
			wood_variants.append(HeronPaperAssets.frames(ref))
	if render:
		initial_frames = render.sprite_frames

func bind_loaded() -> void:
	if object_id.is_empty():
		object_id = String(get_path())
	record = {"id": object_id, "label": display_name if not display_name.is_empty() else String(name)}
	properties = {"改为的关卡名": target_room, "添加次数": pickup_amount, "DelayDestroy": break_delay, "BirdType": unlock_form}
	door_buttons.clear()
	for path: NodePath in linked_buttons:
		var button: HeronWorldObject = get_node_or_null(path) as HeronWorldObject
		if button:
			door_buttons.append(button.object_id)
		else:
			push_warning("Missing linked button on " + String(name) + ": " + String(path))
	component_nodes.clear()
	collision_shapes.clear()
	solid_shapes.clear()
	_bind_children(self)
	if render:
		if randomize_wood and not wood_variants.is_empty():
			render.sprite_frames = wood_variants.pick_random()
		initial_frames = render.sprite_frames
		var geometry_callback: Callable = HeronPaperAssets.apply_frame_geometry.bind(render)
		for signal_name: String in ["frame_changed", "animation_changed", "sprite_frames_changed"]:
			if not render.is_connected(signal_name, geometry_callback):
				render.connect(signal_name, geometry_callback)
		HeronPaperAssets.apply_frame_geometry(render)
		render.play("default")

func _bind_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is AnimatedSprite2D and render == null:
			render = child
		if child is CollisionShape2D:
			collision_shapes.append(child)
			if child.get_parent() is StaticBody2D:
				solid_shapes.append(child)
		if child is Area2D:
			child.body_entered.connect(func(body: Node2D) -> void: entered.emit(self, body))
			child.body_exited.connect(func(body: Node2D) -> void: exited.emit(self, body))
		if child is StaticBody2D:
			child.set_meta("world_object", self)
		if child is Node2D:
			component_nodes[String(child.name)] = child
		_bind_children(child)

func setup(data: Dictionary) -> void:
	record = data
	properties = data.get("properties", {})
	kind = String(data.get("class", "")).get_slice(".", 1).trim_suffix("_C")
	name = String(data.get("id", "Object")).validate_node_name()
	position = vector(data.get("position", [0, 0]))
	scale = vector(data.get("scale", [1, 1]))
	rotation = deg_to_rad(float(data.get("rotation", 0)))
	z_index = clampi(roundi(float(data.get("depth", 0))) + 5, -1000, 1000)
	var root_name: String = data.get("root", "")
	component_nodes[root_name] = self
	var components: Dictionary = data.get("components", {})
	for key: String in components:
		if key == root_name:
			continue
		var node := Node2D.new()
		node.name = key.validate_node_name()
		component_nodes[key] = node
	for key: String in components:
		var p: Dictionary = components[key].get("properties", {})
		var node: Node2D = component_nodes[key]
		if node != self:
			var parent_name: String = String(p.get("AttachParent", root_name)).get_slice(".", String(p.get("AttachParent", root_name)).count("."))
			var parent: Node2D = component_nodes.get(parent_name, self)
			if parent == node:
				parent = self
			parent.add_child(node)
			var loc: Dictionary = p.get("RelativeLocation", {})
			node.position = Vector2(number(loc.get("X", 0)), -number(loc.get("Z", 0)))
			var size: Dictionary = p.get("RelativeScale3D", {})
			node.scale = Vector2(number(size.get("X", 1)), number(size.get("Z", 1)))
			node.rotation = -deg_to_rad(number(p.get("RelativeRotation", {}).get("Pitch", 0)))
		var cls: String = components[key].get("class", "")
		if cls.ends_with("PaperFlipbookComponent"):
			var ref: String = p.get("SourceFlipbook", "")
			if kind == "BP_DestructibleWood" and not properties.get("FlipbookList", []).is_empty():
				ref = properties["FlipbookList"].pick_random()
			if ref.is_empty() and kind.begins_with("BP_Spring"):
				var animation: Dictionary = components.get("PaperZDAnimationComponent", {}).get("properties", {})
				ref = String(animation.get("AnimInstanceClass", ""))
			if not ref.is_empty():
				base_flipbook = ref
				render = HeronPaperAssets.make_flipbook(ref)
				node.add_child(render)
		elif cls.ends_with("BoxComponent"):
			_build_box(node, key, p)
	for ref: String in properties.get("BPButtonRef", []):
		door_buttons.append(ref.get_slice(".", ref.count(".")))
	initialize_editor_fields()

func _build_box(parent: Node2D, key: String, p: Dictionary) -> void:
	var ext: Dictionary = p.get("BoxExtent", {"X": 10, "Z": 10})
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(0.01, number(ext.get("X", 10)) * 2.0), maxf(0.01, number(ext.get("Z", 10)) * 2.0))
	var collision := CollisionShape2D.new()
	collision.shape = shape
	var is_solid: bool = key == "Box" and kind in ["BP_Door", "BP_DestructibleWood", "BP_空气墙"]
	if is_solid:
		var body := StaticBody2D.new()
		body.collision_layer = 4
		body.collision_mask = 2
		parent.add_child(body)
		body.add_child(collision)
		body.set_meta("world_object", self)
		solid_shapes.append(collision)
	else:
		var area := Area2D.new()
		area.collision_layer = 8
		area.collision_mask = 2
		parent.add_child(area)
		area.add_child(collision)
		area.body_entered.connect(func(body: Node2D) -> void: entered.emit(self, body))
		area.body_exited.connect(func(body: Node2D) -> void: exited.emit(self, body))
	collision_shapes.append(collision)

func set_active(enabled: bool) -> void:
	active = enabled
	if render:
		render.visible = enabled
	for child: Node in get_children():
		if child is Label:
			child.visible = enabled
	for shape: CollisionShape2D in collision_shapes:
		shape.set_deferred("disabled", not enabled)

func activate_button() -> void:
	triggered = true
	if render:
		var next_ref: String = base_flipbook.replace("FB_按钮_1", "FB_按钮_2")
		var frames: SpriteFrames = pressed_animation if pressed_animation else HeronPaperAssets.frames(next_ref)
		if frames.get_frame_count("default") > 0:
			render.sprite_frames = frames
			render.play("default")

func open_door() -> void:
	triggered = true
	set_active(false)

func break_wood() -> void:
	triggered = true
	active = false
	if render:
		render.visible = false
	var generation: int = reset_generation
	get_tree().create_timer(float(properties.get("DelayDestroy", 1.0))).timeout.connect(func() -> void:
		if is_inside_tree() and reset_generation == generation:
			for shape: CollisionShape2D in solid_shapes:
				shape.set_deferred("disabled", true)
	)

func reset_object() -> void:
	reset_generation += 1
	triggered = false
	set_active(true)
	if render and (initial_frames or not base_flipbook.is_empty()):
		render.sprite_frames = initial_frames if initial_frames else HeronPaperAssets.frames(base_flipbook)
		render.play("default")
		HeronPaperAssets.apply_frame_geometry(render)

func play_spring() -> void:
	if not render:
		return
	var ref: String = properties.get("AnimS", "")
	if ref.is_empty() and not spring_animation:
		return
	render.sprite_frames = spring_animation if spring_animation else HeronPaperAssets.frames(ref)
	render.play("default")
	HeronPaperAssets.apply_frame_geometry(render)
	var duration: float = 0.0
	var fps: float = render.sprite_frames.get_animation_speed("default")
	for frame: int in render.sprite_frames.get_frame_count("default"):
		duration += render.sprite_frames.get_frame_duration("default", frame) / maxf(fps, 0.01)
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(render) and is_inside_tree():
			render.sprite_frames = initial_frames if initial_frames else HeronPaperAssets.frames(base_flipbook)
			render.play("default")
	)

func world_box() -> Rect2:
	var result := Rect2(global_position, Vector2.ZERO)
	var found: bool = false
	for shape: CollisionShape2D in collision_shapes:
		var rectangle: RectangleShape2D = shape.shape as RectangleShape2D
		if not rectangle:
			continue
		var local := Rect2(-rectangle.size / 2.0, rectangle.size)
		var rect: Rect2 = shape.global_transform * local
		result = result.merge(rect) if found else rect
		found = true
	return result

static func number(value: Variant) -> float:
	return float(value)

static func vector(value: Array) -> Vector2:
	return Vector2(number(value[0]), number(value[1]))
