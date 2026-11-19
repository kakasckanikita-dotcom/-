extends Node3D
## Конь: модель «Armored Horse» (naminoff, CC BY 4.0). Модель статичная,
## поэтому скачка изображается покачиванием и наклоном корпуса.

const SCENE := preload("res://assets/horse/armored_horse.glb")
const LENGTH := 2.5

var model: Node3D
var phase := 0.0
var seat_y := 1.3
var seat_z := 0.35 # седло позади центра модели (вперёд — это −Z)
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
	# по габаритам седла модели: сиденье ~77 % высоты, центр седла чуть позади середины
	seat_y = a.size.y * 0.77
	seat_z = a.size.z * 0.1


func _aabb() -> AABB:
	var res := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = Models.mesh_box(mi.mesh, Models.rel_xf(mi, self))
		res = b if first else res.merge(b)
		first = false
	return res


func animate(speed: float, delta: float) -> void:
	var k := clampf(speed / 12.0, 0.0, 1.4)
	phase += delta * (2.0 + speed * 0.85)
	model.position = _base + Vector3(0, absf(sin(phase)) * 0.16 * k, 0)
	rotation.x = sin(phase * 2.0) * 0.045 * k


## Куда посадить всадника (в координатах родителя), hip_y — высота его бёдер.
func rider_pos(yaw: float, hip_y: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, seat_y - hip_y, seat_z)
