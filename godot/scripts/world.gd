extends Node2D
## Корень игры: генерирует Территорию Мескаль (реку, дороги, города, лагеря,
## кактусы и скалы), спавнит персонажей и ведёт мировую логику: смену суток,
## возрождение лагерей, погоню за преступником.

const WORLD := 4800.0
const RIVER_W := 86.0
const BRIDGES := [2350.0, 700.0, 4050.0]
const CAMP_NAMES := ["Овраг Гремучей Змеи", "Каньон Висельника", "Сухой Колодец", "Скалы Койота", "Старая Шахта", "Красный Утёс", "Ржавая Лощина", "Брод Мертвеца"]
const FOLK_COLORS := ["5e7aa0", "8a6d9e", "9e6b4a", "6b8a5a", "a08a5e", "7a5050"]
const BANDIT_COLORS := ["7a2a1e", "6a4a2a", "5a3a3a", "4a3a2a"]

const PlayerScript := preload("res://scripts/player.gd")
const HorseScript := preload("res://scripts/horse.gd")
const NpcScript := preload("res://scripts/npc.gd")
const ObstacleScript := preload("res://scripts/obstacle.gd")
const BuildingScript := preload("res://scripts/building.gd")
const CampScript := preload("res://scripts/camp.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const LootScript := preload("res://scripts/loot.gd")
const GroundScript := preload("res://scripts/ground.gd")
const DecorScript := preload("res://scripts/decor.gd")
const FxScript := preload("res://scripts/fx.gd")

var rng := RandomNumberGenerator.new()
var roads: Array = [] # массивы точек
var towns: Array = [] # {name, pos, r, buildings}
var buildings: Array = []
var camps: Array = []
var obstacles: Array = [] # [pos, r] — для генерации
var entities: Node2D
var fx: Node2D
var player: CharacterBody2D
var horse: CharacterBody2D
var hud: Control
var law_t := 0.0

@onready var day_night: CanvasModulate = $DayNight


func _ready() -> void:
	Game.world = self
	hud = $HUD/Overlay
	rng.seed = 1889 # один и тот же мир при каждом запуске
	_build_roads()
	_build_towns()

	var ground := GroundScript.new()
	ground.world = self
	add_child(ground)

	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	fx = FxScript.new()
	add_child(fx)

	for t in towns:
		for b in t["buildings"]:
			entities.add_child(b)
	_gen_camps()
	_gen_obstacles()
	_gen_decor()

	horse = HorseScript.new()
	horse.position = Vector2(1180, 1350)
	entities.add_child(horse)
	player = PlayerScript.new()
	player.position = Vector2(1100, 1300)
	player.horse = horse
	entities.add_child(player)

	for t in towns:
		for i in 7:
			var n := spawn_npc("folk", t["pos"] + Vector2(rng.randf_range(-380, 380), rng.randf_range(-50, 50)))
			n.town = t
			n.body_col = Color(FOLK_COLORS[i % FOLK_COLORS.size()])
		var sh = t["buildings"].filter(func(b): return b.type == "sheriff")[0]
		for i in 2:
			var s := spawn_npc("sheriff", sh.door + Vector2(rng.randf_range(-40, 40), 30))
			s.town = t
	for c in camps:
		populate_camp(c)

	var autosave := Timer.new()
	autosave.wait_time = 10.0
	autosave.autostart = true
	autosave.timeout.connect(Game.save_game)
	add_child(autosave)


# ---------- география ----------
func river_x(y: float) -> float:
	return 2400.0 + sin(y / 620.0) * 380.0 + sin(y / 210.0 + 1.3) * 110.0


func on_bridge(y: float) -> bool:
	for b in BRIDGES:
		if absf(y - b) < 42.0:
			return true
	return false


func in_water(p: Vector2) -> bool:
	return absf(p.x - river_x(p.y)) < RIVER_W / 2.0 and not on_bridge(p.y)


func _build_roads() -> void:
	roads = [
		[Vector2(1100, 1300), Vector2(1500, 1300), Vector2(river_x(2350) - 220, 2350), Vector2(river_x(2350) + 220, 2350), Vector2(3300, 3400), Vector2(3700, 3400)],
		[Vector2(1100, 1300), Vector2(1100, 700), Vector2(river_x(700) - 200, 700), Vector2(river_x(700) + 250, 700), Vector2(3700, 900)],
		[Vector2(3700, 3400), Vector2(3700, 4050), Vector2(river_x(4050) + 200, 4050), Vector2(river_x(4050) - 200, 4050), Vector2(1000, 4100)],
	]


func near_road(p: Vector2, d: float) -> bool:
	for r in roads:
		for i in r.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, r[i], r[i + 1])) < d:
				return true
	return false


func _build_towns() -> void:
	_make_town("Пыльный Ручей", Vector2(1100, 1300))
	_make_town("Медная Гора", Vector2(3700, 3400))


func _make_town(town_name: String, c: Vector2) -> void:
	var t := {"name": town_name, "pos": c, "r": 470.0, "buildings": []}
	var north := ["saloon", "store", "sheriff", "house"]
	var south := ["house", "bank", "house", "house"]
	for i in 4:
		var w := 150.0
		var h := 120.0
		var x := c.x - 340.0 + i * 175.0
		_add_building(t, Rect2(x, c.y - 70.0 - h, w, h), north[i], Vector2(x + w / 2.0, c.y - 70.0))
		_add_building(t, Rect2(x, c.y + 70.0, w, h), south[i], Vector2(x + w / 2.0, c.y + 70.0))
	towns.append(t)


func _add_building(t: Dictionary, r: Rect2, type: String, door: Vector2) -> void:
	var b := BuildingScript.new()
	b.rect = r
	b.type = type
	b.door = door
	b.town = t
	b.position = Vector2(r.position.x + r.size.x / 2.0, r.end.y)
	t["buildings"].append(b)
	buildings.append(b)


func _free_spot(p: Vector2, pad: float, town_pad := -1.0) -> bool:
	if p.x < 120 or p.y < 120 or p.x > WORLD - 120 or p.y > WORLD - 120:
		return false
	var tp := pad if town_pad < 0.0 else town_pad
	for t in towns:
		if p.distance_to(t["pos"]) < t["r"] + tp:
			return false
	if absf(p.x - river_x(p.y)) < RIVER_W / 2.0 + pad:
		return false
	if near_road(p, pad * 0.6 + 40.0):
		return false
	for c in camps:
		if p.distance_to(c.position) < 220.0 + pad:
			return false
	for o in obstacles:
		if p.distance_to(o[0]) < o[1] + pad * 0.5:
			return false
	return true


func _gen_camps() -> void:
	for i in CAMP_NAMES.size():
		var p := Vector2.ZERO
		for attempt in 500:
			p = Vector2(rng.randf_range(300, WORLD - 300), rng.randf_range(300, WORLD - 300))
			var far := true
			for c in camps:
				if p.distance_to(c.position) < 900:
					far = false
			if far and _free_spot(p, 200.0, 700.0):
				break
		var camp := CampScript.new()
		camp.camp_name = CAMP_NAMES[i]
		camp.position = p
		for k in 3:
			var a := k * 2.1 + rng.randf_range(0, 0.5)
			camp.tents.append([Vector2.from_angle(a) * 90.0, a + PI / 2.0])
		camps.append(camp)
		add_child(camp)


func _gen_obstacles() -> void:
	for i in 300:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if _free_spot(p, 40.0):
			_add_obstacle("cactus", p, rng.randf_range(10, 15))
	for i in 160:
		var r := rng.randf_range(16, 42)
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if _free_spot(p, r + 20.0):
			_add_obstacle("rock", p, r)


func _add_obstacle(kind: String, p: Vector2, r: float) -> void:
	var o := ObstacleScript.new()
	o.kind = kind
	o.r = r
	o.position = p
	o.arms = rng.randi_range(0, 2)
	o.rot = rng.randf_range(0, TAU)
	o.sh = rng.randf()
	obstacles.append([p, r])
	entities.add_child(o)


func _gen_decor() -> void:
	const CHUNK := 800.0
	var chunks := {}
	for i in 2600:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if in_water(p):
			continue
		var key := Vector2i(int(p.x / CHUNK), int(p.y / CHUNK))
		if not chunks.has(key):
			var d := DecorScript.new()
			chunks[key] = d
			add_child(d)
		chunks[key].items.append([p, 0 if rng.randf() < 0.7 else 1, rng.randf_range(0.6, 1.4)])


# ---------- персонажи ----------
func spawn_npc(kind: String, pos: Vector2) -> CharacterBody2D:
	var n := NpcScript.new()
	n.setup(kind, pos)
	entities.add_child(n)
	return n


func populate_camp(c: Node2D) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.camp == c:
			n.queue_free()
	var cnt := randi_range(3, 5)
	for i in cnt:
		var a := randf() * TAU
		var n := spawn_npc("bandit", c.position + Vector2.from_angle(a) * randf_range(30, 70))
		n.camp = c
		n.body_col = Color(BANDIT_COLORS.pick_random())
	if Game.bounty != null and Game.bounty["camp"] == c and not Game.bounty["done"]:
		var l := spawn_npc("leader", c.position + Vector2(0, 10))
		l.camp = c
		l.npc_name = Game.bounty["name"]
	c.cleared = false
	c.timer = 0.0


func camp_members(c: Node2D) -> Array:
	return get_tree().get_nodes_in_group("npcs").filter(func(n): return n.camp == c and not n.is_queued_for_deletion())


func check_camp(c: Node2D) -> void:
	if c == null or c.cleared:
		return
	for n in camp_members(c):
		if not n.dead:
			return
	c.cleared = true
	c.timer = 0.0
	Game.honor += 5
	Game.say("Лагерь «%s» зачищен" % c.camp_name, Game.GOOD)


func place_player(p: Vector2) -> void:
	player.global_position = p
	horse.global_position = p + Vector2(60, 30)
	player.cam.reset_smoothing()


func respawn_player() -> void:
	player.revive(towns[0]["pos"] + Vector2(0, 20))
	horse.global_position = player.global_position + Vector2(60, 30)
	horse.visible = true
	Game.hp = 100.0
	Game.money = int(Game.money * 0.8)
	Game.clip = 6
	Game.ammo = maxi(Game.ammo, 12)
	clear_wanted()
	Game.say("Доктор подлатал вас. Часть денег ушла на лечение.")
	Game.save_game()


# ---------- бой ----------
func fire(pos: Vector2, ang: float, from_player: bool, dmg: float, shooter: RID) -> void:
	var b := BulletScript.new()
	b.position = pos + Vector2.from_angle(ang) * 18.0
	b.vel = Vector2.from_angle(ang) * 1300.0
	b.from_player = from_player
	b.dmg = dmg
	b.shooter = shooter
	add_child(b)
	fx.muzzle(pos, ang)


func has_los(a: Vector2, b: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(a, b, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func alert_town(p: Vector2) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and n.kind == "folk" and n.global_position.distance_to(p) < 500:
			n.flee = 6.0


func drop_loot(p: Vector2) -> void:
	var l := LootScript.new()
	l.position = p + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	l.money = randi_range(3, 12)
	l.ammo = randi_range(2, 6)
	add_child(l)


func clear_wanted() -> void:
	Game.wanted = 0
	Game.evade = 0.0
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.kind == "lawman":
			n.queue_free()
		elif n.kind == "sheriff":
			n.aggro = false


func near_door(p: Vector2):
	for b in buildings:
		if b.type != "house" and p.distance_to(b.door) < 60.0:
			return b
	return null


func town_at(p: Vector2):
	for t in towns:
		if p.distance_to(t["pos"]) < t["r"]:
			return t
	return null


func nearest_sheriff_door(p: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	for b in buildings:
		if b.type == "sheriff" and p.distance_to(b.door) < bd:
			bd = p.distance_to(b.door)
			best = b.door
	return best


func accept_bounty(bname: String, reward: int, c: Node2D) -> void:
	Game.bounty = {"name": bname, "reward": reward, "camp": c, "done": false}
	c.known = true
	populate_camp(c)


func drop_bounty() -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.kind == "leader":
			n.queue_free()
	Game.bounty = null


# ---------- мировой цикл ----------
func _process(delta: float) -> void:
	Game.game_time += delta * 3.0 # 1 секунда = 3 игровые минуты
	if Game.game_time >= 1440.0:
		Game.game_time -= 1440.0
		Game.day += 1
	if Game.bank_cd > 0.0:
		Game.bank_cd -= delta

	var pp := player.global_position
	for c in camps:
		if pp.distance_to(c.position) < 900.0:
			c.known = true
		if c.cleared:
			c.timer += delta
			if c.timer > 300.0 and pp.distance_to(c.position) > 1200.0:
				populate_camp(c)

	for n in get_tree().get_nodes_in_group("npcs"):
		if n.dead and n.town == null and n.dead_t > 120.0:
			n.queue_free()

	_update_law(delta)

	# смена дня и ночи
	var dk := Game.darkness()
	var col := Color.WHITE.lerp(Color(0.22, 0.27, 0.48), dk / 0.72)
	var h := Game.game_time / 60.0
	if h > 16.0 and h < 18.0:
		col = col.lerp(Color(1.0, 0.78, 0.6), (h - 16.0) / 2.0 * 0.5)
	day_night.color = col
	player.lantern.energy = dk * 1.6


func _update_law(delta: float) -> void:
	if Game.wanted <= 0 or player.dead:
		return
	law_t -= delta
	var law := get_tree().get_nodes_in_group("npcs").filter(func(n): return n.kind == "lawman" and not n.dead)
	if law_t <= 0.0 and law.size() < Game.wanted * 2:
		var a := randf() * TAU
		var p := player.global_position + Vector2.from_angle(a) * 800.0
		var n := spawn_npc("lawman", p.clamp(Vector2(40, 40), Vector2(WORLD - 40, WORLD - 40)))
		n.aggro = true
		law_t = maxf(5.0, 14.0 - Game.wanted * 2.0)
	var near := false
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and (n.kind == "lawman" or n.kind == "sheriff") and n.global_position.distance_to(player.global_position) < 700.0:
			near = true
			break
	if near:
		Game.evade = 0.0
	else:
		Game.evade += delta
		if Game.evade > 25.0:
			clear_wanted()
			Game.say("Вы ушли от погони.", Game.GOOD)
