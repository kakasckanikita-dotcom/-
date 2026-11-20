extends Node3D
## Корень игры. Генерирует Территорию Мескаль в 3D: пустыню, реку с мостами,
## дороги, два города, бандитские лагеря, кактусы, скалы и столовые горы.
## Ведёт мировую логику: смену суток, возрождение лагерей, погоню за героем.
## Координаты: X — восток, Z — юг, Y — вверх; 1 единица = 1 метр.

const WORLD := 1000.0
const RIVER_W := 18.0
const BRIDGES := [490.0, 146.0, 845.0]
const CAMP_NAMES := ["Овраг Гремучей Змеи", "Каньон Висельника", "Сухой Колодец", "Скалы Койота", "Старая Шахта", "Красный Утёс", "Ржавая Лощина", "Брод Мертвеца"]
const FOLK_TINTS := [Color(0.75, 0.85, 1.0), Color(0.9, 0.8, 1.0), Color(1.0, 0.9, 0.75), Color(0.8, 1.0, 0.8), Color(1.0, 1.0, 0.85), Color(0.95, 0.8, 0.8)]
const BANDIT_TINTS := [Color(1.0, 0.8, 0.75), Color(0.85, 0.75, 0.65), Color(0.8, 0.7, 0.7), Color(0.7, 0.65, 0.6)]
## Модели зданий: [файл, наибольший размер, поворот, скрыть детали, высота вывески (доля)]
const BUILD := {
	"saloon": ["bank", 12.5, 0.0, ["Object_99"], 0.9],
	"bank": ["bank", 12.5, 0.0, [], 0.0],
	"store": ["store", 12.0, 0.0, [], 0.55],
	"hotel": ["store", 12.0, 0.0, [], 0.55],
	"sheriff": ["house", 11.5, 0.0, [], 0.62],
	"house": ["house", 11.5, 0.0, [], 0.0],
}
const NAMES := {"saloon": "САЛУН", "store": "ЛАВКА", "sheriff": "ШЕРИФ", "bank": "БАНК", "hotel": "ГОСТИНИЦА", "house": ""}
const WALL := {"saloon": "8a5a3a", "store": "7a6a4a", "sheriff": "6a6a72", "bank": "9a8a70", "hotel": "7a4a3a"}

const PlayerScript := preload("res://scripts/player.gd")
const HorseScript := preload("res://scripts/horse.gd")
const NpcScript := preload("res://scripts/npc.gd")
const CampScript := preload("res://scripts/camp.gd")
const LootScript := preload("res://scripts/loot.gd")
const FxScript := preload("res://scripts/fx.gd")
const AnimalScript := preload("res://scripts/animal.gd")
const EagleScript := preload("res://scripts/eagle.gd")
const GroundShader := preload("res://scripts/ground.gdshader")
const SkyShader := preload("res://scripts/sky.gdshader")
const RoadShader := preload("res://scripts/road.gdshader")
const VegScript := preload("res://scripts/veg.gd")
const InteriorScript := preload("res://scripts/interior.gd")
var interior: Node3D
var road_mat: ShaderMaterial
const TerrainScript := preload("res://scripts/terrain.gd")
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
var terrain: Node3D
var _river_snd: AudioStreamPlayer3D
var _music_explore := 0.0
var _music_combat := 0.0

var env: Environment
var sky_mat: ShaderMaterial
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
	_build_towns()
	_gen_camps()
	_build_ground()
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
		var c: Vector2 = t["pos"]
		# скамейки у домов: [x, z края улицы, лицом (yaw)]
		var benches := [[c.x + 15.0, c.y - 8.1, PI], [c.x - 30.0, c.y + 8.1, 0.0], [c.x + 30.0, c.y - 8.1, PI]]
		for bn in benches:
			_bench(Vector3(bn[0], 0, bn[1]), bn[2])
		for i in 9:
			var pos := _v3(c + Vector2(rng.randf_range(-35, 35), rng.randf_range(-6, 6)))
			var mode := ""
			var yaw := rng.randf() * TAU
			if i < 3: # сидят на скамейках
				pos = Vector3(benches[i][0] + rng.randf_range(-0.4, 0.4), 0, benches[i][1])
				mode = "sit"
				yaw = benches[i][2]
			elif i < 7: # беседуют парами
				var j := int((i - 3) / 2.0)
				var pc := c + Vector2(-12.0 + j * 24.0, -2.0 if j == 0 else 3.0)
				var side := -1.0 if (i - 3) % 2 == 0 else 1.0
				pos = _v3(pc + Vector2(side * 0.65, 0))
				mode = "chat"
				yaw = PI * 0.5 if side < 0 else -PI * 0.5
			var n := spawn_npc("folk", pos)
			n.town = t
			n.pose_mode = mode
			n.seat_h = 0.5
			n.yaw = yaw
			n.tint = FOLK_TINTS[i % FOLK_TINTS.size()]
			n.rebuild()
			n.model.rotation.y = yaw
		var sh: Dictionary = t["buildings"].filter(func(b): return b["type"] == "sheriff")[0]
		for i in 2:
			var s := spawn_npc("sheriff", sh["door"] + Vector3(rng.randf_range(-3, 3), 0, 0) + sh["out"] * 3.0)
			s.town = t
	for c in camps:
		populate_camp(c)
	_spawn_animals()
	# зал салуна
	interior = InteriorScript.new()
	add_child(interior)
	interior.build(self)
	interior.populate()

	_setup_audio()

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
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_mat.set_shader_parameter("cloud_noise", _noise_tex(21, 0.006, 512))
	sky_mat.set_shader_parameter("detail_noise", _noise_tex(57, 0.03, 256))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	# кинематографичная картинка: мягкий тонмаппинг, лёгкое свечение,
	# тёплая цветокоррекция и дымка вдали
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.fog_enabled = true
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_blend_splits = true
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
	var elev := (h - 6.0) / 13.5 * PI # 0 на рассвете (6:00), PI/2 в 12:45, закат в 19:30
	sun.rotation = Vector3(-clampf(elev, -0.3, PI + 0.3), deg_to_rad(-35), 0)
	var day_k := clampf(sin(elev) * 3.0, 0.0, 1.0)
	sun.light_energy = day_k * 1.0
	sun.visible = day_k > 0.01
	var dusk := clampf(1.0 - absf(sin(elev)) * 4.0, 0.0, 1.0) * day_k
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.6, 0.35), dusk)
	moon.light_energy = dk * 0.35
	moon.visible = dk > 0.01
	var top := Color("3a6fc0").lerp(Color("4a5a9a"), dusk * 0.5).lerp(Color("060914"), dk)
	var hor := Color("dcc6a2").lerp(Color("f09858"), dusk).lerp(Color("161a2e"), dk)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", Color("8a6a48").lerp(Color("0a0a12"), dk))
	sky_mat.set_shader_parameter("sun_tint", Color(1.0, 0.92, 0.75).lerp(Color(1.0, 0.55, 0.3), dusk))
	sky_mat.set_shader_parameter("night", dk)
	sky_mat.set_shader_parameter("dusk", dusk)
	sky_mat.set_shader_parameter("moon_dir", -moon.global_basis.z)
	env.ambient_light_energy = lerpf(0.75, 0.3, dk) + dusk * 0.25
	env.ambient_light_color = Color(0.78, 0.74, 0.68).lerp(Color(0.95, 0.65, 0.5), dusk).lerp(Color(0.22, 0.27, 0.42), dk)
	env.fog_light_color = Color("b9a07c").lerp(Color("e08850"), dusk * 0.6).lerp(Color("10131f"), dk)


# ---------- география ----------
func river_x(z: float) -> float:
	return 500.0 + sin(z / 130.0) * 80.0 + sin(z / 44.0 + 1.3) * 23.0


func on_bridge(z: float) -> bool:
	for b in BRIDGES:
		if absf(z - b) < 5.0:
			return true
	return false


## Высота земли в точке (0 там, где рельеф ещё не построен).
func ground(x: float, z: float) -> float:
	if interior and interior.contains(x, z):
		return interior.ORIGIN.y
	return terrain.height(x, z) if terrain else 0.0


## Перемещение по рельефу: ставит тело на землю и не пускает на склоны
## круче ~45°. Возвращает false, если шаг отменён.
func ground_move(body: Node3D, from: Vector3) -> bool:
	var to := body.global_position
	var h0 := ground(from.x, from.z)
	var h1 := ground(to.x, to.z)
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	if dist > 0.001 and h1 - h0 > dist * 1.0 and h1 > 0.5:
		body.global_position = Vector3(from.x, h0, from.z)
		return false
	body.global_position.y = h1
	return true


func in_water(p: Vector3) -> bool:
	return absf(p.x - river_x(p.z)) < RIVER_W / 2.0 + 1.0 and not on_bridge(p.z) and ground(p.x, p.z) < -0.3


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


var _nn: NoiseTexture2D


func _normal_noise() -> NoiseTexture2D:
	if _nn == null:
		_nn = _noise_tex(29, 0.04)
		_nn.as_normal_map = true
		_nn.bump_strength = 6.0
	return _nn


func _road_material() -> ShaderMaterial:
	if road_mat == null:
		road_mat = ShaderMaterial.new()
		road_mat.shader = RoadShader
		road_mat.set_shader_parameter("noise_small", _noise_tex(3, 0.02))
		road_mat.set_shader_parameter("noise_normal", _normal_noise())
	return road_mat


func _build_ground() -> void:
	var gm := ShaderMaterial.new()
	gm.shader = GroundShader
	gm.set_shader_parameter("noise_small", _noise_tex(3, 0.02))
	gm.set_shader_parameter("noise_big", _noise_tex(11, 0.01))
	gm.set_shader_parameter("noise_normal", _normal_noise())
	# ячейки (клеточный шум) — трещины в сухой глине
	var cn := FastNoiseLite.new()
	cn.noise_type = FastNoiseLite.TYPE_CELLULAR
	cn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cn.frequency = 0.03
	cn.seed = 5
	var ct := NoiseTexture2D.new()
	ct.width = 256
	ct.height = 256
	ct.seamless = true
	ct.noise = cn
	ct.normalize = true
	gm.set_shader_parameter("cells", ct)
	# камешки: центры ячеек — круглые пятнышки
	var pn := FastNoiseLite.new()
	pn.noise_type = FastNoiseLite.TYPE_CELLULAR
	pn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	pn.frequency = 0.08
	pn.seed = 9
	var pt := NoiseTexture2D.new()
	pt.width = 256
	pt.height = 256
	pt.seamless = true
	pt.noise = pn
	pt.normalize = true
	gm.set_shader_parameter("pebbles", pt)
	terrain = TerrainScript.new()
	add_child(terrain)
	terrain.build(self, gm)
	for r in roads:
		add_child(Mk.strip(r, 7.5, 0.02, Color.WHITE, 0.95, _road_material()))
	# река
	var centers := PackedVector2Array()
	var z := -400.0
	while z <= WORLD + 400.0:
		centers.append(Vector2(river_x(z), z))
		z += 6.0
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	add_child(Mk.ribbon(centers, RIVER_W + 4.0, terrain.WATER_Y, wm))
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
	var south := ["house", "bank", "house", "hotel", "house"]
	var street_mat := _road_material().duplicate() as ShaderMaterial
	street_mat.set_shader_parameter("ruts", 0.35)
	add_child(Mk.strip([c - Vector2(45, 0), c + Vector2(45, 0)], 19.0, 0.025, Color.WHITE, 0.95, street_mat))
	for i in 5:
		var x := c.x - 30.0 + i * 15.0
		_building(t, north[i], x, c.y - 9.0, 1.0)
		_building(t, south[i], x, c.y + 9.0, -1.0)
	# церковь в конце улицы, дверью к городу
	var church := Models.prop("church", 13.0, "max", PI)
	church.position = Vector3(c.x + 56.0, 0, c.y)
	add_child(church)
	_box_collider(church.position, Models.size_of(church))
	# водонапорная башня, дилижанс, бочки
	var tower := Models.prop("tower", 11.0, "h")
	tower.position = Vector3(c.x - 50.0, 0, c.y - 15.0)
	add_child(tower)
	_box_collider(tower.position, Models.size_of(tower) * Vector3(0.6, 1, 0.6))
	var coach := Models.prop("stagecoach", 6.5, "max", 0.0)
	coach.position = Vector3(c.x + 22.0, 0, c.y + 4.5)
	add_child(coach)
	_box_collider(coach.position, Models.size_of(coach))
	_decorate_town(t, c)
	for i in 6:
		var barrel := Models.group_prop("western", "Barrel", 0.9, "h", rng.randf() * TAU)
		barrel.position = Vector3(c.x + rng.randf_range(-38, 38), 0, c.y + (7.5 if i % 2 == 0 else -7.5))
		add_child(barrel)
		_collider(Vector2(barrel.position.x, barrel.position.z), 0.4, 1.0)


var town_lights: Array = [] # фонари на крыльцах — зажигаются ночью


## Деревянная скамья у стены дома (сиденье на высоте 0,5 м).
func _bench(p: Vector3, yaw: float) -> void:
	var b := Node3D.new()
	b.position = p
	b.rotation.y = yaw
	add_child(b)
	var wood := Color("5e3d22")
	Mk.box(b, Vector3(1.9, 0.07, 0.42), Vector3(0, 0.47, 0.05), wood)
	Mk.box(b, Vector3(1.9, 0.4, 0.06), Vector3(0, 0.75, 0.28), wood)
	for x in [-0.8, 0.8]:
		Mk.box(b, Vector3(0.07, 0.47, 0.38), Vector3(x, 0.235, 0.05), wood.darkened(0.2))


## Объект из набора с материалом-заменой (для моделей без текстур).
func _prop(model: String, size: float, pos: Vector3, yaw := 0.0, fit := "max", tint := Color(0, 0, 0, 0)) -> Node3D:
	var m := Models.prop(model, size, fit, yaw)
	m.position = Vector3(pos.x, ground(pos.x, pos.z) if pos.y == 0.0 else pos.y, pos.z)
	add_child(m)
	if tint.a > 0.0:
		var mat := Mk.mat(tint, 0.85)
		for mi in Models.meshes(m):
			mi.material_override = mat
	return m


## Улица оживает: коновязи с корытами у салуна, лавки и шерифа, фонари на
## крыльцах, бочки, телега, виселица в конце улицы, ветряк с водокачкой.
func _decorate_town(t: Dictionary, c: Vector2) -> void:
	var wood := Color("6b4a2e")
	for i in 3:
		var x := c.x - 30.0 + i * 15.0
		_prop("p_hitch", 2.6, Vector3(x - 2.5, 0, c.y - 6.2), 0.0, "max", wood)
		_collider(Vector2(x - 2.5, c.y - 6.2), 0.3, 1.0)
		_prop("p_trough", 2.0, Vector3(x + 2.6, 0, c.y - 6.4), 0.0, "max", Color("5e4630"))
		_box_collider(Vector3(x + 2.6, 0, c.y - 6.4), Vector3(2.0, 0.9, 1.0))
	# фонари на столбах вдоль улицы (с обеих сторон)
	for i in 4:
		for side in [-1.0, 1.0]:
			var x: float = c.x - 34.0 + i * 22.0 + (6.0 if side > 0.0 else 0.0)
			var z: float = c.y + side * 7.6
			var pole := Mk.box(self, Vector3(0.14, 3.0, 0.14), Vector3(x, 1.5, z), Color("4a3220"))
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			Mk.box(self, Vector3(0.7, 0.1, 0.1), Vector3(x, 2.95, z - side * 0.3), Color("4a3220"))
			var lamp := _prop("p_lantern", 0.45, Vector3(x, 2.25, z - side * 0.6), 0.0, "h")
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.72, 0.4)
			l.omni_range = 13.0
			l.omni_attenuation = 0.9
			l.light_energy = 0.0
			l.visible = false
			l.position = Vector3(x, 2.5, z - side * 0.6)
			add_child(l)
			# пламя: светится само (и даёт ореол через glow)
			var flame := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.07
			fm.height = 0.16
			fm.radial_segments = 6
			fm.rings = 3
			flame.mesh = fm
			var fmat := StandardMaterial3D.new()
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.albedo_color = Color(1.0, 0.75, 0.35)
			fmat.emission_enabled = true
			fmat.emission = Color(1.0, 0.6, 0.25)
			fmat.emission_energy_multiplier = 4.0
			flame.material_override = fmat
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.position = Vector3(x, 2.48, z - side * 0.6)
			flame.visible = false
			add_child(flame)
			town_lights.append([l, flame])
			_collider(Vector2(x, z), 0.15, 3.0)
	_prop("p_barrels", 1.1, Vector3(c.x - 21.0, 0, c.y + 7.0), rng.randf() * TAU, "h")
	_prop("p_barrels", 1.0, Vector3(c.x + 9.0, 0, c.y - 7.2), rng.randf() * TAU, "h")
	var cart := _prop("p_cart", 4.2, Vector3(c.x - 38.0, 0, c.y + 5.5), PI * 0.5 + 0.2)
	_box_collider(cart.position, Models.size_of(cart))
	var gal := _prop("p_gallows", 4.5, Vector3(c.x + 44.0, 0, c.y - 11.0), PI * 0.5, "h")
	_box_collider(gal.position, Models.size_of(gal) * Vector3(1, 1, 1))
	var wm := _prop("p_windmill", 10.0, Vector3(c.x - 62.0, 0, c.y + 16.0), 0.4, "h")
	_box_collider(wm.position, Models.size_of(wm) * Vector3(0.7, 1, 0.7))
	_prop("p_skull", 0.6, Vector3(c.x + 47.0, 0.0, c.y + 8.0), 1.0)
	# загон для коров за городом (с воротами к городу)
	var x0 := c.x - 28.0
	var x1 := c.x + 28.0
	var z0 := c.y - 64.0
	var z1 := c.y - 40.0
	var x := x0
	while x < x1 - 0.1:
		_prop("p_fence", 4.0, Vector3(x + 2.0, 0, z0), PI * 0.5)
		if absf(x + 2.0 - c.x) > 3.0: # ворота посередине ближней стороны
			_prop("p_fence", 4.0, Vector3(x + 2.0, 0, z1), PI * 0.5)
		x += 4.0
	_box_collider(Vector3(c.x, 0, z0), Vector3(56.0, 1.4, 0.3))
	_box_collider(Vector3(c.x - 16.0, 0, z1), Vector3(24.0, 1.4, 0.3))
	_box_collider(Vector3(c.x + 16.0, 0, z1), Vector3(24.0, 1.4, 0.3))
	_box_collider(Vector3(x0, 0, (z0 + z1) / 2.0), Vector3(0.3, 1.4, 24.0))
	_box_collider(Vector3(x1, 0, (z0 + z1) / 2.0), Vector3(0.3, 1.4, 24.0))
	var z := z0
	while z < z1 - 0.1:
		_prop("p_fence", 4.0, Vector3(x0, 0, z + 2.0))
		_prop("p_fence", 4.0, Vector3(x1, 0, z + 2.0))
		z += 4.0


## Здание вдоль улицы. edge — z края улицы; face: +1 — фасад смотрит на юг (+Z).
func _building(t: Dictionary, type: String, x: float, edge: float, face: float) -> void:
	var spec: Array = BUILD[type]
	var model := Models.prop(spec[0], spec[1], "max", spec[2], spec[3])
	var sz := Models.size_of(model)
	var cz := edge - face * (sz.z / 2.0 + 0.5)
	var b := Node3D.new()
	b.position = Vector3(x, 0, cz)
	b.rotation.y = 0.0 if face > 0.0 else PI
	add_child(b)
	b.add_child(model)
	var nm: String = NAMES[type]
	if nm != "" and spec[4] > 0.0:
		var hy: float = sz.y * spec[4]
		var w := 1.2 + nm.length() * 0.62
		Mk.box(b, Vector3(w, 1.1, 0.1), Vector3(0, hy, sz.z / 2.0 + 0.12), Color("e9d6ae"))
		Mk.label(b, nm, Vector3(0, hy, sz.z / 2.0 + 0.2), 80, Color("3a2412"))
	if type == "sheriff":
		var board := Models.prop("wanted", 2.6, "h", -PI / 2.0)
		board.position = Vector3(3.2, 0, sz.z / 2.0 + 1.8)
		b.add_child(board)
	_box_collider(Vector3(x, 0, cz), sz)
	var out := Vector3(0, 0, face) # наружу, к улице
	var door := Vector3(x, 0, cz) + out * (sz.z / 2.0 + 1.5)
	var data := {"type": type, "town": t, "door": door, "out": out, "rect": Rect2(x - sz.x / 2.0, cz - sz.z / 2.0, sz.x, sz.z)}
	t["buildings"].append(data)
	buildings.append(data)


func _box_collider(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.5), maxf(size.y, 0.5), maxf(size.z, 0.5))
	cs.shape = shape
	cs.position = pos + Vector3(0, size.y / 2.0, 0)
	_static.add_child(cs)


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
	# кактусы и камни из скачанных наборов, рисуются через MultiMesh
	var cactus_groups := []
	for n in ["Cactus1", "Cactus2", "Cactus3", "Cactus4"]:
		var g := Models.group("western", n, 1.0, "h")
		if not g.is_empty():
			cactus_groups.append(g)
	var rock_groups := []
	for p in Models.parts("rocks", ""):
		var g := Models.group("rocks", p["name"], 1.0)
		if not g.is_empty():
			rock_groups.append(g)
	var cactus_at := []
	for i in cactus_groups.size():
		cactus_at.append([])
	var rock_at := []
	for i in rock_groups.size():
		rock_at.append([])
	for i in 320:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if not _free_spot(p, 6.0):
			continue
		var h := rng.randf_range(2.8, 5.5)
		var gi := rng.randi_range(0, cactus_groups.size() - 1)
		cactus_at[gi].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * h), Vector3(p.x, ground(p.x, p.y) - 0.1, p.y)))
		_collider(p, 0.12 * h, h)
		obstacles.append([p, 0.15 * h])
	for i in 180:
		var r := rng.randf_range(1.2, 5.0)
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if not _free_spot(p, r + 3.0):
			continue
		var gi := rng.randi_range(0, rock_groups.size() - 1)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r * 2.2, r * 2.2 * rng.randf_range(0.7, 1.1), r * 2.2))
		rock_at[gi].append(Transform3D(b, Vector3(p.x, ground(p.x, p.y) - r * 0.25, p.y)))
		_collider(p, r * 0.95, r * 1.5)
		obstacles.append([p, r * 1.1])
	# сухие деревья и коровьи черепа
	for i in 70:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if not _free_spot(p, 5.0) or (terrain and terrain.normal_at(p.x, p.y).y < 0.9):
			continue
		var tree := _prop("p_deadtree" if rng.randf() < 0.6 else "p_deadtree2", rng.randf_range(4.0, 7.0), Vector3(p.x, 0, p.y), rng.randf() * TAU)
		tree.position.y -= 0.15
		_collider(p, 0.35, 4.0)
		obstacles.append([p, 1.0])
	for i in 50:
		var p := Vector2(rng.randf_range(0, WORLD), rng.randf_range(0, WORLD))
		if _free_spot(p, 2.0):
			var sk := _prop("p_skull", rng.randf_range(0.45, 0.65), Vector3(p.x, 0, p.y), rng.randf() * TAU)
			sk.rotation.z = rng.randf_range(-0.3, 0.3)
	for i in cactus_groups.size():
		_mm_group(cactus_groups[i], cactus_at[i], true, Color("55703f"))
	for i in rock_groups.size():
		_mm_group(rock_groups[i], rock_at[i], true)

	# трава и сухие кусты (только вид, без столкновений)
	var veg := VegScript.new()
	add_child(veg)
	veg.build(self)


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


## MultiMesh для каждой части группы; materials берутся из самой модели.
func _mm_group(parts: Array, placements: Array, shadows: bool, color_override := Color(0, 0, 0, 0)) -> void:
	if placements.is_empty():
		return
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part["mesh"]
		mm.instance_count = placements.size()
		for i in placements.size():
			mm.set_instance_transform(i, placements[i] * part["xf"])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if color_override.a > 0.0:
			mmi.material_override = Mk.mat(color_override, 0.85)
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _collider(p: Vector2, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	cs.shape = s
	cs.position = Vector3(p.x, ground(p.x, p.y) + h / 2.0, p.y)
	_static.add_child(cs)


func _build_mesas() -> void:
	# горы по краю карты (из набора «Low Poly Western») и невидимые стены
	var groups := []
	for n in ["Mountain", "Mountain2", "Mountain3", "Mountain4"]:
		var g := Models.group("western", n, 1.0)
		if not g.is_empty():
			groups.append(g)
	var at := []
	for g in groups:
		at.append([])
	for i in 80:
		var side := i % 4
		var t := rng.randf_range(-150, WORLD + 150)
		var off := rng.randf_range(50, 190)
		var p := Vector2(t, -off)
		match side:
			1: p = Vector2(t, WORLD + off)
			2: p = Vector2(-off, t)
			3: p = Vector2(WORLD + off, t)
		var w := rng.randf_range(70, 160)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, w * rng.randf_range(0.6, 1.2), w))
		at[i % groups.size()].append(Transform3D(b, Vector3(p.x, ground(p.x, p.y) - 2.0, p.y)))
	for i in groups.size():
		_mm_group(groups[i], at[i], false)
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
		n.tint = BANDIT_TINTS.pick_random()
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
	player.global_position = Vector3(p.x, ground(p.x, p.z), p.z)
	var hp := p + Vector3(4, 0, 2)
	horse.global_position = Vector3(hp.x, ground(hp.x, hp.z), hp.z)
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
	return ray(a, b, 1 | 16).is_empty()


func alert_town(p: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and n.kind == "folk" and n.global_position.distance_to(p) < 50.0:
			n.flee = 6.0
	# из окна кричит горожанка
	if town_at(p) != null:
		var w := p + Vector3(randf_range(-14, 14), 2.5, randf_range(-14, 14))
		Game.vo("townf", 3 if randf() < 0.4 else 4, w, "townf", 7.0)


# ---------- животные ----------
func _open_spot(pad: float, town_pad := 140.0) -> Vector3:
	for attempt in 60:
		var p := Vector2(rng.randf_range(60, WORLD - 60), rng.randf_range(60, WORLD - 60))
		if _free_spot(p, pad, town_pad) and ground(p.x, p.y) < 14.0:
			return Vector3(p.x, ground(p.x, p.y), p.y)
	return Vector3(500, 0, 500)


func _spawn_animal(kind: String, p: Vector3) -> Node3D:
	var a := AnimalScript.new()
	a.setup(kind, Vector3(p.x, ground(p.x, p.z), p.z))
	add_child(a)
	return a


func _spawn_animals() -> void:
	for herd in 6: # стада вилорогов
		var c := _open_spot(20.0)
		var lead: Node3D = null
		for i in randi_range(3, 5):
			var a := _spawn_animal("pronghorn", c + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
			if lead == null:
				lead = a
			else:
				a.leader = lead
	for pack in 4: # стаи койотов
		var c := _open_spot(20.0)
		var lead: Node3D = null
		for i in 3:
			var a := _spawn_animal("coyote", c + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
			if lead == null:
				lead = a
			else:
				a.leader = lead
	for i in 14:
		_spawn_animal("hare", _open_spot(5.0, 90.0))
	for t in towns: # коровы пасутся за городом
		var c: Vector2 = t["pos"]
		for i in 5:
			_spawn_animal("cow", Vector3(c.x + randf_range(-20, 20), 0, c.y - 52.0 + randf_range(-6, 6)))
	for i in 4: # орлы в небе
		var e := EagleScript.new()
		e.center = Vector3(rng.randf_range(150, 850), 0, rng.randf_range(150, 850))
		e.radius = rng.randf_range(40, 90)
		e.height = rng.randf_range(40, 70)
		add_child(e)


func scare_animals(p: Vector3, radius: float) -> void:
	for a in get_tree().get_nodes_in_group("animals"):
		if a.global_position.distance_to(p) < radius:
			a.scare()
	# свой конь (не под седлом) пугается выстрелов вблизи
	if not player.mounted and horse.global_position.distance_to(p) < 25.0 and randf() < 0.6:
		horse.spook(p)


func drop_pelt(p: Vector3, money: int, animal_name: String) -> Node3D:
	var l := LootScript.new()
	l.position = p
	l.money = money
	l.ammo = 0
	l.title = "Шкура " + animal_name
	add_child(l)
	return l


func drop_loot(p: Vector3) -> void:
	var l := LootScript.new()
	l.position = p + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	l.position.y = ground(l.position.x, l.position.z)
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
	_update_audio(delta)
	_update_tumbleweeds(delta)
	player.lantern.light_energy = Game.darkness() * 1.1
	# фонари на улицах горят ночью; включены только ближние — так дешевле
	var dk_l := Game.darkness()
	for e in town_lights:
		var l: OmniLight3D = e[0]
		var on := dk_l > 0.35 and l.global_position.distance_squared_to(player.global_position) < 70.0 * 70.0
		l.visible = on
		l.light_energy = dk_l * 2.6
		e[1].visible = dk_l > 0.35


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
		p.y = ground(p.x, p.z)
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


# ---------- звук окружения ----------
func _setup_audio() -> void:
	_river_snd = AudioStreamPlayer3D.new()
	_river_snd.stream = Game.sfx("river")
	_river_snd.unit_size = 10.0
	_river_snd.max_distance = 90.0
	add_child(_river_snd)
	if _river_snd.stream:
		_river_snd.play()
	for b in buildings:
		if b["type"] == "saloon":
			var a := AudioStreamPlayer3D.new()
			a.stream = Game.sfx("saloon")
			a.unit_size = 7.0
			a.max_distance = 70.0
			a.position = b["door"] + Vector3(0, 1.5, 0) - b["out"] * 3.0
			add_child(a)
			if a.stream:
				a.play()


var _chatter_t := 15.0
var _wade_t := 0.0
var _music_town := 0.0
var _music_night := 0.0


func _update_audio(delta: float) -> void:
	var p := player
	var dk := Game.darkness()
	var pp := p.global_position
	if _river_snd and _river_snd.stream:
		_river_snd.global_position = Vector3(river_x(pp.z), 0.3, pp.z)
	# шаги и копыта героя
	var spd := Vector2(p.move_vel.x, p.move_vel.z).length()
	var riding: bool = p.mounted and p.mount_dir == 0 and not p.dead
	var walking: bool = not p.mounted and not p.dead and spd > 0.5
	# по доскам (крыльцо, мост, тротуар — герой выше земли) — деревянные шаги
	var on_wood: bool = walking and (pp.y - ground(pp.x, pp.z) > 0.12 or (on_bridge(pp.z) and absf(pp.x - river_x(pp.z)) < RIVER_W / 2.0 + 5.0))
	var wet: bool = in_water(pp)
	var sv := clampf(spd / 4.6, 0.0, 1.0) * 0.55 if walking else 0.0
	var sp := clampf(0.8 + spd * 0.06, 0.8, 1.2)
	Game.loop_set("steps", 0.0 if on_wood else sv * (0.5 if wet else 1.0), sp)
	Game.loop_set("steps_wood", sv * 1.1 if on_wood else 0.0, sp)
	if wet and walking:
		_wade_t -= delta
		if _wade_t <= 0.0:
			_wade_t = clampf(1.4 / spd, 0.25, 0.7)
			fx.splash(Vector3(pp.x, -0.45, pp.z))
			Game.play_at("splash", pp, -12.0, randf_range(0.9, 1.3), 5.0)
	var gallop := clampf((spd - 5.0) / 3.0, 0.0, 1.0) if riding else 0.0
	var walk := clampf(spd / 2.0, 0.0, 1.0) * (1.0 - gallop) if riding else 0.0
	Game.loop_set("hoof_walk", walk * 0.6, clampf(spd / 1.8, 0.7, 1.6))
	Game.loop_set("gallop", gallop * 0.7, clampf(spd / 13.0, 0.8, 1.25))
	# окружение: ветер днём, сверчки ночью
	var indoor: bool = interior != null and interior.inside
	var outk := 0.15 if indoor else 1.0 # в зале улица еле слышна
	Game.loop_set("wind", lerpf(0.32, 0.15, dk) * (1.3 if town_at(pp) == null else 0.7) * outk)
	Game.loop_set("crickets", dk * 0.45 * outk)
	# в городе днём слышны голоса с крылец и из окон
	_chatter_t -= delta
	if _chatter_t <= 0.0:
		_chatter_t = randf_range(25.0, 50.0)
		if dk < 0.5 and Game.wanted == 0 and not p.dead and town_at(pp) != null:
			var w := pp + Vector3(randf_range(-12, 12), 2.0, randf_range(-12, 12))
			Game.vo("townf", 1 if randf() < 0.5 else 2, w, "townf", 20.0, -3.0)
	# музыка: спокойная в поездках, напряжённая в перестрелке
	var fight := false
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and n.aggro and n.kind != "folk" and n.global_position.distance_to(pp) < 80.0 and (n.kind in ["bandit", "leader"] or Game.wanted > 0):
			fight = true
			break
	_music_combat = move_toward(_music_combat, 0.5 if fight else 0.0, delta * (0.8 if fight else 0.15))
	# мирная музыка зависит от места и времени: город днём, ночь, дорога
	var in_town: bool = town_at(pp) != null
	var night := dk > 0.6
	var calm: bool = not fight and not p.dead and not (interior != null and interior.inside)
	_music_explore = move_toward(_music_explore, 0.28 if calm and not in_town and not night else 0.0, delta * 0.12)
	_music_town = move_toward(_music_town, 0.24 if calm and in_town and not night else 0.0, delta * 0.12)
	_music_night = move_toward(_music_night, 0.3 if calm and night else 0.0, delta * 0.1)
	Game.loop_set("music_combat", _music_combat)
	Game.loop_set("music_explore", _music_explore)
	Game.loop_set("music_town", _music_town)
	Game.loop_set("music_night", _music_night)


# ---------- перекати-поле ----------
const WIND := Vector3(0.94, 0, 0.34) # ветер дует с запада
var _tumbles: Array = [] # [узел, скорость, фаза прыжка]
var _tumble_mesh: Array = []


func _make_tumbleweed() -> Node3D:
	var root := Node3D.new()
	var m := Mk.mat(Color("7a5e3a"), 1.0)
	for i in 7:
		var t := TorusMesh.new()
		t.inner_radius = randf_range(0.18, 0.36)
		t.outer_radius = t.inner_radius + 0.06
		t.rings = 10
		t.ring_segments = 3
		t.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.rotation = Vector3(randf() * PI, randf() * PI, randf() * PI)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	root.scale = Vector3.ONE * randf_range(0.8, 1.3)
	return root


var _gust_t := 20.0


func _update_tumbleweeds(delta: float) -> void:
	var pp := player.global_position
	# пыльные вихри в пустыне днём
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = randf_range(25.0, 60.0)
		if town_at(pp) == null and Game.darkness() < 0.5:
			var gp := pp - WIND * randf_range(25.0, 40.0) + WIND.cross(Vector3.UP) * randf_range(-15.0, 15.0)
			gp.y = ground(gp.x, gp.z) + 0.5
			fx.dust_gust(gp, WIND)
	var want := 0 if town_at(pp) != null or Game.darkness() > 0.7 else 3
	# новые появляются с наветренной стороны
	if _tumbles.size() < want and randf() < delta * 0.25:
		var side := WIND.rotated(Vector3.UP, randf_range(-0.9, 0.9))
		var sp := pp - side * randf_range(45.0, 70.0)
		if not in_water(sp):
			var t := _make_tumbleweed()
			add_child(t)
			t.global_position = Vector3(sp.x, ground(sp.x, sp.z) + 0.35, sp.z)
			_tumbles.append([t, randf_range(2.5, 5.0), randf() * TAU])
	for i in range(_tumbles.size() - 1, -1, -1):
		var e: Array = _tumbles[i]
		var t: Node3D = e[0]
		var v: float = e[1] * (0.75 + 0.35 * sin(Time.get_ticks_msec() * 0.0007 + e[2]))
		var pos := t.global_position + WIND * v * delta
		e[2] += delta * v * 0.9
		var hop := absf(sin(e[2])) * 0.45
		pos.y = ground(pos.x, pos.z) + 0.35 * t.scale.x + hop
		t.global_position = pos
		t.rotate(WIND.cross(Vector3.UP).normalized(), -v * delta / 0.35)
		if pos.distance_to(pp) > 95.0 or in_water(pos):
			t.queue_free()
			_tumbles.remove_at(i)
