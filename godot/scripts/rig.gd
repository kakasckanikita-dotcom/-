extends Node3D
## Персонаж на скелете Mixamo (hero.glb, npc.glb) с анимациями из захвата
## движения (assets/anim/human.json: стойка, шаг, бег, прицел, выстрел,
## перезарядка, смерть). Анимации запечены как повороты костей относительно
## позы «Т» в осях тела (право, верх, вперёд), поэтому подходят любой модели
## на скелете Mixamo, даже с другой ориентацией костей.
## Сверху — слой рук (прицел/выстрел/перезарядка), посадка в седло и езда.

const ANIM_ROLES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
const UPPER := ["Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const WALK_SPEED := 1.4 # м/с, при которых клип шага идёт в своём темпе
const RUN_SPEED := 4.2

static var _lib: Dictionary = {}
static var _dir_child: Dictionary = {} # роль конечности -> дочерняя роль

var skel: Skeleton3D
var inst: Node3D
var fix: Node3D
var bones := {} # роль -> индекс кости
var R := Vector3.RIGHT # оси тела в пространстве скелета
var U := Vector3.UP
var F := Vector3.FORWARD
var _B := Basis()
var _Bi := Basis()
var hip_y := 0.95 # высота бёдер над землёй после нормализации
var _hip_h := 1.0 # то же в единицах скелета
var _ri := [] # индекс роли -> индекс кости (или −1)
var _rp := [] # индекс роли -> индекс роли-родителя (или −1)
var _grest_r := [] # глобальный поворот кости в покое
var _rest_dir := [] # направление кости в покое (для конечностей)
var _hips_rest := Vector3.ZERO
var _hips_parent := Transform3D.IDENTITY
var _upper_mask := []
var _leg_mask := []
var _hand_mask := []

var aiming := false
var mounted := false
var mount_k := 1.0 # 0..1 — ход анимации посадки (1 — сидит)
var dead := false
var gun: Node3D
var _attach: BoneAttachment3D
var _phase := 0.0
var _w_run := 0.0
var _w_move := 0.0
var _w_aim := 0.0
var _upper_clip := "" # «shoot», «reload» — разовый клип рук
var _upper_t := 0.0
var _death := ""
var _death_t := 0.0
var _breath := 0.0
var _idle_t := 0.0


static func lib() -> Dictionary:
	if _lib.is_empty():
		var f := FileAccess.open("res://assets/anim/human.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		_dir_child = d.get("dir", {})
		for name in d["anims"]:
			var a: Dictionary = d["anims"][name]
			var frames := []
			for fr in a["frames"]:
				var qs := []
				for i in ANIM_ROLES.size():
					var q: Array = fr[i]
					if q.size() == 3:
						qs.append(Vector3(q[0], q[1], q[2]).normalized())
					else:
						qs.append(Quaternion(q[0], q[1], q[2], q[3]).normalized())
				var h: Array = fr[ANIM_ROLES.size()]
				qs.append(Vector3(h[0], h[1], h[2]))
				frames.append(qs)
			_lib[name] = {"len": maxf(float(a["len"]), 0.001), "frames": frames}
	return _lib


func build(model: String, height := 1.8, tint := Color.WHITE, with_gun := true) -> void:
	lib()
	fix = Node3D.new()
	add_child(fix)
	inst = Models.scene(model).instantiate()
	fix.add_child(inst)
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		var role := _role(skel.get_bone_name(i))
		if role in ANIM_ROLES and not bones.has(role):
			bones[role] = i
	skel.reset_bone_poses()
	R = (_gp("RightUpLeg") - _gp("LeftUpLeg")).normalized()
	var up := _gp("Head") - _gp("Hips")
	U = (up - R * up.dot(R)).normalized()
	F = U.cross(R)
	_B = Basis(R, U, F)
	_Bi = _B.inverse()
	# поворот и масштаб: голова вверх (+Y), лицо вперёд (−Z), рост = height
	var sx := Models.rel_xf(skel, fix)
	var rot := Basis((sx.basis * R).normalized(), (sx.basis * U).normalized(), (sx.basis * -F).normalized()).transposed()
	var foot := minf(_gp("LeftFoot").dot(U), _gp("RightFoot").dot(U))
	var top := _gp("Head").dot(U)
	var skel_scale := sx.basis.get_scale().x
	var s := height / maxf((top - foot) * skel_scale * 1.13, 0.0001)
	fix.transform = Transform3D(rot.scaled(Vector3.ONE * s), Vector3.ZERO)
	var xf := fix.transform * sx
	var foot_p := xf * (_gp("LeftFoot") + _gp("RightFoot")) * 0.5
	var hips_p := xf * _gp("Hips")
	fix.position = Vector3(-hips_p.x, -foot_p.y + 0.1, -hips_p.z)
	hip_y = hips_p.y - foot_p.y + 0.1
	_hip_h = _gp("Hips").dot(U) - foot
	# таблицы для быстрого применения анимаций
	for r in ANIM_ROLES:
		var bi: int = bones.get(r, -1)
		_ri.append(bi)
		_grest_r.append(skel.get_bone_global_rest(bi).basis.orthonormalized() if bi >= 0 else Basis())
		var pr := -1
		if bi >= 0:
			var p := skel.get_bone_parent(bi)
			if p >= 0:
				pr = ANIM_ROLES.find(_role(skel.get_bone_name(p)))
		_rp.append(pr)
		_upper_mask.append(r in UPPER)
		var rd := Vector3.ZERO
		if _dir_child.has(r) and bi >= 0 and bones.has(_dir_child[r]):
			rd = (_gp(_dir_child[r]) - _gp(r)).normalized()
		_rest_dir.append(rd)
		_leg_mask.append(r.contains("Leg") or r.contains("Foot") or r.contains("Toe"))
		_hand_mask.append(r.ends_with("Hand"))
	var hb: int = bones["Hips"]
	_hips_rest = skel.get_bone_global_rest(hb).origin
	var hp := skel.get_bone_parent(hb)
	_hips_parent = skel.get_bone_global_rest(hp) if hp >= 0 else Transform3D.IDENTITY
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
	_breath = randf() * TAU
	_idle_t = randf() * 8.0
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


# ---------- клипы ----------
## Поза клипа в момент t (секунды), с интерполяцией между кадрами.
func _sample(clip: String, t: float, loop: bool) -> Array:
	var c: Dictionary = _lib[clip]
	var frames: Array = c["frames"]
	var n := frames.size()
	if n == 1:
		return frames[0]
	var len: float = c["len"]
	var u := fposmod(t, len) / len if loop else clampf(t / len, 0.0, 1.0)
	var fpos := u * (n - 1)
	var a := int(floor(fpos))
	var b := mini(a + 1, n - 1)
	return _mix(frames[a], frames[b], fpos - a)


func _mix(pa: Array, pb: Array, w: float) -> Array:
	if w <= 0.001:
		return pa
	if w >= 0.999:
		return pb
	var res := []
	res.resize(pa.size())
	for i in ANIM_ROLES.size():
		res[i] = _blend(pa[i], pb[i], w)
	res[ANIM_ROLES.size()] = (pa[ANIM_ROLES.size()] as Vector3).lerp(pb[ANIM_ROLES.size()], w)
	return res


static func _blend(a, b, w: float):
	if a is Vector3:
		return (a as Vector3).slerp(b, w).normalized()
	return (a as Quaternion).slerp(b, w)


## Смешать только кости верхней части тела.
func _mix_upper(base: Array, top: Array, w: float) -> Array:
	if w <= 0.001:
		return base
	var res := base.duplicate()
	for i in ANIM_ROLES.size():
		if _upper_mask[i]:
			res[i] = _blend(base[i], top[i], w)
	return res


## Применить позу к скелету.
func _apply(pose: Array, skip_legs := false) -> Dictionary:
	var glob := {}
	for i in ANIM_ROLES.size():
		var bi: int = _ri[i]
		if bi < 0:
			continue
		if skip_legs and _leg_mask[i]:
			continue
		if _hand_mask[i]:
			# кисть — продолжение предплечья (позы покоя у моделей разные)
			skel.set_bone_pose_rotation(bi, skel.get_bone_rest(bi).basis.get_rotation_quaternion())
			var pr0: int = _rp[i]
			var pg0: Basis = glob[pr0] if pr0 >= 0 and glob.has(pr0) else _grest(skel.get_bone_parent(bi))
			glob[i] = pg0 * skel.get_bone_rest(bi).basis.orthonormalized()
			continue
		var g: Basis
		var v = pose[i]
		if v is Vector3 and _rest_dir[i] != Vector3.ZERO:
			var want: Vector3 = (_B * (v as Vector3)).normalized()
			g = Basis(Quaternion(_rest_dir[i], want)) * _grest_r[i]
		elif v is Quaternion:
			g = (_B * Basis(v) * _Bi) * _grest_r[i]
		else:
			g = _grest_r[i]
		var pr: int = _rp[i]
		var pg: Basis
		if pr >= 0 and glob.has(pr):
			pg = glob[pr]
		else:
			var p := skel.get_bone_parent(bi)
			pg = _grest(p) if p >= 0 else Basis()
		skel.set_bone_pose_rotation(bi, (pg.inverse() * g).get_rotation_quaternion())
		glob[i] = g
	var off: Vector3 = pose[ANIM_ROLES.size()]
	var hp := _hips_rest + (R * off.x * 0.5 + U * off.y) * _hip_h # без движения вперёд (персонаж двигается сам)
	skel.set_bone_pose_position(_ri[0], _hips_parent.affine_inverse() * hp)
	return glob


# ---------- управление ----------
func shoot_anim() -> void:
	_upper_clip = "shoot"
	_upper_t = 0.0


func reload_anim() -> void:
	_upper_clip = "reload"
	_upper_t = 0.0


func animate(speed: float, delta: float) -> void:
	if skel == null:
		return
	if dead:
		_death_t += delta
		_apply(_sample(_death, _death_t, false))
		return
	var busy := _upper_clip != ""
	if gun:
		gun.visible = aiming or busy # в остальное время револьвер в кобуре
	_w_aim = move_toward(_w_aim, 1.0 if (aiming or _upper_clip == "shoot") and gun else 0.0, delta * 7.0)
	if mounted:
		_animate_mounted(speed, delta)
		return
	# ноги и корпус: стойка / шаг / бег с плавными переходами
	_w_move = move_toward(_w_move, clampf((speed - 0.15) / 1.0, 0.0, 1.0), delta * 5.0)
	_w_run = move_toward(_w_run, clampf((speed - 2.4) / 1.8, 0.0, 1.0), delta * 4.0)
	var wl: float = _lib["walk"]["len"]
	var rl: float = _lib["run"]["len"]
	var cyc := lerpf(wl, rl, _w_run)
	var rate := lerpf(maxf(speed, 0.6) / WALK_SPEED, maxf(speed, 1.0) / RUN_SPEED, _w_run)
	_phase = fposmod(_phase + delta * clampf(rate, 0.4, 2.2) / cyc, 1.0)
	_idle_t += delta
	var pose: Array = _sample("idle", _idle_t, true)
	if _w_move > 0.0:
		var walk := _sample("walk", _phase * wl, true)
		var run := _sample("run", _phase * rl, true)
		pose = _mix(pose, _mix(walk, run, _w_run), _w_move)
	pose = _upper(pose, delta)
	_aim_arm(_apply(pose))


## Слой рук: перезарядка — клипом; прицел и выстрел — вытянутой правой рукой
## (классическая стойка стрелка с револьвером), с отдачей при выстреле.
func _upper(pose: Array, delta: float) -> Array:
	if _upper_clip == "":
		return pose
	_upper_t += delta
	var len: float = _lib[_upper_clip]["len"]
	if _upper_t >= len:
		_upper_clip = ""
		return pose
	if _upper_clip != "reload":
		return pose
	var w := clampf(minf(_upper_t, len - _upper_t) / 0.2, 0.0, 1.0)
	return _mix_upper(pose, _sample("reload", _upper_t, false), w)


func _aim_arm(glob: Dictionary) -> void:
	if _w_aim <= 0.01 or _upper_clip == "reload":
		return
	var recoil := 0.0
	if _upper_clip == "shoot":
		recoil = maxf(0.0, 0.45 - _upper_t * 3.0)
	var rest := (-U * 0.96 + R * 0.2).normalized()
	var dir := rest.slerp((F + U * (0.04 + recoil)).normalized(), _w_aim)
	var si := ANIM_ROLES.find("RightShoulder")
	var pg = glob.get(si, null)
	var a := _aim("RightArm", "RightForeArm", dir, pg)
	_aim("RightForeArm", "RightHand", dir, a)


func _animate_mounted(speed: float, delta: float) -> void:
	_idle_t += delta
	var pose: Array = _sample("idle", _idle_t, true)
	pose = _upper(pose, delta)
	var glob := _apply(pose, true)
	var L := -R
	var k := clampf(mount_k, 0.0, 1.0)
	# сидячая поза: бёдра обхватывают бока коня, голени вдоль боков
	var thigh_l := F * 0.4 - U * 0.65 + L * 0.42
	var thigh_r := F * 0.4 - U * 0.65 + R * 0.42
	var shin_l := -U - F * 0.15 + L * 0.12
	var shin_r := -U - F * 0.15 + R * 0.12
	if k < 1.0:
		# посадка: левая нога в стремени, правая перекидывается через круп
		var s1 := clampf(k / 0.45, 0.0, 1.0)
		var s2 := clampf((k - 0.35) / 0.45, 0.0, 1.0)
		var swing := sin(s2 * PI)
		thigh_l = (-U).lerp(F * 0.75 + U * 0.1 + L * 0.3, s1).lerp(thigh_l, s2)
		shin_l = (-U).lerp(-U + F * 0.2, s1).lerp(shin_l, s2)
		thigh_r = (-U).lerp(R * 0.9 + U * 0.25 - F * 0.35, swing).lerp(thigh_r, clampf((k - 0.6) / 0.4, 0.0, 1.0))
		shin_r = (-U).lerp(R * 0.6 - U * 0.6 - F * 0.2, swing).lerp(shin_r, clampf((k - 0.6) / 0.4, 0.0, 1.0))
	var tl := _aim("LeftUpLeg", "LeftLeg", thigh_l)
	_aim("LeftLeg", "LeftFoot", shin_l, tl)
	var tr := _aim("RightUpLeg", "RightLeg", thigh_r)
	_aim("RightLeg", "RightFoot", shin_r, tr)
	if _w_aim >= 0.5:
		_aim_arm(glob)
	else:
		# руки держат поводья
		var al := _aim("LeftArm", "LeftForeArm", -U * 0.8 + F * 0.35 + L * 0.12)
		_aim("LeftForeArm", "LeftHand", F * 0.9 - U * 0.25 + R * 0.3, al)
		var ar := _aim("RightArm", "RightForeArm", -U * 0.8 + F * 0.35 + R * 0.12)
		_aim("RightForeArm", "RightHand", F * 0.9 - U * 0.25 + L * 0.3, ar)


## Повернуть кость так, чтобы она смотрела в dir (пространство скелета).
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
	# ствол — вдоль предплечья, верх — к «верху» тела (без составляющей вдоль руки)
	var hg := _grest(bones["RightHand"]).inverse()
	var arm := (_gp("RightHand") - _gp("RightForeArm")).normalized()
	var upv := (U - arm * U.dot(arm)).normalized()
	var bx := (hg * arm).normalized()
	var by := (hg * upv).normalized()
	var basis := Basis(bx, by, bx.cross(by).normalized())
	var k := _skel_to_local_scale()
	gun.transform = Transform3D(basis.scaled(Vector3.ONE * k), (bx * 0.07 - by * 0.02) * k)


## Во сколько раз метр снаружи больше единицы внутри кости.
func _skel_to_local_scale() -> float:
	var s := (fix.transform * Models.rel_xf(skel, fix)).basis.get_scale().x
	return 1.0 / maxf(s, 0.000001)


func set_dead(v: bool) -> void:
	dead = v
	if v:
		_death = ["death1", "death1", "death2", "death3"].pick_random()
		_death_t = 0.0
		if gun:
			gun.visible = false
		animate(0.0, 0.0)
	else:
		_death = ""
		skel.reset_bone_poses()
		animate(0.0, 0.0)


func gun_pos() -> Vector3:
	if gun:
		var gx := gun.global_transform
		return gx.origin + (gx.basis * Vector3.RIGHT).normalized() * 0.18
	return global_position + Vector3(0, 1.4, 0)
