extends CharacterBody3D
## Конь героя, Буран. Без всадника стоит на месте; по свисту скачет к хозяину.

const HorseModelScript := preload("res://scripts/horse_model.gd")

var yaw := 0.0
var called := false
var horse_name := "Буран"
var model: Node3D
var _snort_t := 12.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = 0.9
	s.height = 2.0
	cs.shape = s
	cs.position.y = 1.0
	add_child(cs)
	model = HorseModelScript.new()
	add_child(model)


func _physics_process(delta: float) -> void:
	if not visible:
		return
	var p: Node3D = Game.world.player
	var to := p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var spd := 0.0
	if called and d > 3.5:
		var dir := to / d
		spd = 13.0 if d > 20.0 else 4.0
		yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), minf(1.0, delta * 6.0))
		velocity = dir * spd
		var before := global_position
		move_and_slide()
		Game.world.ground_move(self, before)
	else:
		if called:
			Game.play_at("neigh", global_position + Vector3(0, 1.8, 0), -2.0, randf_range(0.95, 1.05), 10.0)
		called = false
		velocity = Vector3.ZERO
		global_position.y = Game.world.ground(global_position.x, global_position.z)
	_snort_t -= delta
	if _snort_t <= 0.0:
		_snort_t = randf_range(14.0, 30.0)
		if p.global_position.distance_to(global_position) < 25.0:
			Game.play_at("snort", global_position + Vector3(0, 1.6, 0), -6.0, randf_range(0.9, 1.1), 6.0)
	model.rotation.y = yaw
	model.animate(spd, delta)
