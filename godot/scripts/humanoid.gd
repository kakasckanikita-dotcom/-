extends Node3D
## Человек из примитивов, смотрит в −Z. Анимация ходьбы, прицеливание,
## посадка в седло и смерть — всё кодом.

const SKIN := Color("e0b48a")

var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var gun: Node3D
var phase := 0.0
var aiming := false
var mounted := false
var dead := false


func build(body: Color, hat: Color, opts := {}) -> void:
	var pants: Color = opts.get("pants", Color("3a3a48"))
	leg_l = _limb(Vector3(-0.12, 0.95, 0), 0.1, 0.95, pants, true)
	leg_r = _limb(Vector3(0.12, 0.95, 0), 0.1, 0.95, pants, true)
	Mk.capsule(self, 0.21, 0.78, Vector3(0, 1.3, 0), body)
	Mk.box(self, Vector3(0.44, 0.08, 0.3), Vector3(0, 1.0, 0), Color("2a1a10"))
	arm_l = _limb(Vector3(-0.3, 1.55, 0), 0.07, 0.62, body, false)
	arm_r = _limb(Vector3(0.3, 1.55, 0), 0.07, 0.62, body, false)
	if opts.get("gun", true):
		gun = Mk.box(arm_r, Vector3(0.05, 0.3, 0.1), Vector3(0, -0.72, -0.04), Color("2a2a2a"))
	Mk.sphere(self, 0.13, Vector3(0, 1.8, 0), SKIN)
	Mk.cyl(self, 0.32, 0.32, 0.03, Vector3(0, 1.9, 0), hat, 12)
	Mk.cyl(self, 0.13, 0.16, 0.18, Vector3(0, 2.0, 0), hat, 10)
	if opts.get("bandana", false):
		Mk.box(self, Vector3(0.22, 0.1, 0.06), Vector3(0, 1.74, -0.11), Color("b8392a"))
	if opts.get("star", false):
		var s := Mk.box(self, Vector3(0.08, 0.08, 0.02), Vector3(-0.1, 1.42, -0.2), Color("e8c35a"))
		s.material_override = Mk.mat(Color("e8c35a"), 0.3, 0.6)


func _limb(at: Vector3, r: float, h: float, c: Color, boot: bool) -> Node3D:
	var p := Node3D.new()
	p.position = at
	add_child(p)
	Mk.capsule(p, r, h, Vector3(0, -h / 2.0 + r * 0.5, 0), c)
	if boot:
		Mk.box(p, Vector3(0.16, 0.14, 0.28), Vector3(0, -h + 0.08, -0.05), Color("3a2412"))
	else:
		Mk.sphere(p, 0.07, Vector3(0, -h + 0.02, 0), SKIN)
	return p


func animate(speed: float, delta: float) -> void:
	if dead:
		return
	if mounted:
		leg_l.rotation = Vector3(0.55, 0, -0.55)
		leg_r.rotation = Vector3(0.55, 0, 0.55)
		arm_l.rotation = Vector3(0.7, 0, 0)
		arm_r.rotation = Vector3(PI / 2.0, 0, 0) if aiming else Vector3(0.7, 0, 0)
		return
	var k := clampf(speed / 4.0, 0.0, 1.4)
	phase += delta * (3.0 + speed * 1.7)
	var s := sin(phase) * 0.7 * k
	leg_l.rotation = Vector3(s, 0, 0)
	leg_r.rotation = Vector3(-s, 0, 0)
	arm_l.rotation = Vector3(-s * 0.8, 0, 0)
	arm_r.rotation = Vector3(PI / 2.0, 0, 0) if aiming else Vector3(s * 0.8, 0, 0)


func set_dead(v: bool) -> void:
	dead = v
	if v:
		rotation.x = -PI / 2.0
		position.y = 0.2
		for l in [leg_l, leg_r, arm_l, arm_r]:
			l.rotation = Vector3.ZERO
	else:
		rotation.x = 0.0
		position.y = 0.0


func gun_pos() -> Vector3:
	if gun:
		return gun.global_position
	return global_position + Vector3(0, 1.5, 0)
