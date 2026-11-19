extends CharacterBody2D
## Любой персонаж, кроме героя: бандит, главарь, горожанин, шериф или конный
## помощник шерифа. Поведение зависит от вида и от розыска героя.

const KINDS := {
	"bandit": {"hp": 100.0, "body": Color("7a2a1e"), "hat": Color("2b1d14"), "spd": 130.0, "dmg": 9.0, "cd": Vector2(1.0, 1.9)},
	"leader": {"hp": 280.0, "body": Color("2a2a2a"), "hat": Color("111111"), "spd": 120.0, "dmg": 14.0, "cd": Vector2(0.6, 1.1)},
	"folk": {"hp": 60.0, "body": Color("5e7aa0"), "hat": Color("9a7a50"), "spd": 70.0, "dmg": 0.0, "cd": Vector2(1.0, 1.0)},
	"sheriff": {"hp": 150.0, "body": Color("3c3a35"), "hat": Color("c8b07a"), "spd": 140.0, "dmg": 12.0, "cd": Vector2(0.8, 1.4)},
	"lawman": {"hp": 130.0, "body": Color("4b4a42"), "hat": Color("6b5a3a"), "spd": 280.0, "dmg": 11.0, "cd": Vector2(0.9, 1.6)},
}

var kind := "bandit"
var hp := 100.0
var max_hp := 100.0
var ang := 0.0
var cd := 1.0
var clip := 6
var reload := 0.0
var home := Vector2.ZERO
var wt := Vector2.ZERO
var wt_t := 0.0
var strafe := 1.0
var str_t := 0.0
var aggro := false
var dead := false
var dead_t := 0.0
var flee := 0.0
var body_col := Color.WHITE
var hat_col := Color.BLACK
var mounted := false
var town = null
var camp = null
var npc_name := ""
var t := 0.0


func setup(k: String, pos: Vector2) -> void:
	kind = k
	var d: Dictionary = KINDS[k]
	hp = d["hp"]
	max_hp = hp
	body_col = d["body"]
	hat_col = d["hat"]
	mounted = k == "lawman"
	position = pos
	home = pos
	wt = pos
	ang = randf() * TAU
	cd = randf_range(0.5, 1.5)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	motion_mode = MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var s := CircleShape2D.new()
	s.radius = 16.0 if mounted else 12.0
	cs.shape = s
	add_child(cs)
	add_to_group("npcs")


func _physics_process(delta: float) -> void:
	t += delta
	if dead:
		dead_t += delta
		if town != null and dead_t > 90.0 and Game.wanted == 0 and Game.world.player.global_position.distance_to(town["pos"]) > 900.0:
			revive()
		return
	var p = Game.world.player
	var to_p: Vector2 = p.global_position - global_position
	var d := to_p.length()
	var k: Dictionary = KINDS[kind]
	var hostile := kind == "bandit" or kind == "leader" or ((kind == "sheriff" or kind == "lawman") and Game.wanted > 0)
	if d > 1100.0 and kind != "lawman":
		aggro = false
	var engage: bool = hostile and not p.dead and (aggro or d < (2000.0 if kind == "lawman" else 420.0))
	var mv := Vector2.ZERO
	var spd: float = k["spd"]

	if engage:
		aggro = true
		ang = to_p.angle()
		str_t -= delta
		if str_t <= 0.0:
			strafe = -1.0 if randf() < 0.5 else 1.0
			str_t = randf_range(1.2, 3.0)
		var want := 260.0 if kind == "lawman" else 210.0
		var f := 0.0
		if d > want + 50.0:
			f = 1.0
		elif d < want - 60.0:
			f = -0.8
		mv = Vector2.from_angle(ang) * f + Vector2.from_angle(ang + PI / 2.0) * strafe * 0.6
		if reload > 0.0:
			reload -= delta
			if reload <= 0.0:
				clip = 6
		else:
			cd -= delta
			if cd <= 0.0 and d < 650.0 and Game.world.has_los(global_position, p.global_position):
				var sp := 0.07
				if p.mounted:
					sp += p.move_vel.length() / 3500.0
				Game.world.fire(global_position, ang + randf_range(-sp, sp), false, k["dmg"], get_rid())
				Game.play("shot", clampf(-8.0 - d / 60.0, -30.0, -6.0), randf_range(0.8, 1.0))
				clip -= 1
				var c: Vector2 = k["cd"]
				cd = randf_range(c.x, c.y)
				if clip <= 0:
					reload = 2.2
	elif kind == "folk" and flee > 0.0:
		flee -= delta
		ang = (-to_p).angle() + sin(t * 3.0 + home.x) * 0.4
		mv = Vector2.from_angle(ang)
		spd = 170.0
	elif kind == "lawman":
		mv = Vector2.from_angle(ang)
		spd *= 0.4
	else:
		wt_t -= delta
		if wt_t <= 0.0:
			wt_t = randf_range(2.0, 6.0)
			if town != null:
				wt = town["pos"] + Vector2(randf_range(-320, 320), randf_range(-45, 45))
			else:
				wt = home + Vector2(randf_range(-90, 90), randf_range(-90, 90))
		if global_position.distance_to(wt) > 10.0:
			ang = (wt - global_position).angle()
			mv = Vector2.from_angle(ang)
			spd *= 0.4

	if Game.world.in_water(global_position):
		spd *= 0.45
	velocity = mv * spd
	move_and_slide()
	queue_redraw()


func take_hit(dmg: float, by_player: bool) -> void:
	if dead:
		return
	hp -= dmg
	aggro = true
	Game.world.fx.blood(global_position)
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
	queue_redraw()


func _die(by_player: bool) -> void:
	dead = true
	dead_t = 0.0
	collision_layer = 0
	collision_mask = 0
	z_index = -3
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
	z_index = 0
	aggro = false
	queue_redraw()


func _draw() -> void:
	if dead:
		Gfx.corpse(self, Vector2.ZERO, ang, body_col, hat_col)
		return
	if mounted:
		Gfx.horse(self, Vector2.ZERO, ang, Color("4a3020"), false, t)
	Gfx.man(self, Vector2.ZERO, ang, body_col, hat_col, kind != "folk", kind == "sheriff" or kind == "lawman", kind == "bandit")
	if kind == "leader":
		Gfx.text(self, Vector2(0, -26), npc_name, 13, Game.GOLD)
	if hp < max_hp:
		draw_rect(Rect2(-14, -20, 28, 4), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-14, -20, 28 * hp / max_hp, 4), Color("cc3333"))
