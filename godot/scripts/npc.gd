extends CharacterBody3D
## Любой персонаж, кроме героя: бандит, главарь, горожанин, шериф или конный
## помощник шерифа. Поведение зависит от вида и от розыска героя.

const RigScript := preload("res://scripts/rig.gd")
const HorseModelScript := preload("res://scripts/horse_model.gd")

const KINDS := {
	"bandit": {"hp": 100.0, "tint": Color(1.0, 0.8, 0.75), "spd": 3.6, "dmg": 9.0, "cd": Vector2(1.0, 1.9)},
	"leader": {"hp": 280.0, "tint": Color(0.5, 0.5, 0.55), "spd": 3.4, "dmg": 14.0, "cd": Vector2(0.6, 1.1)},
	"folk": {"hp": 60.0, "tint": Color(0.85, 0.9, 1.0), "spd": 1.8, "dmg": 0.0, "cd": Vector2(1.0, 1.0)},
	"sheriff": {"hp": 150.0, "tint": Color(0.8, 0.85, 0.95), "spd": 3.8, "dmg": 12.0, "cd": Vector2(0.8, 1.4)},
	"lawman": {"hp": 130.0, "tint": Color(0.85, 0.85, 0.78), "spd": 12.0, "dmg": 11.0, "cd": Vector2(0.9, 1.6)},
}

var kind := "bandit"
var hp := 100.0
var max_hp := 100.0
var yaw := 0.0
var cd := 1.0
var clip := 6
var reload := 0.0
var home := Vector3.ZERO
var wt := Vector3.ZERO
var wt_t := 0.0
var strafe := 1.0
var str_t := 0.0
var aggro := false
var dead := false
var dead_t := 0.0
var flee := 0.0
var tint := Color.WHITE
var height := 1.8
var mounted := false
var town = null
var camp = null
var npc_name := ""
var model: Node3D
var horse_model: Node3D
var name_label: Label3D
var hp_bar: MeshInstance3D
var _think := 0.0
var _anim_acc := 0.0
var voice := "" # набор голосовых реплик
var body := "npc" # модель тела
var pose_mode := "" # "" — ходит; "sit" — сидит; "stand" — стоит на месте; "chat" — беседует
var indoor := false
var seat_h := 0.62 # высота сиденья для pose_mode = "sit"
var _was_engaged := false
var _was_fleeing := false
var _chat_t := 0.0


func setup(k: String, pos: Vector3) -> void:
	kind = k
	var d: Dictionary = KINDS[k]
	hp = d["hp"]
	max_hp = hp
	tint = d["tint"]
	height = randf_range(1.74, 1.88)
	mounted = k == "lawman"
	position = pos
	home = pos
	wt = pos
	yaw = randf() * TAU
	cd = randf_range(0.5, 1.5)
	# горожане разные: часть — бородачи в рубахах
	if k == "folk" and randf() < 0.5:
		body = "bearded"
	match k:
		"bandit": voice = "banda" if randf() < 0.5 else "bandb"
		"leader": voice = "banda"
		"folk": voice = "townm"
		"sheriff": voice = "sheriff"
		"lawman": voice = "posse"


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	motion_mode = MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	if mounted:
		var s := CylinderShape3D.new()
		s.radius = 0.9
		s.height = 3.2
		cs.shape = s
		cs.position.y = 1.6
	else:
		var s := CapsuleShape3D.new()
		s.radius = 0.35
		s.height = 2.0
		cs.shape = s
		cs.position.y = 1.0
	add_child(cs)
	add_to_group("npcs")
	if mounted:
		horse_model = HorseModelScript.new()
		add_child(horse_model)
	rebuild()


## Пересобрать внешний вид (после смены цвета или имени).
func rebuild() -> void:
	if not is_inside_tree():
		return
	if model:
		model.queue_free()
	if name_label:
		name_label.queue_free()
		name_label = null
	model = RigScript.new()
	add_child(model)
	model.build(body, height, tint if body == "npc" else Color.WHITE, kind != "folk")
	if pose_mode == "sit":
		model.seated = true
		model.position.y = seat_h - model.hip_y + model.sit_h
	if mounted:
		model.mounted = true
		model.position = horse_model.rider_pos(yaw, model.hip_y, model.sit_h)
		horse_model.rider = model
		horse_model.rider_hip = model.hip_y
		horse_model.rider_sit = model.sit_h
	if npc_name != "":
		name_label = Label3D.new()
		name_label.text = npc_name
		name_label.font_size = 48
		name_label.pixel_size = 0.01
		name_label.modulate = Game.GOLD
		name_label.outline_size = 8
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.position.y = 2.6
		add_child(name_label)


func head_height() -> float:
	return height * 0.9 + (model.position.y if model else 0.0)


func _physics_process(delta: float) -> void:
	if dead:
		dead_t += delta
		if dead_t < 5.0 and model:
			model.animate(0.0, delta)
		if town != null and dead_t > 90.0 and Game.wanted == 0 and Game.world.v2(Game.world.player.global_position).distance_to(town["pos"]) > 120.0:
			revive()
		return
	var p = Game.world.player
	var to_p: Vector3 = p.global_position - global_position
	to_p.y = 0.0
	var d := to_p.length()
	# далёкие персонажи думают реже — экономия на телефоне
	if d > 180.0 and not aggro:
		_think -= delta
		if _think > 0.0:
			return
		_think = 0.5
	var k: Dictionary = KINDS[kind]
	var hostile := kind == "bandit" or kind == "leader" or ((kind == "sheriff" or kind == "lawman") and Game.wanted > 0)
	if d > 110.0 and kind != "lawman":
		aggro = false
	var engage: bool = hostile and not p.dead and (aggro or d < (220.0 if kind == "lawman" else 40.0))
	var mv := Vector3.ZERO
	var spd: float = k["spd"]

	if engage:
		aggro = true
		var dir := to_p / maxf(d, 0.01)
		yaw = atan2(-dir.x, -dir.z)
		str_t -= delta
		if str_t <= 0.0:
			strafe = -1.0 if randf() < 0.5 else 1.0
			str_t = randf_range(1.2, 3.0)
		var want := 26.0 if kind == "lawman" else 20.0
		var f := 0.0
		if d > want + 5.0:
			f = 1.0
		elif d < want - 6.0:
			f = -0.8
		var side := Vector3(-dir.z, 0, dir.x)
		mv = dir * f + side * strafe * 0.6
		if kind == "lawman" and f == 0.0:
			spd *= 0.35
		if reload > 0.0:
			reload -= delta
			if reload <= 0.0:
				clip = 6
		else:
			cd -= delta
			var eye := global_position + Vector3(0, head_height(), 0)
			var target: Vector3 = p.global_position + Vector3(0, 1.3 if not p.mounted else 2.3, 0)
			if cd <= 0.0 and d < 70.0 and Game.world.has_los(eye, target):
				_shoot_at(p, target, d, k["dmg"])
				clip -= 1
				var c: Vector2 = k["cd"]
				cd = randf_range(c.x, c.y)
				if clip <= 0:
					reload = 2.2
					if voice == "bandb":
						talk(3, 3.0)
					elif voice == "banda" and randf() < 0.6:
						talk(3, 3.0)
	elif kind == "folk" and pose_mode != "" and (flee <= 0.0 or indoor or pose_mode == "sit"):
		# сидит, стоит у стены или беседует — на месте, лицом куда поставили
		if pose_mode == "chat" and d < 8.0 and not p.dead:
			pass
	elif kind == "folk" and flee > 0.0:
		flee -= delta
		var away := -to_p / maxf(d, 0.01)
		mv = away.rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.003 + home.x) * 0.4)
		yaw = atan2(-mv.x, -mv.z)
		spd = 4.5
	elif kind == "lawman":
		mv = Vector3(-sin(yaw), 0, -cos(yaw))
		spd *= 0.4
	else:
		wt_t -= delta
		if wt_t <= 0.0:
			wt_t = randf_range(2.0, 6.0)
			if town != null:
				wt = Vector3(town["pos"].x + randf_range(-32, 32), 0, town["pos"].y + randf_range(-4, 4))
			else:
				wt = home + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		var tw := wt - global_position
		tw.y = 0.0
		if tw.length() > 1.0:
			mv = tw.normalized()
			yaw = atan2(-mv.x, -mv.z)
			spd *= 0.45

	if Game.world.in_water(global_position):
		spd *= 0.5
	velocity = mv * spd
	var before := global_position
	move_and_slide()
	if not Game.world.ground_move(self, before):
		wt_t = 0.0 # упёрся в скалу — выбрать новую цель
		strafe = -strafe
	_voice_update(delta, engage, d, p)
	var real_speed := velocity.length()
	model.rotation.y = lerp_angle(model.rotation.y, yaw, minf(1.0, delta * 10.0))
	model.aiming = engage
	# дальние персонажи обновляют анимацию реже — экономия на телефоне
	_anim_acc += delta
	var step := 0.0 if d < 45.0 else (0.06 if d < 110.0 else 0.2)
	if _anim_acc >= step:
		model.animate(real_speed, _anim_acc)
		_anim_acc = 0.0
	if horse_model:
		horse_model.rotation.y = model.rotation.y
		if not dead:
			model.position = horse_model.rider_pos(model.rotation.y, model.hip_y, model.sit_h)
		horse_model.animate(real_speed, delta)


## Сказать фразу n своим голосом (с паузой между фразами одного персонажа).
func talk(n: int, cdv := 5.0) -> bool:
	if voice == "" or dead:
		return false
	return Game.vo(voice, n, global_position + Vector3(0, head_height(), 0), get_instance_id(), cdv)


## Реплики по ситуации: заметил героя, перестрелка, приветствие, паника.
func _voice_update(delta: float, engage: bool, d: float, p) -> void:
	_chat_t -= delta
	if d > 45.0:
		_was_engaged = engage
		return
	if engage and not _was_engaged:
		match voice:
			"banda": talk(1 if randf() < 0.6 else 2)
			"bandb": talk(1)
			"sheriff": talk(3)
			"posse": talk(1 if randf() < 0.6 else 3)
		_chat_t = randf_range(5.0, 9.0)
	elif engage and _chat_t <= 0.0:
		_chat_t = randf_range(7.0, 14.0)
		match voice:
			"banda": talk(4 if randf() < 0.5 else 3)
			"bandb": talk(2)
			"sheriff": talk(4)
			"posse": talk(2 if randf() < 0.5 else 3)
	elif not engage and not p.dead and _chat_t <= 0.0:
		if kind == "folk":
			var fleeing := flee > 0.0
			var pspd: float = Vector2(p.move_vel.x, p.move_vel.z).length()
			if fleeing and not _was_fleeing:
				talk(5 if randf() < 0.6 else 4, 3.0)
				_chat_t = randf_range(4.0, 7.0)
			elif not fleeing and p.mounted and pspd > 6.0 and d < 4.5:
				if talk(6, 8.0):
					_chat_t = 8.0
			elif not fleeing and p.model.aiming and d < 12.0:
				if talk(4, 6.0):
					_chat_t = 6.0
			elif not fleeing and d < 5.0 and Game.wanted == 0:
				if talk([1, 1, 2, 3].pick_random(), 40.0):
					_chat_t = 12.0
			_was_fleeing = fleeing
		elif kind == "sheriff" and d < 6.0 and Game.wanted == 0:
			if talk(1 if randf() < 0.5 else 2, 45.0):
				_chat_t = 15.0
	_was_engaged = engage


func _shoot_at(p, target: Vector3, d: float, dmg: float) -> void:
	var chance := clampf(0.8 - d / 90.0, 0.15, 0.8)
	if p.mounted and p.move_vel.length() > 8.0:
		chance *= 0.55
	var from: Vector3 = model.gun_pos()
	var end := target
	if randf() < chance:
		p.hurt(dmg)
	else:
		end = target + Vector3(randf_range(-1.5, 1.5), randf_range(-0.8, 1.2), randf_range(-1.5, 1.5)) + (target - from).normalized() * 6.0
		# пуля просвистела рядом с героем
		if randf() < 0.75:
			Game.play_at("whiz", target + (target - from).normalized() * 0.5, -3.0, randf_range(0.85, 1.2), 4.0)
		if absf(end.y - Game.world.ground(end.x, end.z)) < 1.5:
			Game.world.fx.dust(Vector3(end.x, Game.world.ground(end.x, end.z), end.z))
	model.shoot_anim()
	Game.world.fx.tracer(from, end)
	Game.world.fx.muzzle(from)
	if d < 60.0:
		Game.world.fx.smoke(from, end - from)
	Game.play_at("shot" if d < 55.0 else "shot_far", from, 0.0, randf_range(0.85, 1.05), 18.0)


func take_hit(dmg: float, by_player: bool) -> void:
	if dead:
		return
	hp -= dmg
	aggro = true
	Game.world.fx.blood(global_position + Vector3(0, 1.3, 0))
	if hp > 0.0 and kind != "folk":
		Game.play_at("hurt", global_position + Vector3(0, 1.6, 0), -4.0, randf_range(0.85, 1.15), 10.0)
		if randf() < 0.45:
			match voice:
				"banda": talk(5, 4.0)
				"bandb": talk(4, 4.0)
	if by_player and kind in ["folk", "sheriff", "lawman"]:
		if Game.wanted == 0:
			Game.wanted = 1
			Game.say("Вы нарушили закон! Вас разыскивают.", Game.BAD)
		Game.world.alert_town(global_position)
	if by_player and camp != null:
		for n in Game.world.camp_members(camp):
			n.aggro = true
	if hp <= 0.0:
		_die(by_player)


func _die(by_player: bool) -> void:
	dead = true
	dead_t = 0.0
	collision_layer = 0
	collision_mask = 0
	if mounted:
		model.mounted = false
		horse_model.rider = null
		model.position = Vector3(1.4, 0, 0)
	model.set_dead(true)
	Game.play_at("death", global_position + Vector3(0, 1.4, 0), -2.0, randf_range(0.9, 1.1), 10.0)
	var fall_at := global_position
	get_tree().create_timer(0.7 if not mounted else 1.0).timeout.connect(func():
		Game.play_at("bodyfall", fall_at, -3.0, randf_range(0.9, 1.1), 8.0)
		Game.world.fx.dust(fall_at + Vector3(0, 0.2, 0))
		var gp := fall_at + (Vector3(1.4, 0, 0) if mounted else Vector3.ZERO)
		gp.y = Game.world.ground(gp.x, gp.z)
		Game.world.fx.blood_pool(gp))
	if name_label:
		name_label.visible = false
	if by_player:
		if kind == "bandit" or kind == "leader":
			Game.honor += 3
			Game.kills += 1
			Game.world.drop_loot(global_position)
			if randf() < 0.3:
				get_tree().create_timer(1.0).timeout.connect(func(): Game.vo("hero", 3, null, "hero", 25.0, -3.0))
		else:
			Game.wanted = mini(5, Game.wanted + 1)
			Game.honor -= 10
			Game.say("Убийство невиновного. Розыск растёт!", Game.BAD)
		if kind == "leader" and Game.bounty != null and not Game.bounty["done"]:
			Game.bounty["done"] = true
			Game.say("%s мёртв. Возвращайтесь к шерифу за наградой." % npc_name, Game.GOLD)
			Game.play("bounty")
			get_tree().create_timer(1.6).timeout.connect(func(): Game.vo("hero", 4, null, "hero", 0.0, -2.0))
	if camp != null:
		Game.world.check_camp(camp)


func revive() -> void:
	dead = false
	hp = max_hp
	position = home
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	aggro = false
	model.set_dead(false)
	if mounted:
		model.mounted = true
		horse_model.rider = model
