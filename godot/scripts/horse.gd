extends CharacterBody2D
## Конь героя. Без всадника стоит на месте; по свисту скачет к хозяину.

var ang := 0.0
var called := false
var horse_name := "Буран"
var t := 0.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var s := CircleShape2D.new()
	s.radius = 16.0
	cs.shape = s
	add_child(cs)


func _physics_process(delta: float) -> void:
	t += delta
	if not visible:
		return
	var p: Node2D = Game.world.player
	var d := global_position.distance_to(p.global_position)
	if called and d > 55.0:
		var dir := (p.global_position - global_position).normalized()
		ang = dir.angle()
		velocity = dir * (320.0 if d > 200.0 else 120.0)
		move_and_slide()
	else:
		called = false
		velocity = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	Gfx.horse(self, Vector2.ZERO, ang, Color("6b3e22"), true, t)
