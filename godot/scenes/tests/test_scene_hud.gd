extends CanvasLayer

@onready var status: Label = $Status

func _process(_delta: float) -> void:
	var world: HeronWorld = get_parent().get_parent() as HeronWorld
	if not world or not is_instance_valid(world.player):
		return
	var player: HeronPlayer = world.player
	var surface: String = "空中" if not player.on_ground else ("冰面" if player.on_ice else "普通地面")
	var movement: String = "站立" if is_zero_approx(player.velocity.x) else "行走"
	if player.ice_sliding:
		movement = "滑行" if player.on_ground else "腾空滑行"
	elif not player.on_ground:
		movement = "上升" if player.velocity.y < 0.0 else "下落"
	status.text = "%s  ·  %s  ·  %s    |    水平速度 %03.0f / %03.0f    |    R 重置" % [
		HeronUI.BIRD_NAMES[player.bird], surface, movement, absf(player.velocity.x), player.current_speed,
	]
