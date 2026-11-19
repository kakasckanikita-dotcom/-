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
	model.build("npc", height, tint, kind != "folk")
	if mounted:
		model.mounted = true
		model.position = horse_model.rider_pos(yaw, model.hip_y)
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
	move_and_slide()
	global_position.y = 0.0
	var real_speed := velocity.length()
	model.rotation.y = lerp_angle(model.rotation.y, yaw, minf(1.0, delta * 10.0))
	model.aiming = engage
	model.animate(real_speed, delta)
	if horse_model:
		horse_model.rotation.y = model.rotation.y
		if not dead:
			model.position = horse_model.rider_pos(model.rotation.y, model.hip_y)
		horse_model.animate(real_speed, delta)


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
	Game.world.fx.tracer(from, end)
	Game.world.fx.muzzle(from)
	Game.play("shot", clampf(-6.0 - d / 4.0, -30.0, -6.0), randf_range(0.8, 1.0))


func take_hit(dmg: float, by_player: bool) -> void:
	if dead:
		return
	hp -= dmg
	aggro = true
	Game.world.fx.blood(global_position + Vector3(0, 1.3, 0))
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
		model.position = Vector3(1.4, 0, 0)
	model.set_dead(true)
	if name_label:
		name_label.visible = false
	if by_player:
		if kind == "bandit" or kind == "leader":
			Game.honor += 3
			Game.kills += 1
			Game.world.drop_loot(global_position)
		else:
			Game.wanted = mini(5, Game.wanted + 1)
			Game.honor -= 10
			Game.say("Убийство невиновного. Розыск растёт!", Game.BAD)
		if kind == "leader" and Game.bounty != null and not Game.bounty["done"]:
			Game.bounty["done"] = true
			Game.say("%s мёртв. Возвращайтесь к шерифу за наградой." % npc_name, Game.GOLD)
			Game.play("bounty")
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
