extends Node3D
## Конь с настоящими анимациями: «Horse» (henry_7, CC BY 4.0) — стойка, шаг,
## галоп с поворотами, остановка, смерть. Анимация выбирается по скорости,
## темп подстраивается под реальную скорость. Всадник крепится к кости спины
## под седлом и покачивается вместе с конём.

const SCENE := preload("res://assets/models/horse_anim.glb")
const LENGTH := 2.4
const WALK_SPEED := 1.8 # м/с, при которых клип шага выглядит естественно
const GALLOP_SPEED := 13.0

var model: Node3D
var ap: AnimationPlayer
var skel: Skeleton3D
var seat: Node3D # точка на седле, двигается вместе со спиной коня
var seat_y := 1.6
var seat_z := 0.0
var _current := ""
var _turn := 0.0
var _last_yaw := 0.0
var _idle_t := 0.0
var _seat_v: Array = [] # вершины седла: [позиция, [индексы бинда], [веса]]
var _seat_off := Vector3.ZERO # от среднего этих вершин до точки сиденья
var _saddle_mi: MeshInstance3D
var _bind_bone := PackedInt32Array()
var rider: Node3D = null # всадник, которого конь держит в седле
var rider_hip := 0.0 # высота сустава бедра всадника над его «нулём»
var rider_sit := 0.0 # от поверхности седла до сустава бедра
var _override_t := 0.0 # идёт разовый клип (дыбы), обычные не выбираются
var _dust: CPUParticles3D
var _splash_t := 0.0


func _ready() -> void:
	process_priority = 10 # после AnimationPlayer: поза седла уже текущая
	model = SCENE.instantiate()
	var fix := Node3D.new()
	add_child(fix)
	fix.add_child(model)
	model.rotation.y = PI # голова модели смотрит в +Z, «вперёд» в Godot — это −Z
	ap = model.find_children("*", "AnimationPlayer", true, false)[0]
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	# клипы движения и стойки должны повторяться (из glTF они приходят без петли)
	for a in ap.get_animation_list():
		var once := a.contains("Death") or a.contains("Fallen") or a.contains("Jump") or a.contains("Arise") or a.contains("Run_Stop") or a.contains("Buck")
		ap.get_animation(a).loop_mode = Animation.LOOP_NONE if once else Animation.LOOP_LINEAR
	ap.play(_anim("1 Ilde"))
	ap.seek(0.0, true)
	# размер и положение — по костям в позе стойки (габариты меша у этой модели неточные)
	var head := _bone_pos("Head_00")
	var pelvis := _bone_pos("Pelvis")
	var low := INF
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).contains("Toe") and skel.get_bone_name(i).contains("end"):
			low = minf(low, _bone_pos_i(i).y)
	var body := absf(head.z - pelvis.z) + 0.55 # от головы до хвоста примерно
	var s := LENGTH / maxf(body, 0.001)
	fix.scale = Vector3.ONE * s
	head = _bone_pos("Head_00")
	pelvis = _bone_pos("Pelvis")
	low = INF
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).contains("Toe") and skel.get_bone_name(i).contains("end"):
			low = minf(low, _bone_pos_i(i).y)
	var cz := (head.z + pelvis.z + 0.45) / 2.0
	fix.position = Vector3(-(head.x + pelvis.x) / 2.0, -low + 0.04, -cz)
	# седло: точка сиденья берётся с настоящей поверхности седла (меш Saddle1) —
	# несколько вершин в ложбине между луками, которые каждый кадр пересчитываются
	# по костям скелета, так что точка двигается вместе с седлом на любом аллюре
	_setup_seat()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _anim(n: String) -> String:
	for a in ap.get_animation_list():
		if a.ends_with(n):
			return a
	return ""


func _bone(part: String) -> int:
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).contains(part):
			return i
	return 0


func _bone_pos_i(i: int) -> Vector3:
	return to_local(skel.global_transform * skel.get_bone_global_pose(i).origin)


func _bone_pos(part: String) -> Vector3:
	return _bone_pos_i(_bone(part))


func _play(n: String, rate: float, blend := 0.3) -> void:
	var a := _anim(n)
	if a == "":
		return
	if _current != n:
		_current = n
		ap.play(a, blend)
	ap.speed_scale = rate


## speed — скорость в м/с; поворот считается по изменению курса.
func animate(speed: float, delta: float) -> void:
	if ap == null:
		return
	if _override_t > 0.0:
		_override_t -= delta
		_hoof_fx(speed, delta)
		return
	var yaw := rotation.y
	if delta > 0.0:
		var dy := wrapf(yaw - _last_yaw, -PI, PI) / delta
		_turn = lerpf(_turn, dy, minf(1.0, delta * 6.0))
	_last_yaw = yaw
	var side := ""
	if _turn > 0.6:
		side = "_L"
	elif _turn < -0.6:
		side = "_R"
	if speed < 0.4:
		_idle_t += delta
		_play("1 Ilde", 1.0, 0.4)
	elif speed < 6.5:
		_idle_t = 0.0
		_play("Walk" + side, clampf(speed / WALK_SPEED, 0.6, 2.4))
	else:
		_idle_t = 0.0
		_play("Gallop" + side, clampf(speed / GALLOP_SPEED, 0.7, 1.5))
	_hoof_fx(speed, delta)


## Пыль из-под копыт на скаку, брызги в реке.
func _hoof_fx(speed: float, delta: float) -> void:
	if Game.world == null or Game.world.fx == null:
		return
	if _dust == null:
		_dust = Game.world.fx.trail()
		add_child(_dust)
	var wet: bool = Game.world.in_water(global_position)
	_dust.emitting = is_visible_in_tree() and speed > 4.5 and not wet
	if wet and speed > 1.2 and is_visible_in_tree():
		_splash_t -= delta
		if _splash_t <= 0.0:
			_splash_t = clampf(1.6 / speed, 0.12, 0.6)
			var p := global_position + global_basis.z * randf_range(-0.8, 0.8)
			Game.world.fx.splash(Vector3(p.x, -0.45, p.z), speed > 6.0)
			if randf() < 0.5:
				Game.play_at("splash", p, -10.0, randf_range(0.8, 1.2), 6.0)


## Разовый клип (например, «Buck_1» — встаёт на дыбы).
func play_once(n: String) -> void:
	var a := _anim(n)
	if a == "" or _override_t > 0.0:
		return
	_current = n
	ap.play(a, 0.15)
	ap.speed_scale = 1.0
	_override_t = ap.get_animation(a).length * 0.95


func play_death() -> void:
	_current = "Death"
	ap.speed_scale = 1.0
	ap.play(_anim("Death"), 0.2)


## Куда поставить всадника (в координатах родителя коня): ягодицы — на седло.
func rider_pos(_yaw: float, hip_y: float, sit := -1.0) -> Vector3:
	var p := get_parent() as Node3D
	return p.to_local(seat_global()) - Vector3(0, hip_y - (sit if sit >= 0.0 else rider_sit), 0)


## Точка сиденья в мире — по текущей позе скелета (без отставания на кадр).
func seat_global() -> Vector3:
	if _seat_v.is_empty():
		return seat.global_position
	var mats := {}
	var acc := Vector3.ZERO
	for v in _seat_v:
		var pos := Vector3.ZERO
		var bs: Array = v[1]
		var ws: Array = v[2]
		for j in bs.size():
			var b: int = bs[j]
			if not mats.has(b):
				mats[b] = skel.get_bone_global_pose(_bind_bone[b]) * _saddle_mi.skin.get_bind_pose(b)
			pos += (mats[b] * (v[0] as Vector3)) * float(ws[j])
		acc += pos
	acc /= float(_seat_v.size())
	return skel.global_transform * (acc + skel.global_transform.basis.inverse() * (global_basis * _seat_off))


func _setup_seat() -> void:
	# запасной вариант — кость спины
	var bi := _bone("Spine_02")
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_idx = bi
	seat = Node3D.new()
	att.add_child(seat)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh and mi.mesh.resource_name.contains("Saddle1") and mi.skin:
			_saddle_mi = mi
	if _saddle_mi == null:
		return
	var skin := _saddle_mi.skin
	_bind_bone.resize(skin.get_bind_count())
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		_bind_bone[b] = bone if bone >= 0 else skel.find_bone(skin.get_bind_name(b))
	var arr := _saddle_mi.mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var B = arr[Mesh.ARRAY_BONES]
	var W = arr[Mesh.ARRAY_WEIGHTS]
	if V.is_empty() or W.is_empty():
		return
	var nb: int = W.size() / V.size()
	# все вершины в координатах коня (поза стойки)
	var loc := PackedVector3Array()
	loc.resize(V.size())
	var cx := 0.0
	var zmin := INF
	var zmax := -INF
	for i in V.size():
		var p := Vector3.ZERO
		for j in nb:
			var w: float = W[i * nb + j]
			if w > 0.0:
				p += (skel.get_bone_global_pose(_bind_bone[B[i * nb + j]]) * skin.get_bind_pose(B[i * nb + j]) * V[i]) * w
		var l := to_local(skel.global_transform * p)
		loc[i] = l
		cx += l.x
		zmin = minf(zmin, l.z)
		zmax = maxf(zmax, l.z)
	cx /= V.size()
	# ложбина сиденья: верх седла по средней линии, самое низкое место между луками
	var best := Vector3(cx, INF, 0)
	var n := 24
	for k in range(int(n * 0.25), int(n * 0.75)):
		var z0 := lerpf(zmin, zmax, float(k) / n)
		var z1 := lerpf(zmin, zmax, float(k + 1) / n)
		var top := -INF
		for l in loc:
			if l.z >= z0 and l.z < z1 and absf(l.x - cx) < 0.06:
				top = maxf(top, l.y)
		if top > -INF and top < best.y:
			best = Vector3(cx, top, (z0 + z1) / 2.0)
	if best.y == INF:
		return
	# 12 вершин верхней поверхности рядом с этой точкой
	var cand := []
	for i in V.size():
		var d := loc[i] - best
		if absf(d.x) < 0.12 and absf(d.z) < 0.12 and d.y > -0.04:
			cand.append([d.length(), i])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var avg := Vector3.ZERO
	for c in cand.slice(0, 12):
		var i: int = c[1]
		var bs := []
		var ws := []
		for j in nb:
			var w: float = W[i * nb + j]
			if w > 0.0:
				bs.append(B[i * nb + j])
				ws.append(w)
		_seat_v.append([V[i], bs, ws])
		avg += loc[i]
	if _seat_v.is_empty():
		return
	avg /= float(_seat_v.size())
	_seat_off = best - avg
	seat_y = best.y
	seat_z = best.z



## Конь сам держит всадника в седле — после своей анимации в этом же кадре.
func _process(_delta: float) -> void:
	if rider and is_instance_valid(rider) and rider.get_parent() == get_parent():
		rider.position = rider_pos(rotation.y, rider_hip)
