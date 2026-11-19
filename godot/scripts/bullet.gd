extends Node2D
## Пуля. Каждый кадр пускает луч от старой позиции к новой, поэтому быстрая
## пуля не пролетает сквозь цели.

var vel := Vector2.ZERO
var life := 0.6
var dmg := 10.0
var from_player := true
var shooter: RID


func _ready() -> void:
	z_index = 5


func _physics_process(delta: float) -> void:
	var to := global_position + vel * delta
	# слой 1 — мир, 2 — герой, 3 (бит 4) — NPC
	var mask := 1 | (4 if from_player else 2)
	var q := PhysicsRayQueryParameters2D.create(global_position, to, mask, [shooter])
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var c = hit["collider"]
		if c.has_method("take_hit"):
			c.take_hit(dmg, from_player)
		else:
			var col := Color("999999") if c.get("kind") == "rock" else Color("8a6440") if c.get("kind") == null else Color("4d7a3a")
			Game.world.fx.burst(hit["position"], col, 4, 20.0, 60.0, 0.3, 2.0)
		queue_free()
		return
	global_position = to
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var col := Color(1.0, 0.9, 0.6, 0.9) if from_player else Color(1.0, 0.67, 0.47, 0.8)
	draw_line(Vector2.ZERO, -vel * 0.015, col, 2.0)
