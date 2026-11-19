extends Node3D
## Бандитский лагерь: палатки, ящики и костёр, который светит ночью.

var camp_name := ""
var cleared := false
var timer := 0.0
var known := false
var seed_v := 0
var flame: MeshInstance3D
var light: OmniLight3D
var t := 0.0


func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var patch := Mk.cyl(self, 13.0, 13.0, 0.02, Vector3(0, 0.012, 0), Color("8a6a44"), 18)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for k in 3:
		var a := k * 2.1 + r.randf() * 0.5
		var pos := Vector3(cos(a), 0, sin(a)) * 8.5
		var pm := PrismMesh.new()
		pm.size = Vector3(3.4, 2.3, 4.0)
		Mk.add(self, pm, pos + Vector3(0, 1.15, 0), Color("cbb894"), Vector3(0, -a, 0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.0, 2.0, 3.8)
		cs.shape = bs
		cs.position = pos + Vector3(0, 1.0, 0)
		cs.rotation.y = -a
		body.add_child(cs)
	for k in 2:
		Mk.cyl(self, 0.12, 0.12, 1.4, Vector3(0, 0.15, 0), Color("4a2e18"), 6, Vector3(0, k * PI / 2.0, PI / 2.0))
	for k in 8:
		var a := k / 8.0 * TAU
		Mk.sphere(self, 0.18, Vector3(cos(a) * 0.9, 0.1, sin(a) * 0.9), Color("666060"))
	# фургон и припасы банды
	var wa := r.randf() * TAU
	var wagon := Models.prop("wagon", 5.5, "max", r.randf() * TAU)
	wagon.position = Vector3(cos(wa), 0, sin(wa)) * 11.5
	add_child(wagon)
	var ws := Models.size_of(wagon)
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(maxf(ws.x, ws.z) * 0.7, ws.y, maxf(ws.x, ws.z) * 0.7)
	wcs.shape = wbs
	wcs.position = wagon.position + Vector3(0, ws.y / 2.0, 0)
	body.add_child(wcs)
	var loot_names := ["Box", "Box2", "Box3", "Barrel", "BigDynamite", "Box"]
	for k in loot_names.size():
		var a := r.randf() * TAU
		var sz := 0.9 if loot_names[k] != "BigDynamite" else 0.7
		var item := Models.group_prop("western", loot_names[k], sz, "max", r.randf() * TAU)
		item.position = Vector3(cos(a), 0, sin(a)) * r.randf_range(4.0, 6.0)
		add_child(item)
	flame = Mk.sphere(self, 0.32, Vector3(0, 0.55, 0), Color("ff8a2a"))
	flame.material_override = Mk.mat(Color("ff8a2a"), 1.0, 4.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.position = Vector3(0, 1.4, 0)
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 18.0
	add_child(light)


func _process(delta: float) -> void:
	t += delta
	if cleared:
		return
	flame.scale = Vector3(1.0, 1.5 + sin(t * 13.0) * 0.25, 1.0) * (0.9 + 0.1 * sin(t * 21.0))
	light.light_energy = (0.3 + Game.darkness() * 2.5) * (0.9 + 0.1 * sin(t * 17.0))


func set_cleared(v: bool) -> void:
	cleared = v
	timer = 0.0
	flame.visible = not v
	light.visible = not v
