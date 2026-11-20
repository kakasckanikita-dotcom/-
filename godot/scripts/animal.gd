extends CharacterBody3D
## Животные Территории Мескаль: вилороги (стада на равнинах), зайцы,
## койоты (днём сторонятся людей, ночью нападают стаей), коровы у городов.
## Всех можно подстрелить; со шкуры — деньги в лавке (сразу при обыске).

const AnimalModel := preload("res://scripts/animal_model.gd")

const SPECIES := {
	"pronghorn": {"file": "pronghorn", "len": 1.45, "yaw": PI, "hp": 60.0, "idle": "Stand_Eating", "walk": "Walk", "run": "Sprint", "die": "Death_Stand_R01", "walk_spd": 1.4, "run_spd": 11.0, "pelt": [6, 12], "name": "вилорога", "shy": 28.0},
	"hare": {"file": "hare", "len": 0.5, "yaw": PI, "hp": 15.0, "idle": "Idle", "walk": "walk", "run": "run", "die": "", "walk_spd": 0.8, "run_spd": 8.0, "pelt": [1, 3], "name": "зайца", "shy": 14.0},
	"coyote": {"file": "coyote", "len": 1.05, "yaw": PI, "hp": 45.0, "idle": "Coyote_Idle", "walk": "Coyote_Walk", "run": "Coyote_Walk", "die": "", "walk_spd": 1.6, "run_spd": 7.5, "pelt": [3, 6], "name": "койота", "shy": 18.0},
	"cow": {"file": "cow", "len": 2.2, "yaw": PI, "hp": 120.0, "idle": "idle1", "walk": "idle2", "run": "idle2", "die": "Death", "walk_spd": 0.6, "run_spd": 3.0, "pelt": [0, 0], "name": "коровы", "shy": 6.0},
}

var species := "pronghorn"
var cfg: Dictionary
var model: Node3D
var hp := 50.0
var dead := false
var dead_t := 0.0
var home := Vector3.ZERO
var wt := Vector3.ZERO
var wt_t := 0.0
var flee := 0.0
var yaw := 0.0
var leader: Node3D = null # стадо держится вожака
var _think := 0.0
var _bite := 0.0
var _call_t := randf_range(8.0, 40.0)


func setup(kind: String, pos: Vector3) -> void:
	species = kind
	cfg = SPECIES[kind]
	position = pos
	home = pos
	wt = pos
	hp = cfg["hp"]
	yaw = randf() * TAU


func _ready() -> void:
	collision_layer = 4 # как у людей: пули попадают
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var s := CapsuleShape3D.new()
	var L: float = cfg["len"]
	s.radius = L * 0.22
	s.height = L * 0.9
	cs.shape = s
	cs.rotation.x = PI / 2.0
	cs.position.y = L * 0.35
	add_child(cs)
	model = AnimalModel.new()
	add_child(model)
	model.setup(cfg["file"], L, cfg["yaw"], cfg["idle"])
	add_to_group("animals")


func head_height() -> float:
	return float(cfg["len"]) * 0.55


func _physics_process(delta: float) -> void:
	if dead:
		dead_t += delta
		if dead_t > 180.0 and Game.world.player.global_position.distance_to(home) > 150.0:
			_respawn()
		return
	var p = Game.world.player
	var to_p: Vector3 = p.global_position - global_position
	to_p.y = 0.0
	var d := to_p.length()
	# далёкие животные почти не думают
	if d > 160.0:
		_think -= delta
		if _think > 0.0:
			return
		_think = 1.0
	# голоса: коровы мычат, койоты ночью воют и тявкают перед нападением
	_call_t -= delta
	if _call_t <= 0.0:
		_call_t = randf_range(18.0, 45.0)
		if species == "cow" and d < 70.0:
			Game.play_at("moo", global_position + Vector3(0, 1.4, 0), -4.0, randf_range(0.85, 1.1), 12.0)
		elif species == "coyote" and Game.darkness() > 0.5 and d < 140.0 and (leader == null or randf() < 0.3):
			Game.play_at("coyote_howl", global_position + Vector3(0, 1, 0), -2.0, randf_range(0.9, 1.1), 30.0)
	var spd := 0.0
	var mv := Vector3.ZERO
	var night := Game.darkness() > 0.6
	var hunting: bool = species == "coyote" and night and not p.dead and d < 45.0
	if hunting:
		# стая койотов ночью нападает
		var dir := to_p / maxf(d, 0.01)
		mv = dir
		spd = cfg["run_spd"] if d > 1.6 else 0.0
		_bite -= delta
		if d < 1.8 and _bite <= 0.0:
			_bite = 1.2
			p.hurt(6.0)
			Game.play_at("hurt", global_position, -10.0, 1.6, 6.0)
	elif flee > 0.0 or (d < float(cfg["shy"]) and not p.dead):
		if d < float(cfg["shy"]):
			flee = maxf(flee, 4.0)
		flee -= delta
		var away := (-to_p / maxf(d, 0.01)).rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.002 + home.x) * 0.5)
		mv = away
		spd = cfg["run_spd"]
	else:
		wt_t -= delta
		if wt_t <= 0.0:
			wt_t = randf_range(4.0, 12.0)
			var base := home
			if leader and is_instance_valid(leader) and not leader.dead:
				base = leader.global_position
			var r := 4.0 if species == "cow" else 14.0
			wt = base + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
		var tw := wt - global_position
		tw.y = 0.0
		if tw.length() > 1.0 and wt_t < 9.0:
			mv = tw.normalized()
			spd = cfg["walk_spd"]
	if spd > 0.1:
		yaw = lerp_angle(yaw, atan2(-mv.x, -mv.z), minf(1.0, delta * 6.0))
	if Game.world.in_water(global_position):
		spd *= 0.5
	velocity = Vector3(-sin(yaw), 0, -cos(yaw)) * spd if spd > 0.1 else Vector3.ZERO
	var before := global_position
	move_and_slide()
	if not Game.world.ground_move(self, before):
		wt_t = 0.0
		yaw += PI * 0.6
	model.rotation.y = yaw
	# анимация по скорости
	if spd < 0.2:
		model.play(cfg["idle"], 1.0)
	elif spd < float(cfg["walk_spd"]) * 1.5:
		model.play(cfg["walk"], 1.0)
	else:
		var rate := 1.0 if cfg["run"] != cfg["walk"] else spd / float(cfg["walk_spd"]) * 0.5
		model.play(cfg["run"], clampf(rate, 0.8, 3.0))


## Выстрел рядом пугает животных.
func scare() -> void:
	if not dead and species != "coyote":
		flee = 6.0


func take_hit(dmg: float, by_player: bool) -> void:
	if dead:
		return
	hp -= dmg
	Game.world.fx.blood(global_position + Vector3(0, head_height(), 0))
	flee = 8.0
	if hp <= 0.0:
		_die(by_player)


func _die(by_player: bool) -> void:
	dead = true
	dead_t = 0.0
	collision_layer = 0
	velocity = Vector3.ZERO
	if cfg["die"] != "":
		model.play(cfg["die"], 1.0, 0.1)
	else:
		# у модели нет клипа смерти — тело заваливается на бок
		if model.ap:
			model.ap.pause()
		model.rotation.z = PI / 2.0
		model.position.y = float(cfg["len"]) * 0.12
	if by_player:
		if species == "cow":
			Game.honor -= 3
			Game.say("Это была чья-то корова. Честь −3", Game.BAD)
		else:
			var pr: Array = cfg["pelt"]
			var l = Game.world.drop_pelt(global_position, randi_range(pr[0], pr[1]), cfg["name"])
			l.position.y = Game.world.ground(l.position.x, l.position.z)


func _respawn() -> void:
	dead = false
	hp = cfg["hp"]
	collision_layer = 4
	global_position = Vector3(home.x, Game.world.ground(home.x, home.z), home.z)
	model.rotation.z = 0.0
	model.position.y = 0.0
	model.play(cfg["idle"], 1.0, 0.0)
