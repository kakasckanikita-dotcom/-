extends Node3D
## Трассеры, вспышки выстрелов и брызги (кровь, пыль).

var tracers: Array = [] # [меш, оставшееся время]


func tracer(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.2:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, len)
	m.mesh = bm
	m.material_override = Mk.mat(Color(1.0, 0.85, 0.45), 0.5, 3.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = (a + b) / 2.0
	var up := Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	m.look_at(b, up)
	tracers.append([m, 0.12])


func muzzle(p: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 3.0
	l.omni_range = 6.0
	add_child(l)
	l.global_position = p
	tracers.append([l, 0.06])


func burst(p: Vector3, col: Color, n: int, spd := 3.0) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = n
	cp.lifetime = 0.6
	cp.explosiveness = 1.0
	cp.direction = Vector3.UP
	cp.spread = 70.0
	cp.initial_velocity_min = spd * 0.4
	cp.initial_velocity_max = spd
	cp.gravity = Vector3(0, -9.8, 0)
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = Mk.mat(col)
	cp.mesh = sm
	add_child(cp)
	cp.global_position = p
	cp.emitting = true
	get_tree().create_timer(1.5, false).timeout.connect(cp.queue_free)


func blood(p: Vector3) -> void:
	burst(p, Color("8a1a10"), 14)


func dust(p: Vector3) -> void:
	burst(p, Color("b89a70"), 8, 2.0)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	for i in range(tracers.size() - 1, -1, -1):
		var tr: Array = tracers[i]
		tr[1] -= real
		if tr[1] <= 0.0:
			tr[0].queue_free()
			tracers.remove_at(i)
		elif tr[0] is MeshInstance3D:
			var k: float = tr[1] / 0.12
			tr[0].scale = Vector3(k, k, 1.0)
