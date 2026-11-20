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
var _dust: CPUParticles3D
var _splash_t := 0.0


func _ready() -> void:
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
	# седло: над серединой спины (кости Spine идут от крупа к шее)
	var bi := _bone("Spine_02")
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_idx = bi
	seat = Node3D.new()
	att.add_child(seat)
	var spine := _bone_pos_i(bi)
	var want := Vector3(spine.x, spine.y + 0.2, spine.z + 0.15)
	var att_g := skel.global_transform * skel.get_bone_global_pose(bi)
	seat.transform = att_g.affine_inverse() * Transform3D(Basis(), to_global(want))
	seat_y = want.y
	seat_z = want.z
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


func play_death() -> void:
	_current = "Death"
	ap.speed_scale = 1.0
	ap.play(_anim("Death"), 0.2)


## Куда поставить всадника (в координатах родителя коня): бёдра — на седло.
func rider_pos(_yaw: float, hip_y: float) -> Vector3:
	var p := get_parent() as Node3D
	return p.to_local(seat.global_position) - Vector3(0, hip_y, 0)
