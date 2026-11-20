extends Node3D
## Трассеры, вспышки выстрелов, пороховой дым, искры рикошета, брызги воды,
## кровь и пыль из-под копыт.

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


var _puff_mat: StandardMaterial3D


## Мягкий круглый «клочок» дыма/пыли — общий материал для всех облачков.
func _puff_material() -> StandardMaterial3D:
	if _puff_mat:
		return _puff_mat
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puff_mat = m
	return m


func _puffs(col: Color, n: int, life: float, size: float, grow: float) -> CPUParticles3D:
	var cp := CPUParticles3D.new()
	cp.amount = n
	cp.lifetime = life
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = _puff_material()
	cp.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	cp.color_ramp = ramp
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, grow))
	cp.scale_amount_curve = c
	cp.angle_min = 0.0
	cp.angle_max = 360.0
	return cp


## Пороховой дым из ствола: облачко вылетает вперёд и медленно поднимается.
func smoke(p: Vector3, dir: Vector3) -> void:
	var cp := _puffs(Color(0.82, 0.8, 0.76, 0.55), 7, 1.6, 0.35, 2.6)
	cp.one_shot = true
	cp.explosiveness = 0.9
	cp.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	cp.spread = 18.0
	cp.initial_velocity_min = 0.8
	cp.initial_velocity_max = 2.2
	cp.damping_min = 2.0
	cp.damping_max = 3.0
	cp.gravity = Vector3(0.25, 0.35, 0)
	add_child(cp)
	cp.global_position = p
	cp.emitting = true
	get_tree().create_timer(2.5, false).timeout.connect(cp.queue_free)


## Искры при попадании в камень, дерево или металл.
func sparks(p: Vector3) -> void:
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.amount = 10
	cp.lifetime = 0.35
	cp.explosiveness = 1.0
	cp.direction = Vector3.UP
	cp.spread = 80.0
	cp.initial_velocity_min = 3.0
	cp.initial_velocity_max = 7.0
	cp.gravity = Vector3(0, -12.0, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.015, 0.015, 0.08)
	bm.material = Mk.mat(Color(1.0, 0.75, 0.3), 0.5, 4.0)
	cp.mesh = bm
	cp.particle_flag_align_y = true
	add_child(cp)
	cp.global_position = p
	cp.emitting = true
	get_tree().create_timer(1.0, false).timeout.connect(cp.queue_free)
	# облачко пыли от удара
	var d := _puffs(Color(0.72, 0.62, 0.48, 0.45), 4, 0.9, 0.3, 2.0)
	d.one_shot = true
	d.explosiveness = 1.0
	d.direction = Vector3.UP
	d.spread = 50.0
	d.initial_velocity_min = 0.4
	d.initial_velocity_max = 1.2
	d.gravity = Vector3(0, 0.2, 0)
	add_child(d)
	d.global_position = p
	d.emitting = true
	get_tree().create_timer(1.5, false).timeout.connect(d.queue_free)


## Брызги воды (пуля в реку, копыта или шаги по воде).
func splash(p: Vector3, big := false) -> void:
	burst(p, Color(0.75, 0.85, 0.95), 18 if big else 10, 4.5 if big else 3.0)


## Пыль из-под копыт или ног: постоянный излучатель, включается по скорости.
func trail() -> CPUParticles3D:
	var cp := _puffs(Color(0.76, 0.66, 0.5, 0.38), 18, 1.4, 0.7, 3.0)
	cp.emitting = false
	cp.local_coords = false
	cp.direction = Vector3.UP
	cp.spread = 60.0
	cp.initial_velocity_min = 0.3
	cp.initial_velocity_max = 1.2
	cp.damping_min = 1.0
	cp.damping_max = 2.0
	cp.gravity = Vector3(0.3, 0.15, 0)
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	cp.emission_box_extents = Vector3(0.4, 0.05, 0.9)
	return cp


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
