extends CharacterBody3D
## Герой, Эли Брэнсон. Камера от третьего лица, ходьба и езда верхом,
## стрельба через прицел, «Глаз ястреба» (замедление и залп по отмеченным).
## На ПК — мышь и клавиатура, на телефоне — сенсорные кнопки (touch.gd).

const RigScript := preload("res://scripts/rig.gd")
const HorseModelScript := preload("res://scripts/horse_model.gd")
const BODY := Color("5a4632")
const HAT := Color("4a3220")

var horse: CharacterBody3D
var model: Node3D
var horse_model: Node3D
var yaw := 0.0 # камера
var pitch := -0.25
var face_yaw := 0.0 # куда смотрит герой
var horse_yaw := 0.0
var aim_t := 0.0
var recoil := 0.0 # отдача: камера подскакивает и плавно возвращается
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
var move_vel := Vector3.ZERO
var shake := 0.0
var flash := 0.0
var last_town = null
var hint := ""
var hoof_t := 0.0
var mount_dir := 0 # 1 — садится на коня, −1 — слезает
var mount_t := 0.0
const MOUNT_TIME := 1.3
const DISMOUNT_TIME := 0.9
var rig: Node3D
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var lantern: OmniLight3D
var _col: CollisionShape3D
var _shape_walk: CapsuleShape3D
var _shape_ride: CylinderShape3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = MOTION_MODE_FLOATING
	_shape_walk = CapsuleShape3D.new()
	_shape_walk.radius = 0.35
	_shape_walk.height = 1.9
	_shape_ride = CylinderShape3D.new()
	_shape_ride.radius = 0.9
	_shape_ride.height = 3.0
	_col = CollisionShape3D.new()
	_col.shape = _shape_walk
	_col.position.y = 0.95
	add_child(_col)
	model = RigScript.new()
	add_child(model)
	model.build("hero", 1.82)
	horse_model = HorseModelScript.new()
	add_child(horse_model)
	horse_model.visible = false
	rig = Node3D.new()
	rig.top_level = true
	add_child(rig)
	pivot = Node3D.new()
	pivot.position.y = 1.75
	rig.add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 4.2
	arm.collision_mask = 1 | 16
	arm.margin = 0.3
	arm.position = Vector3(0.6, 0, 0)
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 1600.0
	arm.add_child(cam)
	cam.current = true
	lantern = OmniLight3D.new()
	lantern.position = Vector3(0, 2.0, 0)
	lantern.omni_range = 16.0
	lantern.light_color = Color(1.0, 0.82, 0.55)
	lantern.light_energy = 0.0
	add_child(lantern)
	add_to_group("player")
	snap_camera()


func snap_camera() -> void:
	if rig:
		rig.global_position = global_position


func _physics_process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	clock += real
	_update_focus(real)
	var pfac := 0.6 if focus_on else 1.0
	yaw -= Game.touch_look.x * 0.006
	pitch -= Game.touch_look.y * 0.005
	Game.touch_look = Vector2.ZERO
	pitch = clampf(pitch, -1.1, 0.45)
	flash = maxf(0.0, flash - real)
	shake = maxf(0.0, shake - real * 30.0)
	aim_t -= real

	if dead:
		dead_t += real
		model.animate(0.0, real)
		if dead_t > 4.0:
			Game.world.respawn_player()
		_update_camera(real)
		return

	if mount_dir != 0:
		global_position.y = Game.world.ground(global_position.x, global_position.z)
		_update_mounting(real)
		_update_camera(real)
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Game.touch_mode and Game.touch_move.length() > 0.05:
		input = Game.touch_move
	var dir := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	var sprint := mounted and Input.is_action_pressed("sprint") and Game.stam > 0.0 and input.length() > 0.1
	var sp := 4.6
	if mounted:
		sp = 18.0 if sprint else 11.0
	if Game.world.in_water(global_position):
		sp *= 0.5
	if sprint:
		Game.stam = maxf(0.0, Game.stam - real * pfac * 20.0)
	else:
		Game.stam = minf(100.0, Game.stam + real * 12.0)
	var k := minf(1.0, real * pfac * (3.0 if mounted else 10.0))
	move_vel = move_vel.lerp(dir * sp, k)
	# move_and_slide использует замедленную дельту; компенсируем, чтобы
	# в «Глазе ястреба» герой двигался на 60 % скорости, а не на 25 %
	var tf := pfac / maxf(Engine.time_scale, 0.01)
	velocity = move_vel * tf
	var before := global_position
	move_and_slide()
	move_vel = velocity / tf
	if not Game.world.ground_move(self, before):
		move_vel = Vector3.ZERO

	var speed := Vector2(move_vel.x, move_vel.z).length()
	if speed > 0.6:
		var move_yaw := atan2(-move_vel.x, -move_vel.z)
		horse_yaw = lerp_angle(horse_yaw, move_yaw, minf(1.0, real * 5.0))
		if aim_t <= 0.0 and not focus_on:
			face_yaw = lerp_angle(face_yaw, horse_yaw if mounted else move_yaw, minf(1.0, real * 12.0))
	if aim_t > 0.0 or focus_on:
		face_yaw = lerp_angle(face_yaw, yaw, minf(1.0, real * 20.0))
	model.rotation.y = face_yaw
	model.aiming = aim_t > 0.0 or focus_on
	model.animate(speed, real * pfac)
	if mounted:
		horse_model.rotation.y = horse_yaw
		# конь наклоняется по склону
		var fwd := Vector3(-sin(horse_yaw), 0, -cos(horse_yaw))
		var gp := global_position
		var pitch := atan2(Game.world.ground(gp.x + fwd.x * 1.1, gp.z + fwd.z * 1.1) - Game.world.ground(gp.x - fwd.x * 1.1, gp.z - fwd.z * 1.1), 2.2)
		horse_model.rotation.x = lerpf(horse_model.rotation.x, pitch, minf(1.0, real * 8.0))
		model.position = horse_model.rider_pos(horse_yaw, model.hip_y, model.sit_h)
		horse_model.animate(speed, real * pfac)
		# дальше конь сам держит всадника в седле после своей анимации
		horse_model.rider = model
		horse_model.rider_hip = model.hip_y
		horse_model.rider_sit = model.sit_h

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
		if l.global_position.distance_to(global_position) < 2.0:
			Game.money += l.money
			Game.ammo += l.ammo
			if l.title != "":
				Game.say("%s: $%d" % [l.title, l.money], Game.GOOD)
			else:
				Game.say("Обыскали тело: $%d, патроны +%d" % [l.money, l.ammo])
			Game.play("coin", -6.0)
			l.queue_free()

	var town = Game.world.town_at(global_position)
	if town != null and town != last_town:
		Game.say("— %s —" % town["name"], Game.GOLD)
	last_town = town

	hint = ""
	var b = Game.world.near_door(global_position)
	if Game.world.interior.near_bartender(global_position):
		hint = "Поговорить с барменом"
	elif Game.world.interior.near_exit(global_position):
		hint = "Выйти на улицу"
	elif b:
		hint = "Войти в салун" if b["type"] == "saloon" else Game.world.NAMES[b["type"]]
	elif not mounted and global_position.distance_to(horse.global_position) < 3.5:
		hint = "Сесть на коня"
	_update_camera(real)


func _update_camera(real: float) -> void:
	rig.global_position = rig.global_position.lerp(global_position, minf(1.0, real * 12.0))
	rig.rotation = Vector3(0, yaw, 0)
	recoil = move_toward(recoil, 0.0, real * (0.35 + recoil * 4.0))
	pivot.rotation.x = pitch + recoil
	var want_len := 6.0 if mounted else 4.2
	var want_h := 2.7 if mounted else 1.75
	if focus_on:
		want_len *= 0.75
	arm.spring_length = lerpf(arm.spring_length, want_len, minf(1.0, real * 4.0))
	pivot.position.y = lerpf(pivot.position.y, want_h, minf(1.0, real * 4.0))
	cam.h_offset = randf_range(-shake, shake) * 0.01
	cam.v_offset = randf_range(-shake, shake) * 0.01


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
				var tp: Vector3 = t.global_position + Vector3(0, t.head_height() - 0.3, 0)
				var to := tp - global_position
				face_yaw = atan2(-to.x, -to.z)
				model.rotation.y = face_yaw
				aim_t = 1.0
				Game.world.fx.tracer(model.gun_pos(), tp)
				Game.world.fx.muzzle(model.gun_pos())
				Game.world.fx.smoke(model.gun_pos(), tp - model.gun_pos())
				Game.play("shot", -2.0, randf_range(0.9, 1.1))
				shake = 4.0
				model.shoot_anim()
				t.take_hit(150.0, true)
				Game.world.hud.hit(true)
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
	if Game.touch_mode and event is InputEventMouse:
		return # на телефоне касания обрабатывает touch.gd
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0032
		pitch -= event.relative.y * 0.0032
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if dead:
		return
	if event.is_action_pressed("shoot"):
		if focus_on:
			mark_at_screen(get_viewport().get_visible_rect().size / 2.0)
		else:
			shoot()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("whistle") and not mounted and not Game.world.interior.inside:
		horse.called = true
		Game.play("whistle", -4.0)
		get_tree().create_timer(0.9).timeout.connect(func(): Game.vo("hero", 1, null, "hero_call", 12.0, -2.0))
		Game.say("Вы свистнули. %s скачет к вам." % horse.horse_name)
	elif event.is_action_pressed("medkit") and Game.medkits > 0 and Game.hp < 100.0:
		Game.medkits -= 1
		Game.hp = minf(100.0, Game.hp + 60.0)
		Game.say("Аптечка: +60 здоровья", Game.GOOD)
	elif event.is_action_pressed("tonic") and Game.tonics > 0 and Game.focus < 100.0:
		Game.tonics -= 1
		Game.focus = 100.0
		Game.say("Тоник: концентрация восстановлена", Game.GOLD)


## Отметить цель «Глаза ястреба» ближе всего к точке экрана.
func mark_at_screen(sp: Vector2) -> void:
	if marks.size() >= Game.clip:
		return
	var best = null
	var bd := 70.0
	for n in get_tree().get_nodes_in_group("npcs") + get_tree().get_nodes_in_group("animals"):
		if n.dead or n.global_position.distance_to(global_position) > 120.0:
			continue
		var chest: Vector3 = n.global_position + Vector3(0, n.head_height() - 0.3, 0)
		if cam.is_position_behind(chest):
			continue
		var d := cam.unproject_position(chest).distance_to(sp)
		if d < bd and Game.world.has_los(cam.global_position, chest):
			bd = d
			best = n
	if best:
		marks.append(best)
		Game.play("mark", -10.0)


## Есть ли цель под прицелом (для красного перекрестия).
func target_under_crosshair():
	var from := cam.global_position
	var hit: Dictionary = Game.world.ray(from, from - cam.global_basis.z * 120.0, 1 | 4 | 16, [get_rid()])
	if not hit.is_empty() and hit["collider"].has_method("take_hit"):
		return hit["collider"]
	return null


func shoot() -> void:
	if reload_t > 0.0 or shoot_cd > 0.0 or mount_dir != 0:
		return
	if Game.clip <= 0:
		Game.play("click", -6.0)
		start_reload()
		return
	Game.clip -= 1
	shoot_cd = 0.28
	aim_t = 1.6
	face_yaw = yaw
	model.rotation.y = yaw
	model.aiming = true
	model.animate(0.0, 0.0)
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var spread := (0.012 if mounted else 0.005) + move_vel.length() / 1500.0
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread)).rotated(cam.global_basis.x, randf_range(-spread, spread) * 0.6)
	if Game.touch_mode:
		dir = _aim_assist(from, dir)
	var to := from + dir * 200.0
	var hit: Dictionary = Game.world.ray(from, to, 1 | 4 | 16, [get_rid(), horse.get_rid()])
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var c = hit["collider"]
		if c.has_method("take_hit"):
			var dmg := 34.0
			if end.y - c.global_position.y > c.head_height() - 0.15:
				dmg *= 3.0
				if not c.dead and c.hp <= dmg:
					Game.say("Точно в голову!", Game.GOLD)
			c.take_hit(dmg, true)
			Game.world.hud.hit(c.dead)
		elif Game.world.in_water(end):
			Game.world.fx.splash(Vector3(end.x, -0.45, end.z), true)
			Game.play_at("splash", end, -6.0, randf_range(1.1, 1.4), 8.0)
		elif c is CollisionObject3D and c.collision_layer & 16:
			Game.world.fx.dust(end)
			Game.world.fx.bullet_hole(end, hit["normal"])
			if randf() < 0.2:
				Game.world.fx.sparks(end)
			Game.play_at("impact", end, -4.0, randf_range(0.9, 1.15), 8.0)
		else:
			Game.world.fx.sparks(end)
			Game.world.fx.dust(end)
			Game.play_at("ricochet" if randf() < 0.35 else "impact", end, -4.0, randf_range(0.9, 1.15), 8.0)
	var gp: Vector3 = model.gun_pos()
	Game.world.fx.tracer(gp, end)
	Game.world.fx.muzzle(gp)
	Game.world.fx.smoke(gp, end - gp)
	Game.play("shot", -2.0, randf_range(0.9, 1.1))
	model.shoot_anim()
	shake = 3.0
	recoil = minf(recoil + 0.05, 0.12)
	Game.world.alert_town(global_position)
	Game.world.scare_animals(global_position, 70.0)
	if Game.clip == 0:
		get_tree().create_timer(0.3).timeout.connect(start_reload)


## Помощь в прицеливании на телефоне: доводка к ближайшей цели в узком конусе.
func _aim_assist(from: Vector3, dir: Vector3) -> Vector3:
	var best_dir := dir
	var best := 0.1
	for n in get_tree().get_nodes_in_group("npcs") + get_tree().get_nodes_in_group("animals"):
		var nk = n.get("kind")
		if n.dead or nk == "folk" or (nk == "sheriff" and Game.wanted == 0) or n.get("species") == "cow":
			continue
		var chest: Vector3 = n.global_position + Vector3(0, n.head_height() - 0.4, 0)
		var to := chest - from
		if to.length() > 90.0:
			continue
		var ang := dir.angle_to(to.normalized())
		if ang < best:
			best = ang
			best_dir = to.normalized()
	return best_dir


func start_reload() -> void:
	if reload_t > 0.0 or Game.clip >= 6 or Game.ammo <= 0 or dead:
		return
	reload_t = 1.5
	model.reload_anim()
	Game.play("reload", -6.0)


func interact() -> void:
	var w = Game.world
	if w.interior.near_bartender(global_position):
		cancel_focus()
		w.hud.open_building(w.interior.building)
		return
	if w.interior.near_exit(global_position):
		w.hud.fade(func(): w.interior.leave())
		Game.play("door", -6.0)
		return
	var b = w.near_door(global_position)
	if b:
		if mounted:
			dismount()
			return
		cancel_focus()
		if b["type"] == "saloon":
			# в салун — заходим внутрь, меню у бармена
			w.hud.fade(func(): w.interior.enter(b))
			Game.play("door", -6.0)
		else:
			w.hud.open_building(b)
	elif mounted:
		dismount()
	elif global_position.distance_to(horse.global_position) < 3.5:
		mount()


## Посадка: подходит к левому боку, ставит ногу в стремя, перекидывает
## правую ногу через круп и опускается в седло.
func mount() -> void:
	if mount_dir != 0:
		return
	mounted = true
	horse.called = false
	horse.visible = false
	horse_yaw = horse.yaw
	face_yaw = horse_yaw
	global_position = horse.global_position
	_col.shape = _shape_ride
	_col.position.y = 1.5
	horse_model.visible = true
	horse_model.rotation.y = horse_yaw
	model.mounted = true
	model.mount_k = 0.0
	mount_dir = 1
	mount_t = 0.0
	move_vel = Vector3.ZERO
	Game.play("horse", -6.0)
	if randf() < 0.35:
		Game.vo("hero", 2, null, "hero", 30.0, -3.0)


func _side_pos() -> Vector3:
	var right := Vector3(cos(horse_yaw), 0, -sin(horse_yaw))
	return -right * 0.85


func _update_mounting(real: float) -> void:
	mount_t += real / (MOUNT_TIME if mount_dir > 0 else DISMOUNT_TIME)
	var k := clampf(mount_t, 0.0, 1.0)
	if mount_dir < 0:
		k = 1.0 - k
	model.mount_k = k
	model.rotation.y = horse_yaw
	face_yaw = horse_yaw
	horse_model.rider = null
	var seat: Vector3 = horse_model.rider_pos(horse_yaw, model.hip_y, model.sit_h)
	var side := _side_pos()
	var up := smoothstep(0.15, 0.7, k)
	var over := smoothstep(0.35, 0.95, k)
	model.position = Vector3(lerpf(side.x, seat.x, over), lerpf(0.0, seat.y, up), lerpf(side.z, seat.z, over))
	horse_model.rotation.y = horse_yaw
	horse_model.animate(0.0, real)
	model.animate(0.0, real)
	if mount_t >= 1.0:
		if mount_dir > 0:
			model.mount_k = 1.0
			mount_dir = 0
		else:
			mount_dir = 0
			_finish_dismount()


func dismount() -> void:
	if mount_dir != 0 or not mounted:
		return
	mount_dir = -1
	mount_t = 0.0
	move_vel = Vector3.ZERO
	cancel_focus()


func _finish_dismount() -> void:
	mounted = false
	horse.global_position = global_position
	horse.yaw = horse_yaw
	horse.visible = true
	horse_model.visible = false
	model.mounted = false
	model.mount_k = 1.0
	model.position = Vector3.ZERO
	_col.shape = _shape_walk
	_col.position.y = 0.95
	move_and_collide(_side_pos())
	global_position.y = Game.world.ground(global_position.x, global_position.z)
	move_vel = Vector3.ZERO
	velocity = Vector3.ZERO


func hurt(dmg: float, from := Vector3.INF) -> void:
	if dead:
		return
	if from != Vector3.INF:
		var to := from - global_position
		Game.world.hud.damage_from(atan2(-to.x, -to.z) - yaw)
	# конь под всадником шарахается от ранения
	if mounted and mount_dir == 0 and randf() < 0.25:
		horse_model.play_once("Buck_2")
		Game.play_at("neigh", global_position + Vector3(0, 2.0, 0), -2.0, randf_range(0.9, 1.1), 12.0)
	Game.hp -= dmg
	last_hit = clock
	flash = 0.35
	shake = 6.0
	Game.world.fx.blood(global_position + Vector3(0, 1.4, 0))
	Game.play("hurt", -8.0)
	if Game.hp <= 0.0:
		Game.hp = 0.0
		if mounted:
			mount_dir = 0
			_finish_dismount()
		cancel_focus()
		dead = true
		dead_t = 0.0
		model.set_dead(true)
		Game.play("death", -4.0)


func revive(at: Vector3) -> void:
	dead = false
	model.set_dead(false)
	global_position = at
	move_vel = Vector3.ZERO
	snap_camera()
