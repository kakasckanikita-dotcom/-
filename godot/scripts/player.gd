extends CharacterBody2D
## Герой, Эли Брэнсон: ходьба и езда верхом, стрельба, перезарядка,
## «Глаз ястреба» (замедление времени и залп по отмеченным целям).

const BODY := Color("5a4632")
const HAT := Color("4a3220")

var horse: CharacterBody2D
var ang := 0.0
var horse_ang := 0.0
var mounted := false
var dead := false
var dead_t := 0.0
var shoot_cd := 0.0
var reload_t := 0.0
var last_hit := -99.0
var clock := 0.0
var focus_on := false
var marks: Array = []
var exec_q: Array = []
var exec_t := 0.0
var move_vel := Vector2.ZERO
var shake := 0.0
var flash := 0.0
var last_town = null
var hint := ""
var cam: Camera2D
var lantern: PointLight2D
var _shape: CircleShape2D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	_shape = CircleShape2D.new()
	_shape.radius = 12.0
	cs.shape = _shape
	add_child(cs)
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	cam.make_current()
	lantern = PointLight2D.new()
	lantern.texture = Game.light_texture()
	lantern.texture_scale = 2.6
	lantern.color = Color(1.0, 0.85, 0.6)
	lantern.energy = 0.0
	add_child(lantern)
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	clock += real
	_update_focus(real)
	var pfac := 0.6 if focus_on else 1.0
	flash = maxf(0.0, flash - real)
	shake = maxf(0.0, shake - real * 30.0)
	var vp := get_viewport()
	var lead := (vp.get_mouse_position() - vp.get_visible_rect().size / 2.0) * 0.12
	cam.offset = lead + Vector2(randf_range(-shake, shake), randf_range(-shake, shake))

	if dead:
		dead_t += real
		if dead_t > 3.5:
			Game.world.respawn_player()
		queue_redraw()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprint := mounted and Input.is_action_pressed("sprint") and Game.stam > 0.0 and input != Vector2.ZERO
	var sp := 150.0
	if mounted:
		sp = 440.0 if sprint else 290.0
	if Game.world.in_water(global_position):
		sp *= 0.45
	if sprint:
		Game.stam = maxf(0.0, Game.stam - real * pfac * 22.0)
	else:
		Game.stam = minf(100.0, Game.stam + real * 12.0)
	var k := minf(1.0, real * pfac * (4.0 if mounted else 10.0))
	move_vel = move_vel.lerp(input * sp, k)
	# move_and_slide использует замедленную дельту; компенсируем, чтобы
	# в «Глазе ястреба» герой двигался на 60 % скорости, а не на 25 %
	var tf := pfac / maxf(Engine.time_scale, 0.01)
	velocity = move_vel * tf
	move_and_slide()
	move_vel = velocity / tf

	ang = (get_global_mouse_position() - global_position).angle()
	if mounted and move_vel.length() > 20.0:
		horse_ang = move_vel.angle()
	shoot_cd -= real * pfac
	if reload_t > 0.0:
		reload_t -= real * pfac
		if reload_t <= 0.0:
			var n := mini(6 - Game.clip, Game.ammo)
			Game.clip += n
			Game.ammo -= n
	if clock - last_hit > 5.0 and Game.hp < 100.0:
		Game.hp = minf(100.0, Game.hp + real * 3.0)

	for l in get_tree().get_nodes_in_group("loot"):
		if l.global_position.distance_to(global_position) < 30.0:
			Game.money += l.money
			Game.ammo += l.ammo
			Game.say("Обыскали тело: $%d, патроны +%d" % [l.money, l.ammo])
			Game.play("coin", -6.0)
			l.queue_free()

	var town = Game.world.town_at(global_position)
	if town != null and town != last_town:
		Game.say("— %s —" % town["name"], Game.GOLD)
	last_town = town

	hint = ""
	var b = Game.world.near_door(global_position)
	if b:
		hint = "[E] " + b.NAMES[b.type]
	elif not mounted and global_position.distance_to(horse.global_position) < 70.0:
		hint = "[E] Сесть на коня"
	queue_redraw()


func _update_focus(real: float) -> void:
	var want := Input.is_action_pressed("focus") and not dead and Game.focus > 0.0 and exec_q.is_empty()
	if want:
		if not focus_on:
			focus_on = true
			marks.clear()
			Engine.time_scale = 0.25
			Game.play("focus", -4.0)
		Game.focus = maxf(0.0, Game.focus - real * 16.0)
	elif focus_on:
		cancel_focus(true)
	if not focus_on and exec_q.is_empty():
		Game.focus = minf(100.0, Game.focus + real * 1.2)
	if not exec_q.is_empty():
		exec_t -= real
		if exec_t <= 0.0:
			exec_t = 0.11
			var t = exec_q.pop_front()
			if is_instance_valid(t) and not t.dead and Game.clip > 0 and not dead:
				Game.clip -= 1
				ang = (t.global_position - global_position).angle()
				Game.world.fx.tracer(global_position, t.global_position)
				Game.play("shot", -2.0, randf_range(0.9, 1.1))
				shake = 4.0
				t.take_hit(150.0, true)
				Game.world.alert_town(global_position)
			if exec_q.is_empty() and Game.clip == 0:
				start_reload()


## fire — выстрелить по отмеченным целям после выхода из замедления.
func cancel_focus(fire := false) -> void:
	focus_on = false
	Engine.time_scale = 1.0
	exec_q = marks.duplicate() if fire else []
	marks.clear()
	exec_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event.is_action_pressed("shoot"):
		if focus_on:
			_mark_target()
		else:
			shoot()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("whistle") and not mounted:
		horse.called = true
		Game.play("whistle", -4.0)
		Game.say("Вы свистнули. %s скачет к вам." % horse.horse_name)
	elif event.is_action_pressed("medkit") and Game.medkits > 0 and Game.hp < 100.0:
		Game.medkits -= 1
		Game.hp = minf(100.0, Game.hp + 60.0)
		Game.say("Аптечка: +60 здоровья", Game.GOOD)
	elif event.is_action_pressed("tonic") and Game.tonics > 0 and Game.focus < 100.0:
		Game.tonics -= 1
		Game.focus = 100.0
		Game.say("Тоник: концентрация восстановлена", Game.GOLD)


func _mark_target() -> void:
	if marks.size() >= Game.clip:
		return
	var m := get_global_mouse_position()
	var best = null
	var bd := 30.0
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.dead:
			continue
		var d: float = n.global_position.distance_to(m)
		if d < bd:
			bd = d
			best = n
	if best:
		marks.append(best)
		Game.play("mark", -10.0)


func shoot() -> void:
	if reload_t > 0.0 or shoot_cd > 0.0:
		return
	if Game.clip <= 0:
		Game.play("click", -6.0)
		start_reload()
		return
	Game.clip -= 1
	shoot_cd = 0.28
	var spread := (0.06 if mounted else 0.03) + move_vel.length() / 6000.0
	Game.world.fire(global_position, ang + randf_range(-spread, spread), true, 34.0, get_rid())
	Game.play("shot", -2.0, randf_range(0.9, 1.1))
	shake = 4.0
	Game.world.alert_town(global_position)
	if Game.clip == 0:
		get_tree().create_timer(0.3).timeout.connect(start_reload)


func start_reload() -> void:
	if reload_t > 0.0 or Game.clip >= 6 or Game.ammo <= 0 or dead:
		return
	reload_t = 1.5
	Game.play("reload", -6.0)


func interact() -> void:
	var b = Game.world.near_door(global_position)
	if b:
		if mounted:
			dismount()
		cancel_focus()
		Game.world.hud.open_building(b)
	elif mounted:
		dismount()
	elif global_position.distance_to(horse.global_position) < 70.0:
		mount()


func mount() -> void:
	mounted = true
	horse.called = false
	horse.visible = false
	horse_ang = horse.ang
	global_position = horse.global_position
	_shape.radius = 16.0
	Game.play("horse", -6.0)


func dismount() -> void:
	mounted = false
	horse.global_position = global_position
	horse.ang = horse_ang
	horse.visible = true
	_shape.radius = 12.0
	velocity = Vector2.from_angle(horse_ang + PI / 2.0) * 30.0 / get_physics_process_delta_time()
	move_and_slide()
	move_vel = Vector2.ZERO
	velocity = Vector2.ZERO


func take_hit(dmg: float, _by_player: bool) -> void:
	hurt(dmg)


func hurt(dmg: float) -> void:
	if dead:
		return
	Game.hp -= dmg
	last_hit = clock
	flash = 0.35
	shake = 6.0
	Game.world.fx.blood(global_position)
	Game.play("hurt", -8.0)
	if Game.hp <= 0.0:
		Game.hp = 0.0
		if mounted:
			dismount()
		cancel_focus()
		dead = true
		dead_t = 0.0
		Game.play("death", -4.0)


func revive(at: Vector2) -> void:
	dead = false
	global_position = at
	move_vel = Vector2.ZERO
	cam.reset_smoothing()


func _draw() -> void:
	if dead:
		Gfx.corpse(self, Vector2.ZERO, ang, BODY, HAT)
		return
	if mounted:
		Gfx.horse(self, Vector2.ZERO, horse_ang, Color("6b3e22"), false, clock)
	Gfx.man(self, Vector2.ZERO, ang, BODY, HAT)
	if hint != "":
		var w := Gfx.text_width(hint, 14) + 16.0
		draw_rect(Rect2(-w / 2.0, -50, w, 22), Color(0.12, 0.07, 0.03, 0.8))
		Gfx.text(self, Vector2(0, -34), hint, 14, Game.CREAM)
