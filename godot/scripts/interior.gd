extends Node3D
## Зал салуна «Последний Глоток»: модель «Saloon Modular Interior» (lollidrops,
## CC BY 4.0) стоит отдельно от карты. Вход — через дверь салуна на улице,
## выход — через проём в передней стене. Внутри бармен за стойкой (с ним
## разговор открывает меню салуна), посетители за столами, тапёр у пианино.

const SIZE := 20.0 # длина зала, м
const ORIGIN := Vector3(-820.0, 0.0, 480.0)

var world: Node3D
var rect: Rect2 # пол зала в мировых XZ
var bartender: Node3D
var building: Dictionary # здание салуна, откуда вошли
var inside := false
var _static: StaticBody3D
var _music: AudioStreamPlayer
var _vol := 0.0


func build(w: Node3D) -> void:
	world = w
	position = ORIGIN
	var m := Models.prop("saloon_int", SIZE, "max")
	add_child(m)
	var sz := Models.size_of(m)
	rect = Rect2(ORIGIN.x - sz.x / 2.0, ORIGIN.z - sz.z / 2.0, sz.x, sz.z)
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	add_child(_static)
	# стены (модель без передней стены — делаем её сами, с проёмом-входом)
	_wall(Vector3(-6.45, 0, 0), Vector3(0.4, 7.2, 20.2))
	_wall(Vector3(6.25, 0, 0), Vector3(0.4, 7.2, 20.2))
	_wall(Vector3(0, 0, -10.0), Vector3(13.0, 7.2, 0.4))
	_wall(Vector3(0, 0, -6.4), Vector3(13.0, 3.6, 0.4)) # перегородка подсобки
	var front := Color("5a3a22")
	for side in [-1.0, 1.0]:
		var bx := Mk.box(self, Vector3(5.4, 3.6, 0.3), Vector3(side * 3.7, 1.8, 10.05), front)
		bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_wall(Vector3(side * 3.7, 0, 10.05), Vector3(5.4, 3.6, 0.4))
	Mk.box(self, Vector3(12.9, 3.6, 0.3), Vector3(0, 5.4, 10.05), front)
	Mk.box(self, Vector3(13.2, 0.3, 20.6), Vector3(0, 7.45, 0), Color("3a2414")) # крыша
	Mk.box(self, Vector3(2.0, 0.6, 0.3), Vector3(0, 3.3, 10.05), front)
	# дверной проём светится улицей
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 3.0)
	glow.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.9, 0.7)
	glow.material_override = gm
	glow.position = Vector3(0, 1.5, 10.25)
	glow.rotation.y = PI
	add_child(glow)
	_wall(Vector3(0, 0, 10.6), Vector3(2.2, 3.6, 0.4)) # за проёмом — не выйти в пустоту
	# стойка, лестница, столы
	_wall(Vector3(4.15, 0, -1.85), Vector3(0.9, 1.1, 5.5))
	_wall(Vector3(5.05, 0, 2.25), Vector3(2.7, 1.1, 2.7))
	_wall(Vector3(-5.4, 0, 0.75), Vector3(1.8, 3.6, 4.4))
	for t in [Vector3(-2.25, 0, 2.75), Vector3(2.85, 0, 4.75), Vector3(4.55, 0, 8.15), Vector3(-4.05, 0, 8.05)]:
		_wall(t, Vector3(1.1, 0.9, 1.1))
	# пианино у левой стены
	var piano := Models.prop("p_piano", 1.6, "max", PI * 0.5)
	piano.position = Vector3(-5.6, 0, -3.6)
	add_child(piano)
	for mi in Models.meshes(piano):
		mi.material_override = Mk.mat(Color("3a2214"), 0.5)
	_wall(Vector3(-5.6, 0, -3.6), Vector3(0.8, 1.4, 1.6))
	# люстры: тёплый свет
	for lp in [Vector3(-2.5, 3.2, 3.0), Vector3(2.0, 3.2, 3.0), Vector3(-2.0, 3.2, -3.0), Vector3(1.5, 3.2, 7.5)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.45)
		l.light_energy = 2.0
		l.omni_range = 8.5
		l.omni_attenuation = 0.8
		l.position = lp
		add_child(l)
	_music = AudioStreamPlayer.new()
	_music.stream = Game.sfx("saloon")
	_music.volume_db = -60.0
	add_child(_music)


func _wall(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = center + Vector3(0, size.y / 2.0, 0)
	_static.add_child(cs)


## Люди в зале: бармен за стойкой, посетители за столами, тапёр.
func populate() -> void:
	bartender = _person(Vector3(5.1, 0, -1.2), PI * 0.5, "")
	# сидящие: [позиция стула, куда смотрят (стол)]
	var seats := [
		[Vector3(-2.7, 0, 1.75), Vector3(-2.25, 0, 2.75)],
		[Vector3(-1.4, 0, 2.3), Vector3(-2.25, 0, 2.75)],
		[Vector3(2.3, 0, 3.9), Vector3(2.85, 0, 4.75)],
		[Vector3(3.7, 0, 4.4), Vector3(2.85, 0, 4.75)],
		[Vector3(-4.6, 0, 7.1), Vector3(-4.05, 0, 8.05)],
		[Vector3(4.0, 0, 7.3), Vector3(4.55, 0, 8.15)],
	]
	for s in seats:
		var to: Vector3 = s[1] - s[0]
		_person(s[0], atan2(-to.x, -to.z), "sit")
	_person(Vector3(-4.85, 0, -3.6), PI * 0.5, "sit") # тапёр


func _person(local: Vector3, yaw: float, mode: String) -> Node3D:
	var n = world.spawn_npc("folk", to_global(local))
	n.yaw = yaw
	n.home = n.global_position
	n.pose_mode = mode if mode != "" else "stand"
	n.indoor = true
	n.rebuild()
	n.model.rotation.y = yaw
	return n


func contains(x: float, z: float) -> bool:
	return rect.has_point(Vector2(x, z))


## Вошли с улицы.
func enter(b: Dictionary) -> void:
	building = b
	inside = true
	var p = world.player
	p.global_position = to_global(Vector3(0, 0, 8.4))
	p.yaw = 0.0
	p.face_yaw = 0.0
	p.model.rotation.y = 0.0
	p.snap_camera()


## Вышли на улицу — к двери того же салуна.
func leave() -> void:
	inside = false
	var p = world.player
	var out: Vector3 = building["out"]
	p.global_position = building["door"] + out * 2.2
	p.global_position.y = world.ground(p.global_position.x, p.global_position.z)
	p.yaw = atan2(-out.x, -out.z)
	p.face_yaw = p.yaw
	p.model.rotation.y = p.yaw
	p.snap_camera()


func near_exit(p: Vector3) -> bool:
	var l := to_local(p)
	return inside and absf(l.x) < 1.6 and l.z > 8.9


func near_bartender(p: Vector3) -> bool:
	return inside and bartender and p.distance_to(bartender.global_position) < 2.6


func _process(delta: float) -> void:
	if _music.stream == null:
		return
	_vol = move_toward(_vol, 1.0 if inside else 0.0, delta * 1.5)
	if _vol > 0.001:
		if not _music.playing:
			_music.play()
		_music.volume_db = linear_to_db(_vol * 0.8)
	elif _music.playing:
		_music.stop()
