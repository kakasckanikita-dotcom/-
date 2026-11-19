extends Node3D
## Корень игры. Генерирует Территорию Мескаль в 3D: пустыню, реку с мостами,
## дороги, два города, бандитские лагеря, кактусы, скалы и столовые горы.
## Ведёт мировую логику: смену суток, возрождение лагерей, погоню за героем.
## Координаты: X — восток, Z — юг, Y — вверх; 1 единица = 1 метр.

const WORLD := 1000.0
const RIVER_W := 18.0
const BRIDGES := [490.0, 146.0, 845.0]
const CAMP_NAMES := ["Овраг Гремучей Змеи", "Каньон Висельника", "Сухой Колодец", "Скалы Койота", "Старая Шахта", "Красный Утёс", "Ржавая Лощина", "Брод Мертвеца"]
const FOLK_COLORS := ["5e7aa0", "8a6d9e", "9e6b4a", "6b8a5a", "a08a5e", "7a5050"]
const BANDIT_COLORS := ["7a2a1e", "6a4a2a", "5a3a3a", "4a3a2a"]
const NAMES := {"saloon": "САЛУН", "store": "ЛАВКА", "sheriff": "ШЕРИФ", "bank": "БАНК", "hotel": "ГОСТИНИЦА", "house": ""}
const WALL := {"saloon": "8a5a3a", "store": "7a6a4a", "sheriff": "6a6a72", "bank": "9a8a70", "hotel": "7a4a3a"}

const PlayerScript := preload("res://scripts/player.gd")
const HorseScript := preload("res://scripts/horse.gd")
const NpcScript := preload("res://scripts/npc.gd")
const CampScript := preload("res://scripts/camp.gd")
const LootScript := preload("res://scripts/loot.gd")
const FxScript := preload("res://scripts/fx.gd")
const GroundShader := preload("res://scripts/ground.gdshader")
const WaterShader := preload("res://scripts/water.gdshader")

var rng := RandomNumberGenerator.new()
var roads: Array = [] # массивы Vector2 (x, z)
var towns: Array = [] # {name, pos: Vector2, r, buildings}
var buildings: Array = [] # {type, town, door: Vector3, rect: Rect2}
var camps: Array = []
var obstacles: Array = [] # [Vector2, радиус] — для генерации
var fx: Node3D
var player: CharacterBody3D
var horse: CharacterBody3D
var hud: Control
var law_t := 0.0

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var _static: StaticBody3D


func _ready() -> void:
	Game.world = self
	hud = $HUD/Overlay
	rng.seed = 1889 # один и тот же мир при каждом запуске
	_setup_environment()
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	_static.collision_mask = 0
	add_child(_static)
	_build_roads()
	_build_ground()
	_build_towns()
	_gen_camps()
	_gen_obstacles()
	_build_mesas()

	fx = FxScript.new()
	add_child(fx)
	horse = HorseScript.new()
	horse.position = Vector3(238, 0, 274)
	add_child(horse)
	player = PlayerScript.new()
	player.position = Vector3(230, 0, 270)
	player.horse = horse
	add_child(player)

	for t in towns:
		for i in 7:
			var n := spawn_npc("folk", _v3(t["pos"] + Vector2(rng.randf_range(-35, 35), rng.randf_range(-6, 6))))
			n.town = t
			n.body_col = Color(FOLK_COLORS[i % FOLK_COLORS.size()])
			n.rebuild()
		var sh: Dictionary = t["buildings"].filter(func(b): return b["type"] == "sheriff")[0]
		for i in 2:
			var s := spawn_npc("sheriff", sh["door"] + Vector3(rng.randf_range(-3, 3), 0, 0) + sh["out"] * 3.0)
			s.town = t
	for c in camps:
		populate_camp(c)

	var autosave := Timer.new()
	autosave.wait_time = 10.0
	autosave.autostart = true
	autosave.timeout.connect(Game.save_game)
	add_child(autosave)


static func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0, p.y)


static func v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


# ---------- окружение ----------
func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.light_color = Color(1.0, 0.95, 0.85)
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _update_sky() -> void:
	var h := Game.game_time / 60.0
	var dk := Game.darkness()
	var elev := (h - 6.0) / 12.0 * PI # 0 на рассвете, PI/2 в полдень
	sun.rotation = Vector3(-clampf(elev, -0.3, PI + 0.3), deg_to_rad(-35), 0)
	var day_k := clampf(sin(elev) * 3.0, 0.0, 1.0)
	sun.light_energy = day_k * 1.3
	sun.visible = day_k > 0.01
	var dusk := clampf(1.0 - absf(sin(elev)) * 4.0, 0.0, 1.0) * day_k
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.35), dusk)
	moon.light_energy = dk * 0.35
	moon.visible = dk > 0.01
	sky_mat.sky_top_color = Color("3d74c4").lerp(Color("070b1c"), dk)
	sky_mat.sky_horizon_color = Color("e6c9a2").lerp(Color("e08850"), dusk).lerp(Color("1a1d33"), dk)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color("8a6a48").lerp(Color("0a0a12"), dk)
	env.ambient_light_energy = lerpf(1.0, 0.18, dk)
	env.fog_light_color = Color("d8bf98").lerp(Color("e08850"), dusk * 0.6).lerp(Color("10131f"), dk)


# ---------- география ----------
func river_x(z: float) -> float:
	return 500.0 + sin(z / 130.0) * 80.0 + sin(z / 44.0 + 1.3) * 23.0


func on_bridge(z: float) -> bool:
	for b in BRIDGES:
		if absf(z - b) < 5.0:
			return true
	return false


func in_water(p: Vector3) -> bool:
	return absf(p.x - river_x(p.z)) < RIVER_W / 2.0 and not on_bridge(p.z)


func _build_roads() -> void:
	roads = [
		[Vector2(230, 270), Vector2(310, 270), Vector2(river_x(490) - 45, 490), Vector2(river_x(490) + 45, 490), Vector2(690, 710), Vector2(770, 710)],
		[Vector2(230, 270), Vector2(230, 146), Vector2(river_x(146) - 40, 146), Vector2(river_x(146) + 50, 146), Vector2(770, 190)],
		[Vector2(770, 710), Vector2(770, 845), Vector2(river_x(845) + 40, 845), Vector2(river_x(845) - 40, 845), Vector2(210, 855)],
	]


func near_road(p: Vector2, d: float) -> bool:
	for r in roads:
		for i in r.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, r[i], r[i + 1])) < d:
				return true
	return false


func _noise_tex(seed_v: int, freq: float, size := 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	return t


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1800, 1800)
	var gm := ShaderMaterial.new()
	gm.shader = GroundShader
	gm.set_shader_parameter("noise_small", _noise_tex(3, 0.02))
	gm.set_shader_parameter("noise_big", _noise_tex(11, 0.01))
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = gm
	g.position = Vector3(500, 0, 500)
	add_child(g)
	for r in roads:
		var road := Mk.strip(r, 7.0, 0.02, Color("a8845a"))
		add_child(road)
		var rut := Mk.strip(r, 1.0, 0.03, Color("94714c"))
		add_child(rut)
	# река
	var centers := PackedVector2Array()
	var z := -400.0
	while z <= WORLD + 400.0:
		centers.append(Vector2(river_x(z), z))
		z += 6.0
	add_child(Mk.ribbon(centers, RIVER_W + 8.0, 0.015, Mk.mat(Color("6f7740"))))
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	add_child(Mk.ribbon(centers, RIVER_W, 0.05, wm))
	for bz in BRIDGES:
		var bx := river_x(bz)
		var bridge := Node3D.new()
		bridge.position = Vector3(bx, 0, bz)
		add_child(bridge)
		var i := -RIVER_W / 2.0 - 4.0
		while i < RIVER_W / 2.0 + 4.0:
			Mk.box(bridge, Vector3(0.9, 0.25, 8.0), Vector3(i, 0.25, 0), Color("7a5232") if int(i) % 2 == 0 else Color("6b4423"))
			i += 1.0
		for side in [-1, 1]:
			Mk.box(bridge, Vector3(RIVER_W + 8.0, 0.15, 0.15), Vector3(0, 1.0, side * 3.9), Color("4a2e18"))
			var px := -RIVER_W / 2.0 - 4.0
			while px <= RIVER_W / 2.0 + 4.0:
				Mk.box(bridge, Vector3(0.18, 1.0, 0.18), Vector3(px, 0.5, side * 3.9), Color("4a2e18"))
				px += 4.0


# ---------- города ----------
func _build_towns() -> void:
	_make_town("Пыльный Ручей", Vector2(230, 270))
	_make_town("Медная Гора", Vector2(770, 710))


func _make_town(town_name: String, c: Vector2) -> void:
	var t := {"name": town_name, "pos": c, "r": 70.0, "buildings": []}
	towns.append(t)
	var north := ["saloon", "store", "sheriff", "house", "house"]
	var south := ["house", "bank", "hotel", "house", "house"]
	var street := Mk.box(self, Vector3(84, 0.02, 20), Vector3(c.x, 0.01, c.y), Color("a8845a"))
	street.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 5:
		var x := c.x - 28.0 + i * 14.0
		_building(t, north[i], Vector2(x, c.y - 18.0), 1.0)
		_building(t, south[i], Vector2(x, c.y + 18.0), -1.0)
	# бочки и коновязи для атмосферы
	for i in 6:
		var bx := c.x + rng.randf_range(-38, 38)
		var bz := c.y + (8.5 if i % 2 == 0 else -8.5)
		Mk.cyl(self, 0.38, 0.42, 1.0, Vector3(bx, 0.5, bz), Color("6b4423"), 10)
	for side in [-1.0, 1.0]:
		var rail := Node3D.new()
		rail.position = Vector3(c.x + side * 38.0, 0, c.y + 6.0 * side)
		add_child(rail)
		Mk.box(rail, Vector3(3.0, 0.12, 0.12), Vector3(0, 1.0, 0), Color("4a2e18"))
		Mk.box(rail, Vector3(0.14, 1.0, 0.14), Vector3(-1.4, 0.5, 0), Color("4a2e18"))
		Mk.box(rail, Vector3(0.14, 1.0, 0.14), Vector3(1.4, 0.5, 0), Color("4a2e18"))


## face: +1 — фасад смотрит на юг (+Z), −1 — на север.
func _building(t: Dictionary, type: String, center: Vector2, face: float) -> void:
	var w := 11.0
	var d := 12.0
	var hgt := 5.0 if type != "hotel" else 8.0
	var b := Node3D.new()
	b.position = Vector3(center.x, 0, center.y)
	b.rotation.y = 0.0 if face > 0.0 else PI
	add_child(b)
	var wall := Color(WALL.get(type, ["8a6440", "7a5532", "6e5038"][rng.randi_range(0, 2)]))
	var roof := Color("4a3020")
	Mk.box(b, Vector3(w, hgt, d), Vector3(0, hgt / 2.0, 0), wall)
	Mk.box(b, Vector3(w + 0.6, 0.3, d + 0.6), Vector3(0, hgt + 0.1, 0), roof)
	Mk.box(b, Vector3(w, 2.6, 0.3), Vector3(0, hgt + 1.2, d / 2.0), wall) # фальшфасад
	Mk.box(b, Vector3(1.7, 2.6, 0.1), Vector3(0, 1.3, d / 2.0 + 0.02), Color("2a1a10"))
	for wx in [-3.3, 3.3]:
		Mk.box(b, Vector3(1.6, 1.4, 0.1), Vector3(wx, 2.3, d / 2.0 + 0.02), Color("2b3440"))
		if type == "hotel":
			Mk.box(b, Vector3(1.6, 1.4, 0.1), Vector3(wx, 5.6, d / 2.0 + 0.02), Color("2b3440"))
	Mk.box(b, Vector3(w, 0.25, 3.0), Vector3(0, 0.12, d / 2.0 + 1.5), Color("7a5232"))
	Mk.box(b, Vector3(w, 0.15, 3.2), Vector3(0, 3.3, d / 2.0 + 1.6), roof)
	for px in [-5.2, 5.2]:
		Mk.cyl(b, 0.1, 0.1, 3.3, Vector3(px, 1.65, d / 2.0 + 2.9), Color("4a2e18"), 6)
	var nm: String = NAMES[type]
	if nm != "":
		Mk.box(b, Vector3(7.5, 1.3, 0.12), Vector3(0, hgt + 1.2, d / 2.0 + 0.2), Color("e9d6ae"))
		Mk.label(b, nm, Vector3(0, hgt + 1.2, d / 2.0 + 0.3), 90, Color("3a2412"))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, hgt + 2.6, d)
	cs.shape = shape
	cs.position = Vector3(center.x, (hgt + 2.6) / 2.0, center.y)
	_static.add_child(cs)
	var out := Vector3(0, 0, face) # наружу, к улице
	var door := Vector3(center.x, 0, center.y) + out * (d / 2.0 + 1.6)
	var data := {"type": type, "town": t, "door": door, "out": out, "rect": Rect2(center.x - w / 2.0, center.y - d / 2.0, w, d)}
	t["buildings"].append(data)
	buildings.append(data)


# ---------- лагеря и природа ----------
func _free_spot(p: Vector2, pad: float, town_pad := -1.0) -> bool:
	if p.x < 25 or p.y < 25 or p.x > WORLD - 25 or p.y > WORLD - 25:
		return false
	var tp := pad if town_pad < 0.0 else town_pad
	for t in towns:
		if p.distance_to(t["pos"]) < t["r"] + tp:
			return false
	if absf(p.x - river_x(p.y)) < RIVER_W / 2.0 + 4.0 + pad:
		return false
	if near_road(p, pad * 0.6 + 6.0):
		return false
	for c in camps:
		if p.distance_to(v2(c.position)) < 30.0 + pad:
			return false
	for o in obstacles:
		if p.distance_to(o[0]) < o[1] + pad * 0.5:
			return false
	return true


func _gen_camps() -> void:
	for i in CAMP_NAMES.size():
		var p := Vector2.ZERO
		for attempt in 500:
			p = Vector2(rng.randf_range(60, WORLD - 60), rng.randf_range(60, WORLD - 60))
			var far := true
			for c in camps:
				if p.distance_to(v2(c.position)) < 190.0:
					far = false
			if far and _free_spot(p, 30.0, 140.0):
				break
		var camp := CampScript.new()
		camp.camp_name = CAMP_NAMES[i]
		camp.position = _v3(p)
		camp.seed_v = rng.randi()
		camps.append(camp)
		add_child(camp)


func _gen_obstacles() -> void:
	var cactus: Array[Transform3D] = []
	var arms_v: Array[Transform3D] = []
	var arms_h: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var rock_cols: Array[Color] = []
	for i in 320:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if not _free_spot(p, 6.0):
			continue
		var s := rng.randf_range(0.7, 1.25)
		var rot := rng.randf_range(0, TAU)
		var base := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), _v3(p))
		cactus.append(base * Transform3D(Basis(), Vector3(0, 2.0, 0)))
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.6:
				var hgt := rng.randf_range(1.4, 2.4)
				arms_h.append(base * Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(side * 0.55, hgt, 0)))
				arms_v.append(base * Transform3D(Basis(), Vector3(side * 0.85, hgt + 0.6, 0)))
		_collider(p, 0.4 * s, 4.0 * s)
		obstacles.append([p, 0.5 * s])
	for i in 180:
		var r := rng.randf_range(1.2, 5.0)
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if not _free_spot(p, r + 3.0):
			continue
		var b := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(r * 1.2, r * rng.randf_range(0.5, 0.9), r))
		rocks.append(Transform3D(b, Vector3(p.x, r * 0.2, p.y)))
		rock_cols.append(Color("8b7b6a").lerp(Color("a0684a"), rng.randf()))
		_collider(p, r * 1.05, r * 1.5)
		obstacles.append([p, r * 1.1])

	var green := Color("3f6b33")
	_multimesh(_cyl_mesh(0.38, 0.42, 4.0), cactus, green)
	_multimesh(_cyl_mesh(0.24, 0.26, 1.3), arms_v, green)
	_multimesh(_cyl_mesh(0.22, 0.22, 0.75), arms_h, green)
	var rm := SphereMesh.new()
	rm.radial_segments = 7
	rm.rings = 4
	rm.radius = 1.0
	rm.height = 2.0
	_multimesh(rm, rocks, Color.WHITE, rock_cols)

	# трава и сухие кусты (только вид, без столкновений)
	var tufts: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	for i in 3500:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if in_water(_v3(p)) or near_road(p, 4.0) or town_at(_v3(p)) != null:
			continue
		var s := rng.randf_range(0.6, 1.4)
		if rng.randf() < 0.85:
			tufts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0.25 * s, p.y)))
		else:
			bushes.append(Transform3D(Basis().scaled(Vector3(s, s * 0.6, s)), Vector3(p.x, 0.3 * s, p.y)))
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.28
	tm.height = 0.5
	tm.radial_segments = 4
	tm.rings = 1
	_multimesh(tm, tufts, Color("7d7a3e"), [], false)
	var bm := SphereMesh.new()
	bm.radial_segments = 6
	bm.rings = 3
	bm.radius = 0.6
	bm.height = 1.2
	_multimesh(bm, bushes, Color("8a7a4a"), [], false)


func _cyl_mesh(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


func _multimesh(mesh: Mesh, xforms: Array, c: Color, cols: Array = [], shadows := true) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = mm.use_colors
	mmi.material_override = m
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _collider(p: Vector2, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = Vector3(p.x, h / 2.0, p.y)
	_static.add_child(cs)


func _build_mesas() -> void:
	# столовые горы по краю карты и невидимые стены
	var reds := [Color("a0583a"), Color("b8693f"), Color("8e4c34"), Color("c27a4c")]
	for i in 70:
		var side := i % 4
		var t := rng.randf_range(-100, WORLD + 100)
		var off := rng.randf_range(40, 160)
		var p := Vector2(t, -off)
		match side:
			1: p = Vector2(t, WORLD + off)
			2: p = Vector2(-off, t)
			3: p = Vector2(WORLD + off, t)
		var r := rng.randf_range(25, 70)
		var h := rng.randf_range(25, 85)
		var c: Color = reds[rng.randi_range(0, 3)]
		var m := Mk.cyl(self, r * 0.85, r, h, Vector3(p.x, h / 2.0, p.y), c, 9)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var top := Mk.cyl(self, r * 0.6, r * 0.85, h * 0.25, Vector3(p.x, h + h * 0.125, p.y), c.darkened(0.12), 9)
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for wall in [[Vector3(500, 10, -2), Vector3(1100, 20, 4)], [Vector3(500, 10, WORLD + 2), Vector3(1100, 20, 4)], [Vector3(-2, 10, 500), Vector3(4, 20, 1100)], [Vector3(WORLD + 2, 10, 500), Vector3(4, 20, 1100)]]:
		var cs := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = wall[1]
		cs.shape = s
		cs.position = wall[0]
		_static.add_child(cs)


# ---------- персонажи ----------
func spawn_npc(kind: String, pos: Vector3) -> CharacterBody3D:
	var n := NpcScript.new()
	n.setup(kind, pos)
	add_child(n)
	return n


func populate_camp(c: Node3D) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.camp == c:
			n.queue_free()
	var cnt := randi_range(3, 5)
	for i in cnt:
		var a := randf() * TAU
		var n := spawn_npc("bandit", c.position + Vector3(cos(a), 0, sin(a)) * randf_range(3, 7))
		n.camp = c
		n.body_col = Color(BANDIT_COLORS.pick_random())
		n.rebuild()
	if Game.bounty != null and Game.bounty["camp"] == c and not Game.bounty["done"]:
		var l := spawn_npc("leader", c.position + Vector3(0, 0, 2))
		l.camp = c
		l.npc_name = Game.bounty["name"]
		l.rebuild()
	c.set_cleared(false)


func camp_members(c: Node3D) -> Array:
	return get_tree().get_nodes_in_group("npcs").filter(func(n): return n.camp == c and not n.is_queued_for_deletion())


func check_camp(c: Node3D) -> void:
	if c == null or c.cleared:
		return
	for n in camp_members(c):
		if not n.dead:
			return
	c.set_cleared(true)
	Game.honor += 5
	Game.say("Лагерь «%s» зачищен" % c.camp_name, Game.GOOD)


func place_player(p: Vector3) -> void:
	player.global_position = p
	horse.global_position = p + Vector3(4, 0, 2)
	player.snap_camera()


func respawn_player() -> void:
	player.revive(_v3(towns[0]["pos"]) + Vector3(0, 0, 2))
	horse.global_position = player.global_position + Vector3(4, 0, 2)
	horse.visible = true
	Game.hp = 100.0
	Game.money = int(Game.money * 0.8)
	Game.clip = 6
	Game.ammo = maxi(Game.ammo, 12)
	clear_wanted()
	Game.say("Доктор подлатал вас. Часть денег ушла на лечение.")
	Game.save_game()


# ---------- бой ----------
func ray(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)


func has_los(a: Vector3, b: Vector3) -> bool:
	return ray(a, b, 1).is_empty()


func alert_town(p: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and n.kind == "folk" and n.global_position.distance_to(p) < 50.0:
			n.flee = 6.0


func drop_loot(p: Vector3) -> void:
	var l := LootScript.new()
	l.position = p + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
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


func near_door(p: Vector3):
	for b in buildings:
		if b["type"] != "house" and p.distance_to(b["door"]) < 3.2:
			return b
	return null


func town_at(p: Vector3):
	for t in towns:
		if v2(p).distance_to(t["pos"]) < t["r"]:
			return t
	return null


func nearest_sheriff_door(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for b in buildings:
		if b["type"] == "sheriff" and p.distance_to(b["door"]) < bd:
			bd = p.distance_to(b["door"])
			best = b["door"]
	return best


func accept_bounty(bname: String, reward: int, c: Node3D) -> void:
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
		if pp.distance_to(c.position) < 110.0:
			c.known = true
		if c.cleared:
			c.timer += delta
			if c.timer > 300.0 and pp.distance_to(c.position) > 200.0:
				populate_camp(c)

	for n in get_tree().get_nodes_in_group("npcs"):
		if n.dead and n.town == null and n.dead_t > 120.0:
			n.queue_free()

	_update_law(delta)
	_update_sky()
	player.lantern.light_energy = Game.darkness() * 1.1


func _update_law(delta: float) -> void:
	if Game.wanted <= 0 or player.dead:
		return
	law_t -= delta
	var law := get_tree().get_nodes_in_group("npcs").filter(func(n): return n.kind == "lawman" and not n.dead)
	if law_t <= 0.0 and law.size() < Game.wanted * 2:
		var a := randf() * TAU
		var p := player.global_position + Vector3(cos(a), 0, sin(a)) * 160.0
		p.x = clampf(p.x, 10, WORLD - 10)
		p.z = clampf(p.z, 10, WORLD - 10)
		var n := spawn_npc("lawman", p)
		n.aggro = true
		law_t = maxf(5.0, 14.0 - Game.wanted * 2.0)
	var near := false
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and (n.kind == "lawman" or n.kind == "sheriff") and n.global_position.distance_to(player.global_position) < 90.0:
			near = true
			break
	if near:
		Game.evade = 0.0
	else:
		Game.evade += delta
		if Game.evade > 25.0:
			clear_wanted()
			Game.say("Вы ушли от погони.", Game.GOOD)
