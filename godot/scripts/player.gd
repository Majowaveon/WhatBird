class_name HeronPlayer
extends CharacterBody2D
## Scene-independent port of HeronPlayer, HeronPlayerController and the bird abilities.
## Positions are capsule centers; all distances/speeds supplied to setup are Godot units.
## The world owns areas, damage targets, sounds, checkpoints and restart input.

signal died
signal attack_requested(origin: Vector2, facing: int)
signal form_changed(form: int)
signal transform_count_changed(remaining: int, maximum: int)
signal landed(in_water: bool)
signal sound_requested(kind: String)


enum Bird { HERON, MALLARD, PENGUIN, WOODPECKER }

const FORM_NAMES: Array[StringName] = [&"heron", &"mallard", &"penguin", &"woodpecker"]
# The slide frames' visible body ends 10 pixels above the standing frames' feet.
const PENGUIN_SLIDE_FOOT_OFFSET: float = 10.0

# Runtime state is independent of any particular level, UI or game singleton.
var bird: int = Bird.HERON
var unlocked_birds: Array[int] = [Bird.HERON]
var remaining_transforms: int = -1
var max_transforms: int = -1
var facing: int = 1
var frozen: bool = false
var water_count: int = 0
var ice_count: int = 0

# BP_Player's gameplay variables override the inherited movement-component defaults.
@export var speed: float = 200.0
@export var jump_speed: float = 200.0
@export var jump_hold_time: float = 0.32
@export_range(0.0, 1.0) var jump_hold_gravity_scale: float = 0.5
@export_range(0.0, 1.0) var jump_release_multiplier: float = 0.5
@export var gravity: float = 980.0
@export var gravity_scale: float = 1.0
@export var max_acceleration: float = 2048.0
@export var ground_friction: float = 8.0
@export var braking_friction_factor: float = 2.0
@export var braking_deceleration_walking: float = 2048.0
@export var braking_deceleration_falling: float = 0.0
@export var falling_lateral_friction: float = 0.0
@export var air_control: float = 0.8
@export var air_control_boost_multiplier: float = 2.0
@export var air_control_boost_velocity_threshold: float = 25.0

# BP_HeronGlide overrides C++ glide speed/gravity; the other ability defaults
# come directly from the C++ headers.
@export var glide_speed: float = 200.0
@export var glide_fall_speed: float = 100.0
@export var glide_gravity_scale: float = 0.4
@export var water_speed_multiplier: float = 0.8
@export var water_gravity_scale: float = 0.3
@export var water_ground_friction: float = 2.0
@export var ice_speed_multiplier: float = 1.5
@export var ice_ground_friction: float = 0.5
@export var ice_acceleration: float = 450.0
@export var ice_braking_deceleration: float = 60.0

# Effective dimensions after the original capsule's component scale.
# Collision height includes both semicircles, rather than UE's half-height.
@export var collision_radius: float = 8.5
@export var collision_height: float = 26.4
@export var sprite_scale: Vector2 = Vector2.ONE
@export var sprite_offset: Vector2 = Vector2(0.0, 14.4)
## False anchors each frame's bottom center at sprite_offset (Paper2D foot pivot).
## True anchors its center there. The offset is already converted to Godot Y-down.
@export var sprite_centered: bool = false
@export var auto_flip_sprite: bool = true

var sprite: AnimatedSprite2D
var collision: CollisionShape2D

var gliding: bool:
	get:
		return _gliding

var in_water: bool:
	get:
		return water_count > 0

var on_ice: bool:
	get:
		return ice_count > 0

var ice_sliding: bool:
	get:
		return bird == Bird.PENGUIN and not _dead and not frozen \
			and (_ice_slide_airborne or (_grounded and on_ice and absf(velocity.x) > 1.0))

var on_ground: bool:
	get:
		return _grounded

var dead: bool:
	get:
		return _dead

# Derive modifiers from base settings every time. Unlike Enter/Exit mutation, this
# cannot retain another form's water/ice/gravity settings after overlapping areas.
var current_speed: float:
	get:
		if bird == Bird.MALLARD and in_water:
			return speed * water_speed_multiplier
		if bird == Bird.PENGUIN and (on_ice or _ice_slide_airborne):
			return speed * ice_speed_multiplier
		return speed

var current_gravity: float:
	get:
		if bird == Bird.HERON and _gliding:
			return gravity * glide_gravity_scale
		if bird == Bird.MALLARD and in_water:
			return gravity * water_gravity_scale
		return gravity * gravity_scale

var current_ground_friction: float:
	get:
		if bird == Bird.MALLARD and in_water:
			return water_ground_friction
		if bird == Bird.PENGUIN and on_ice:
			return ice_ground_friction
		return ground_friction

var _dead: bool = false
var _grounded: bool = false
var _gliding: bool = false
var _ice_slide_airborne: bool = false
var _ice_slide_air_velocity: float = 0.0
var _jump_hold_remaining: float = 0.0
var _variable_jump_active: bool = false
var _attack_animation_remaining: float = 0.0
var _animation_dirty: bool = true
var _animation_paused: bool = false
var _paper_geometry: Script
var _configured_sprite_scale: Vector2 = Vector2.ONE
var _notify_animation: StringName = &""
var _notify_time: float = -0.001
const SOUND_NOTIFIES: Dictionary = {
	"heron_walk": [0.5, 1.1666666269],
	"mallard_walk": [0.0666666701, 0.2666666806],
	"mallard_swim_walk": [0.0, 0.200000003],
	"penguin_walk": [0.1333333403, 0.400000006],
	"woodpecker_walk": [0.0666666701, 0.3333333433],
}

func _process(_delta: float) -> void:
	if not is_instance_valid(sprite) or frozen or _dead or not sprite.is_playing():
		return
	var animation: StringName = sprite.animation
	if not SOUND_NOTIFIES.has(String(animation)) or not _has_animation(animation):
		_notify_animation = animation
		_notify_time = -0.001
		return
	var frames: SpriteFrames = sprite.sprite_frames
	var fps: float = frames.get_animation_speed(animation)
	var time: float = 0.0
	for index: int in sprite.frame:
		time += frames.get_frame_duration(animation, index) / fps
	time += sprite.frame_progress * frames.get_frame_duration(animation, sprite.frame) / fps
	if _notify_animation != animation or time < _notify_time:
		_notify_time = -0.001
	for event_time: float in SOUND_NOTIFIES[String(animation)]:
		if event_time > _notify_time and event_time <= time:
			sound_requested.emit("swim" if animation == &"mallard_swim_walk" else "step")
	_notify_animation = animation
	_notify_time = time


func _ready() -> void:
	collision_layer = 2
	collision_mask = 5
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	floor_snap_length = 1.0
	_ensure_default_unlocked()
	_ensure_nodes()
	_configure_collision()
	_configure_sprite()
	_update_animation()


## Accepts flat snake_case keys matching the exported settings above.
## Vector settings accept Vector2, [x, y], or {"x": x, "y": y}; sprite_scale
## additionally accepts a uniform number. No UE-unit conversion is performed here.
## Safe to call after add_child, repeatedly, or with null/empty SpriteFrames.
func setup(settings: Dictionary, frames: SpriteFrames) -> void:
	speed = _setting_float(settings, "speed", speed)
	jump_speed = _setting_float(settings, "jump_speed", jump_speed)
	jump_hold_time = _setting_float(settings, "jump_hold_time", jump_hold_time)
	jump_hold_gravity_scale = clampf(_setting_float(settings, "jump_hold_gravity_scale", jump_hold_gravity_scale), 0.0, 1.0)
	jump_release_multiplier = clampf(_setting_float(settings, "jump_release_multiplier", jump_release_multiplier), 0.0, 1.0)
	gravity = _setting_float(settings, "gravity", gravity)
	gravity_scale = _setting_float(settings, "gravity_scale", gravity_scale)
	max_acceleration = _setting_float(settings, "max_acceleration", max_acceleration)
	ground_friction = _setting_float(settings, "ground_friction", ground_friction)
	braking_friction_factor = _setting_float(settings, "braking_friction_factor", braking_friction_factor)
	braking_deceleration_walking = _setting_float(settings, "braking_deceleration_walking", braking_deceleration_walking)
	braking_deceleration_falling = _setting_float(settings, "braking_deceleration_falling", braking_deceleration_falling)
	falling_lateral_friction = _setting_float(settings, "falling_lateral_friction", falling_lateral_friction)
	air_control = clampf(_setting_float(settings, "air_control", air_control), 0.0, 1.0)
	air_control_boost_multiplier = _setting_float(settings, "air_control_boost_multiplier", air_control_boost_multiplier)
	air_control_boost_velocity_threshold = _setting_float(settings, "air_control_boost_velocity_threshold", air_control_boost_velocity_threshold)
	glide_speed = _setting_float(settings, "glide_speed", glide_speed)
	glide_fall_speed = _setting_float(settings, "max_glide_fall_speed", glide_fall_speed)
	glide_fall_speed = _setting_float(settings, "glide_fall_speed", glide_fall_speed)
	glide_gravity_scale = _setting_float(settings, "glide_gravity_scale", glide_gravity_scale)
	water_speed_multiplier = _setting_float(settings, "water_speed_multiplier", water_speed_multiplier)
	water_gravity_scale = _setting_float(settings, "water_gravity_scale", water_gravity_scale)
	water_ground_friction = _setting_float(settings, "water_ground_friction", water_ground_friction)
	ice_speed_multiplier = _setting_float(settings, "ice_speed_multiplier", ice_speed_multiplier)
	ice_ground_friction = _setting_float(settings, "ice_ground_friction", ice_ground_friction)
	ice_acceleration = _setting_float(settings, "ice_acceleration", ice_acceleration)
	ice_braking_deceleration = _setting_float(settings, "ice_braking_deceleration", ice_braking_deceleration)
	collision_radius = maxf(0.01, _setting_float(settings, "collision_radius", collision_radius))
	collision_height = maxf(collision_radius * 2.0, _setting_float(settings, "collision_height", collision_height))
	sprite_scale = _setting_vector(settings.get("sprite_scale", sprite_scale), sprite_scale, true)
	sprite_scale = Vector2(maxf(absf(sprite_scale.x), 0.001), maxf(absf(sprite_scale.y), 0.001))
	sprite_offset = _setting_vector(settings.get("sprite_offset", sprite_offset), sprite_offset)
	sprite_centered = _setting_bool(settings, "sprite_centered", sprite_centered)
	auto_flip_sprite = _setting_bool(settings, "auto_flip_sprite", auto_flip_sprite)
	_ensure_default_unlocked()
	_ensure_nodes()
	if _paper_geometry == null and ResourceLoader.exists("res://scripts/paper_assets.gd"):
		_paper_geometry = load("res://scripts/paper_assets.gd") as Script
	_configure_collision()
	if frames != null:
		sprite.sprite_frames = frames
	_configure_sprite()
	_attack_animation_remaining = 0.0
	_animation_dirty = true
	_update_animation()


## Reset keeps permanent unlocks. The world sets the new room's limit separately.
## point is the capsule's global center, not the standing foot position.
func reset_at(point: Vector2, form: int = Bird.HERON) -> void:
	_cancel_variable_jump()
	_set_gliding(false)
	_ice_slide_airborne = false
	_ice_slide_air_velocity = 0.0
	_dead = false
	frozen = false
	bird = form if _valid_form(form) else Bird.HERON
	facing = 1
	water_count = 0
	ice_count = 0
	max_transforms = maxi(max_transforms, -1)
	remaining_transforms = max_transforms
	velocity = Vector2.ZERO
	# CharacterBody2D's contact flags belong to its last move_and_slide. Keep our
	# own grounded state so neither a teleport nor bounce can reuse that floor.
	_grounded = false
	_attack_animation_remaining = 0.0
	_animation_dirty = true
	_animation_paused = false
	global_position = point
	if is_inside_tree():
		reset_physics_interpolation()
	_ensure_default_unlocked()
	_ensure_nodes()
	_update_animation()
	form_changed.emit(bird)
	transform_count_changed.emit(remaining_transforms, max_transforms)


func set_transform_limit(count: int) -> void:
	max_transforms = maxi(count, -1)
	remaining_transforms = max_transforms
	transform_count_changed.emit(remaining_transforms, max_transforms)


func add_transform_count(count: int) -> void:
	if remaining_transforms < 0 or count == 0:
		return
	# Pickups may exceed the room's initial limit, as in AddHenshinCount. Clamp
	# spending at zero so an underflow cannot accidentally grant infinite uses.
	remaining_transforms = maxi(0, remaining_transforms + count)
	transform_count_changed.emit(remaining_transforms, max_transforms)


func unlock_bird(form: int) -> void:
	_ensure_default_unlocked()
	if _valid_form(form) and not unlocked_birds.has(form):
		unlocked_birds.append(form)


func is_bird_unlocked(form: int) -> bool:
	return _valid_form(form) and (form == Bird.HERON or unlocked_birds.has(form))


func can_transform() -> bool:
	return not frozen and not _dead and remaining_transforms != 0


func try_transform(form: int) -> bool:
	if not can_transform() or form == bird or not is_bird_unlocked(form):
		return false
	_cancel_variable_jump()
	_set_gliding(false)
	_ice_slide_airborne = false
	_ice_slide_air_velocity = 0.0
	bird = form
	_attack_animation_remaining = 0.0
	_animation_dirty = true
	if remaining_transforms > 0:
		remaining_transforms -= 1
	_update_animation()
	form_changed.emit(bird)
	transform_count_changed.emit(remaining_transforms, max_transforms)
	sound_requested.emit("transform_%s" % String(FORM_NAMES[bird]))
	# Switching out of mallard while submerged is immediately lethal, even
	# though no new area-enter event occurs. Ice/water modifiers are derived.
	if in_water and bird != Bird.MALLARD:
		die()
	return true


## World-driven form changes bypass unlocks and charges (checkpoint restoration).
## Invalid ids are ignored; water remains lethal unless the new form is mallard.
func force_transform(form: int) -> void:
	if not _valid_form(form):
		return
	_cancel_variable_jump()
	_set_gliding(false)
	_ice_slide_airborne = false
	_ice_slide_air_velocity = 0.0
	bird = form
	_attack_animation_remaining = 0.0
	_animation_dirty = true
	_update_animation()
	form_changed.emit(bird)
	if in_water and bird != Bird.MALLARD:
		die()


## Counts, rather than booleans, preserve state across adjacent/overlapping areas.
func set_environment(water: int, ice: int) -> void:
	water_count = maxi(water, 0)
	ice_count = maxi(ice, 0)
	if in_water and bird != Bird.MALLARD:
		die()
	else:
		_update_animation()


## Upward launch speed supplied by the world (normal/super/transition bounce).
func bounce(launch_speed: float) -> void:
	if frozen or _dead or not is_finite(launch_speed) or launch_speed <= 0.0:
		return
	_cancel_variable_jump()
	_set_gliding(false)
	_ice_slide_airborne = ice_sliding
	_ice_slide_air_velocity = velocity.x
	velocity.y = -launch_speed
	_grounded = false
	_update_animation()


## Freeze immediately and emit once; checkpoint/world logic decides what follows.
func die() -> void:
	if _dead:
		return
	_cancel_variable_jump()
	_ice_slide_airborne = false
	_ice_slide_air_velocity = 0.0
	_dead = true
	frozen = true
	velocity = Vector2.ZERO
	_grounded = false
	_attack_animation_remaining = 0.0
	_set_gliding(false)
	if is_instance_valid(sprite):
		sprite.pause()
	died.emit()


## Call from the world's attack_requested handler only after an actual break.
## The original ability plays drum animation/sound on a hit, with no cooldown.
## The world traces center, one tile below, then one tile above, stopping at its
## first breakable hit. Defaults in WoodpeckerAbility.h: tile 16, reach 20, radius 8.
func confirm_attack(hit: bool = true) -> void:
	if not hit or frozen or _dead or bird != Bird.WOODPECKER:
		return
	_ensure_nodes()
	_attack_animation_remaining = _animation_duration(&"woodpecker_drum")
	_animation_dirty = true
	_update_animation()
	sound_requested.emit("drum")


func _physics_process(delta: float) -> void:
	if _dead or frozen:
		_cancel_variable_jump()
		_ice_slide_airborne = false
		_ice_slide_air_velocity = 0.0
		velocity = Vector2.ZERO
		_set_gliding(false)
		if is_instance_valid(sprite) and sprite.is_playing():
			_animation_paused = true
			sprite.pause()
		return
	if in_water and bird != Bird.MALLARD:
		die()
		return

	_attack_animation_remaining = maxf(0.0, _attack_animation_remaining - delta)
	_poll_transform_input()
	if _dead or frozen:
		return

	var jump_ability_requested: bool = false
	if _just_pressed(&"jump"):
		if _grounded:
			# A penguin that is already moving on ice carries that slide into the jump.
			_ice_slide_airborne = ice_sliding
			_ice_slide_air_velocity = velocity.x if _ice_slide_airborne else 0.0
			velocity.y = -jump_speed
			_grounded = false
			_jump_hold_remaining = jump_hold_time
			_variable_jump_active = true
		else:
			jump_ability_requested = true
	if _just_released(&"jump"):
		if _variable_jump_active and velocity.y < 0.0:
			velocity.y *= jump_release_multiplier
		_cancel_variable_jump()
		_set_gliding(false)

	var axis: float = _input_strength(&"move_right") - _input_strength(&"move_left")
	_move_horizontal(axis, delta)
	_update_facing()
	if jump_ability_requested:
		_special_action_pressed()
	# Action deliberately cannot start heron glide. Mallard/penguin have no
	# special action in C++; midair jump dispatches the current ability, too.
	if _just_pressed(&"action") and bird != Bird.HERON:
		_special_action_pressed()
	if _dead or frozen:
		return

	var held_time: float = 0.0
	if _variable_jump_active and velocity.y < 0.0 and _input_strength(&"jump") > 0.0:
		held_time = minf(_jump_hold_remaining, delta)
		_jump_hold_remaining -= held_time
	velocity.y += current_gravity * (delta - held_time * (1.0 - jump_hold_gravity_scale))
	if velocity.y >= 0.0:
		_cancel_variable_jump()
	if _gliding:
		velocity.y = minf(velocity.y, glide_fall_speed)
		# Preserve rising momentum and existing horizontal direction. A vertical
		# glide does not manufacture forward speed until there is movement input.
		if not is_zero_approx(velocity.x):
			velocity.x = signf(velocity.x) * glide_speed

	var was_grounded: bool = _grounded
	var was_ice_sliding: bool = ice_sliding
	move_and_slide()
	_grounded = is_on_floor()
	if _grounded:
		_ice_slide_airborne = false
		_ice_slide_air_velocity = 0.0
	elif was_grounded and was_ice_sliding:
		_ice_slide_airborne = true
		_ice_slide_air_velocity = velocity.x
	elif _ice_slide_airborne and is_on_wall():
		_ice_slide_air_velocity = velocity.x
	if _grounded or is_on_ceiling():
		_cancel_variable_jump()
	if _gliding and (_grounded or is_on_wall()):
		_set_gliding(false)
	_update_facing()
	_update_animation()
	if _grounded and not was_grounded:
		landed.emit(in_water)
		sound_requested.emit("splash" if in_water else "land")


func _poll_transform_input() -> void:
	for form in range(FORM_NAMES.size()):
		if _just_pressed(FORM_NAMES[form]):
			try_transform(form)
			# One selection per physics frame also avoids consuming several
			# charges when multiple transform bindings are pressed together.
			return


func _special_action_pressed() -> void:
	if frozen or _dead:
		return
	match bird:
		Bird.HERON:
			if not _grounded:
				_set_gliding(true)
		Bird.WOODPECKER:
			attack_requested.emit(global_position, facing)


func _cancel_variable_jump() -> void:
	_jump_hold_remaining = 0.0
	_variable_jump_active = false


func _set_gliding(enabled: bool) -> void:
	if enabled:
		_cancel_variable_jump()
	if _gliding == enabled:
		return
	_gliding = enabled
	sound_requested.emit("glide" if enabled else "glide_stop")


func _move_horizontal(axis: float, delta: float) -> void:
	if bird == Bird.PENGUIN and _ice_slide_airborne:
		velocity.x = _ice_slide_air_velocity
		return
	if bird == Bird.PENGUIN and _grounded and on_ice:
		if is_zero_approx(axis):
			_brake_horizontal(ice_ground_friction, ice_braking_deceleration, delta)
		else:
			velocity.x = move_toward(velocity.x, axis * current_speed, ice_acceleration * absf(axis) * delta)
		return

	var friction: float = current_ground_friction if _grounded else falling_lateral_friction
	var braking: float = braking_deceleration_walking if _grounded else braking_deceleration_falling
	var limit: float = current_speed
	if is_zero_approx(axis):
		_brake_horizontal(friction * braking_friction_factor, braking, delta)
		return

	if absf(velocity.x) > limit:
		_brake_horizontal(friction * braking_friction_factor, braking, delta)
	# Approximate CharacterMovement's friction-assisted turning in one axis.
	velocity.x = lerpf(velocity.x, signf(axis) * absf(velocity.x), minf(friction * delta, 1.0))
	var control: float = 1.0
	if not _grounded:
		control = air_control
		if absf(velocity.x) < air_control_boost_velocity_threshold:
			control = minf(1.0, control * air_control_boost_multiplier)
	velocity.x = move_toward(velocity.x, axis * limit, max_acceleration * control * absf(axis) * delta)


func _brake_horizontal(friction: float, deceleration: float, delta: float) -> void:
	var magnitude: float = absf(velocity.x)
	if friction > 0.0:
		# Exact integration of dv/dt = -friction*v - deceleration avoids
		# frame-rate-dependent damping or reversing the velocity at low speeds.
		var offset: float = deceleration / friction
		magnitude = (magnitude + offset) * exp(-friction * delta) - offset
	else:
		magnitude -= deceleration * delta
	velocity.x = signf(velocity.x) * maxf(0.0, magnitude)


func _update_facing() -> void:
	# Match the source's velocity-based orientation, including ice momentum.
	if auto_flip_sprite and absf(velocity.x) > 1.0:
		facing = 1 if velocity.x > 0.0 else -1
	if is_instance_valid(sprite):
		sprite.flip_h = facing < 0


func _ensure_nodes() -> void:
	if not is_instance_valid(collision):
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)
	if not is_instance_valid(sprite):
		sprite = AnimatedSprite2D.new()
		sprite.name = "AnimatedSprite2D"
		var empty_frames: SpriteFrames = SpriteFrames.new()
		empty_frames.clear_all()
		sprite.sprite_frames = empty_frames
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		sprite.frame_changed.connect(_update_sprite_pivot)
		sprite.animation_changed.connect(_update_sprite_pivot)


func _configure_collision() -> void:
	collision_radius = maxf(collision_radius, 0.01)
	collision_height = maxf(collision_height, collision_radius * 2.0)
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = collision_radius
	capsule.height = collision_height
	collision.shape = capsule
	collision.position = Vector2.ZERO


func _configure_sprite() -> void:
	# Geometry preserves caller scale using its previous/current PPU ratio. Only
	# apply the change in configured scale, never multiply it once per frame.
	sprite.scale *= sprite_scale / _configured_sprite_scale
	_configured_sprite_scale = sprite_scale
	sprite.position = sprite_offset
	# Keep the drawing rect centered horizontally when flip_h changes. A frame
	# offset implements a bottom-center pivot without mirroring its X offset.
	sprite.centered = true
	sprite.flip_h = facing < 0
	_update_sprite_pivot()


func _update_sprite_pivot() -> void:
	if not is_instance_valid(sprite):
		return
	sprite.offset = Vector2.ZERO
	if not _has_animation(sprite.animation):
		return
	if _paper_geometry != null and _paper_geometry.has_method("apply_frame_geometry"):
		_paper_geometry.call("apply_frame_geometry", sprite)
		if sprite_centered:
			sprite.offset = Vector2.ZERO
	elif not sprite_centered:
		var frames: SpriteFrames = sprite.sprite_frames
		var frame_index: int = clampi(sprite.frame, 0, frames.get_frame_count(sprite.animation) - 1)
		var texture: Texture2D = frames.get_frame_texture(sprite.animation, frame_index)
		if texture != null:
			sprite.offset.y = -texture.get_height() * 0.5
	if sprite.animation == &"penguin_slide" and not sprite_centered:
		sprite.offset.y += PENGUIN_SLIDE_FOOT_OFFSET


func _update_animation() -> void:
	if not is_instance_valid(sprite) or _dead or frozen:
		return
	var state: String = "idle"
	if bird == Bird.WOODPECKER and _attack_animation_remaining > 0.0:
		state = "drum"
	elif bird == Bird.HERON and _gliding:
		state = "glide"
	elif ice_sliding:
		state = "slide"
	elif not _grounded:
		state = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 1.0:
		state = "walk"
	if bird == Bird.MALLARD and in_water:
		match state:
			"idle", "walk", "jump":
				state = "swim_" + state

	var animation_name: StringName = _resolve_animation(state)
	if animation_name == &"":
		sprite.visible = false
		sprite.stop()
		return
	sprite.visible = true
	sprite.flip_h = facing < 0
	if _animation_dirty or sprite.animation != animation_name:
		sprite.play(animation_name)
		if _animation_dirty:
			sprite.set_frame_and_progress(0, 0.0)
	elif _animation_paused:
		sprite.play(animation_name)
	_animation_dirty = false
	_animation_paused = false
	_update_sprite_pivot()


func _resolve_animation(state: String) -> StringName:
	var prefix: String = String(FORM_NAMES[clampi(bird, Bird.HERON, Bird.WOODPECKER)]) + "_"
	var ordinary_state: String = state.trim_prefix("swim_")
	if state == "glide":
		ordinary_state = "fall"
	elif state == "slide":
		ordinary_state = "walk"
	elif state == "drum":
		ordinary_state = "idle"
	var candidates: Array[StringName] = [
		StringName(prefix + state), StringName(prefix + ordinary_state),
		StringName(prefix + "idle"), StringName(prefix + "walk"),
		StringName(prefix + "fall"), StringName(prefix + "jump"), &"heron_idle",
	]
	for candidate: StringName in candidates:
		if _has_animation(candidate):
			return candidate
	if sprite.sprite_frames != null:
		for available: String in sprite.sprite_frames.get_animation_names():
			if _has_animation(StringName(available)):
				return StringName(available)
	return &""


func _has_animation(animation_name: StringName) -> bool:
	return is_instance_valid(sprite) and sprite.sprite_frames != null \
		and sprite.sprite_frames.has_animation(animation_name) \
		and sprite.sprite_frames.get_frame_count(animation_name) > 0


func _animation_duration(animation_name: StringName) -> float:
	if not _has_animation(animation_name):
		return 0.0
	var frames: SpriteFrames = sprite.sprite_frames
	var frames_per_second: float = frames.get_animation_speed(animation_name)
	if frames_per_second <= 0.0:
		return 0.0
	var duration: float = 0.0
	for index in range(frames.get_frame_count(animation_name)):
		duration += frames.get_frame_duration(animation_name, index) / frames_per_second
	return duration


func _ensure_default_unlocked() -> void:
	if not unlocked_birds.has(Bird.HERON):
		unlocked_birds.append(Bird.HERON)


func _valid_form(form: int) -> bool:
	return form >= Bird.HERON and form <= Bird.WOODPECKER


# Missing actions are benign for programmatic/headless instantiation. InputMap
# construction remains the project's responsibility, including restart.
func _just_pressed(action_name: StringName) -> bool:
	return InputMap.has_action(action_name) and Input.is_action_just_pressed(action_name)


func _just_released(action_name: StringName) -> bool:
	return InputMap.has_action(action_name) and Input.is_action_just_released(action_name)


func _input_strength(action_name: StringName) -> float:
	return Input.get_action_strength(action_name) if InputMap.has_action(action_name) else 0.0


func _setting_float(settings: Dictionary, key: String, fallback: float) -> float:
	return maxf(0.0, _finite_number(settings.get(key, fallback), fallback))


func _finite_number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number: float = float(value)
		if is_finite(number):
			return number
	return fallback


func _setting_bool(settings: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = settings.get(key, fallback)
	return bool(value) if value is bool else fallback


func _setting_vector(value: Variant, fallback: Vector2, uniform: bool = false) -> Vector2:
	var result: Vector2 = fallback
	if value is Vector2 or value is Vector2i:
		result = Vector2(value)
	elif value is Array and value.size() >= 2:
		result = Vector2(_finite_number(value[0], fallback.x), _finite_number(value[1], fallback.y))
	elif value is Dictionary:
		result = Vector2(_finite_number(value.get("x", fallback.x), fallback.x), _finite_number(value.get("y", fallback.y), fallback.y))
	elif uniform and (value is float or value is int):
		var scale_value: float = _finite_number(value, fallback.x)
		result = Vector2(scale_value, scale_value)
	return result if result.is_finite() else fallback
