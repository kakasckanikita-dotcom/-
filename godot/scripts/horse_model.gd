extends Node3D
## Конь: модель «Armored Horse» (naminoff, CC BY 4.0). Модель статичная,
## поэтому скачка изображается покачиванием и наклоном корпуса.

const SCENE := preload("res://assets/horse/armored_horse.glb")
const LENGTH := 2.5

var model: Node3D
var phase := 0.0
var seat_y := 1.3
var _base := Vector3.ZERO


func _ready() -> void:
	model = SCENE.instantiate()
	add_child(model)
	var a := _aabb()
	var s := LENGTH / maxf(a.size.z, 0.01)
	model.scale = Vector3.ONE * s
	model.rotation.y = PI # голова модели смотрит в +Z, а «вперёд» в Godot — это −Z
	a = _aabb()
	model.position = Vector3(-a.get_center().x, -a.position.y, -a.get_center().z)
	_base = model.position
	seat_y = a.size.y * 0.66


func _aabb() -> AABB:
	var inv := global_transform.affine_inverse()
	var res := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		res = b if first else res.merge(b)
		first = false
	return res


func animate(speed: float, delta: float) -> void:
	var k := clampf(speed / 12.0, 0.0, 1.4)
	phase += delta * (2.0 + speed * 0.85)
	model.position = _base + Vector3(0, absf(sin(phase)) * 0.16 * k, 0)
	rotation.x = sin(phase * 2.0) * 0.045 * k
