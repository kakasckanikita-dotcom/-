extends Node3D
## Персонаж из модели со скелетом Mixamo (hero.glb, npc.glb). Анимации в
## моделях нет, поэтому позы считаются кодом: ходьба, бег, прицеливание,
## посадка в седло. Оси тела берутся из самого скелета (от левого бедра к
## правому, от бёдер к голове), поэтому подходят любые риги Mixamo.
## Интерфейс совпадает с прежним humanoid.gd: build, animate, set_dead, gun_pos.

const ROLES := ["Hips", "Head", "LeftShoulder", "RightShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]

var skel: Skeleton3D
var inst: Node3D
var fix: Node3D
var bones := {} # роль -> индекс кости
var R := Vector3.RIGHT # оси тела в пространстве скелета
var U := Vector3.UP
var F := Vector3.FORWARD
var hip_y := 0.95 # высота бёдер после нормализации (для посадки в седло)
var phase := 0.0
var aiming := false
var mounted := false
var dead := false
var gun: Node3D
var _attach: BoneAttachment3D
var _gun_dir_local := Vector3.RIGHT


func build(model: String, height := 1.8, tint := Color.WHITE, with_gun := true) -> void:
	fix = Node3D.new()
	add_child(fix)
	inst = Models.scene(model).instantiate()
	fix.add_child(inst)
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		var role := _role(skel.get_bone_name(i))
		if role in ROLES and not bones.has(role):
			bones[role] = i
	skel.reset_bone_poses()
	R = (_gp("RightUpLeg") - _gp("LeftUpLeg")).normalized()
	var up := _gp("Head") - _gp("Hips")
	U = (up - R * up.dot(R)).normalized()
	F = U.cross(R)
	# поворот и масштаб: голова вверх (+Y), лицо вперёд (−Z), рост = height
	var sx := Models.rel_xf(skel, fix)
	var r_n := (sx.basis * R).normalized()
	var u_n := (sx.basis * U).normalized()
	var b_n := (sx.basis * -F).normalized()
	var rot := Basis(r_n, u_n, b_n).transposed()
	var foot := minf(_gp("LeftFoot").dot(U), _gp("RightFoot").dot(U))
	var top := _gp("Head").dot(U)
	var skel_scale := sx.basis.get_scale().x
	var body := (top - foot) * skel_scale * 1.13 # от стоп до макушки примерно +13 % к голове
	var s := height / maxf(body, 0.0001)
	fix.transform = Transform3D(rot.scaled(Vector3.ONE * s), Vector3.ZERO)
	var xf := fix.transform * sx
	var foot_p := xf * (_gp("LeftFoot") + _gp("RightFoot")) * 0.5
	var hips_p := xf * _gp("Hips")
	fix.position = Vector3(-hips_p.x, -foot_p.y + 0.07, -hips_p.z)
	hip_y = hips_p.y - foot_p.y + 0.07
	for mi in Models.meshes(inst):
		if tint != Color.WHITE:
			for si in mi.mesh.get_surface_count():
				var m = mi.get_active_material(si)
				if m is BaseMaterial3D:
					var mm: BaseMaterial3D = m.duplicate()
					mm.albedo_color = mm.albedo_color * tint
					mi.set_surface_override_material(si, mm)
	if with_gun and bones.has("RightHand"):
		_attach_gun()
	animate(0.0, 0.0)


func _role(bone_name: String) -> String:
	var n := bone_name
	var k := n.findn("mixamorig")
	if k != -1:
		n = n.substr(k + 9)
	n = n.lstrip(":_")
	var parts := n.split("_")
	if parts.size() > 1 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)


func _gp(role: String) -> Vector3:
	return skel.get_bone_global_rest(bones[role]).origin


func _grest(i: int) -> Basis:
	return skel.get_bone_global_rest(i).basis.orthonormalized()


## Повернуть кость так, чтобы она смотрела в dir (пространство скелета).
## parent_now — текущий глобальный поворот родителя (null — родитель в покое).
func _aim(role: String, child: String, dir: Vector3, parent_now = null) -> Basis:
	var i: int = bones[role]
	var rest_dir := (_gp(child) - _gp(role)).normalized()
	var q := Basis(Quaternion(rest_dir, dir.normalized()))
	var g := q * _grest(i)
	var p := skel.get_bone_parent(i)
	var pg: Basis = parent_now if parent_now != null else (_grest(p) if p >= 0 else Basis())
	skel.set_bone_pose_rotation(i, (pg.inverse() * g).get_rotation_quaternion())
	return g


func _attach_gun() -> void:
	_attach = BoneAttachment3D.new()
	skel.add_child(_attach)
	_attach.bone_idx = bones["RightHand"]
	gun = Models.prop("colt", 0.3, "x")
	_attach.add_child(gun)
	# в позе «Т» рука вытянута вдоль R ладонью вниз: ствол — вдоль руки, верх — вдоль U
	var hg := _grest(bones["RightHand"]).inverse()
	var bx := (hg * R).normalized()
	var by := (hg * U).normalized()
	_gun_dir_local = bx
	var basis := Basis(bx, by, bx.cross(by).normalized())
	var k := _skel_to_local_scale()
	gun.transform = Transform3D(basis.scaled(Vector3.ONE * k), (bx * 0.07 - by * 0.02) * k)


## Во сколько раз метр снаружи больше единицы внутри кости.
func _skel_to_local_scale() -> float:
	var s := (fix.transform * Models.rel_xf(skel, fix)).basis.get_scale().x
	return 1.0 / maxf(s, 0.000001)


func animate(speed: float, delta: float) -> void:
	if dead or skel == null:
		return
	if gun:
		gun.visible = aiming # в остальное время револьвер в кобуре
	var L := -R
	if mounted:
		var tl := _aim("LeftUpLeg", "LeftLeg", F * 0.8 - U * 0.25 + L * 0.5)
		_aim("LeftLeg", "LeftFoot", -U + F * 0.15 + L * 0.15, tl)
		var tr := _aim("RightUpLeg", "RightLeg", F * 0.8 - U * 0.25 + R * 0.5)
		_aim("RightLeg", "RightFoot", -U + F * 0.15 + R * 0.15, tr)
		var al := _aim("LeftArm", "LeftForeArm", -U * 0.6 + F * 0.5 + L * 0.2)
		_aim("LeftForeArm", "LeftHand", F * 0.9 - U * 0.2, al)
		_arm_right(0.0)
		return
	var k := clampf(speed / 4.0, 0.0, 1.5)
	phase += delta * (3.0 + speed * 1.6)
	var sw := sin(phase) * 0.55 * k
	var bend := maxf(0.0, -cos(phase)) * 0.9 * k
	var bend2 := maxf(0.0, cos(phase)) * 0.9 * k
	var dl := (-U).rotated(R, -sw)
	var dr := (-U).rotated(R, sw)
	var tl := _aim("LeftUpLeg", "LeftLeg", dl)
	_aim("LeftLeg", "LeftFoot", dl.rotated(R, bend), tl)
	var tr := _aim("RightUpLeg", "RightLeg", dr)
	_aim("RightLeg", "RightFoot", dr.rotated(R, bend2), tr)
	var ad := (-U * 0.96 + L * 0.2).rotated(R, sw * 0.8)
	var al := _aim("LeftArm", "LeftForeArm", ad)
	_aim("LeftForeArm", "LeftHand", ad.rotated(R, -0.25 - 0.3 * k), al)
	_arm_right(sw)


func _arm_right(sw: float) -> void:
	if aiming:
		var a := _aim("RightArm", "RightForeArm", F + U * 0.05)
		_aim("RightForeArm", "RightHand", F + U * 0.05, a)
	else:
		var d := (-U * 0.96 + R * 0.2).rotated(R, -sw * 0.8)
		var a := _aim("RightArm", "RightForeArm", d)
		_aim("RightForeArm", "RightHand", d.rotated(R, -0.25), a)


func set_dead(v: bool) -> void:
	dead = v
	if v:
		rotation.x = -PI / 2.0
		position.y = 0.25
	else:
		rotation.x = 0.0
		position.y = 0.0
		animate(0.0, 0.0)


func gun_pos() -> Vector3:
	if gun:
		var gx := gun.global_transform
		return gx.origin + (gx.basis * Vector3.RIGHT).normalized() * 0.18
	return global_position + Vector3(0, 1.4, 0)
