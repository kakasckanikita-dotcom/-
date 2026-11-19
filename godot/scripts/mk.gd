class_name Mk
extends RefCounted
## Помощники для построения геометрии из примитивов: материалы (с кэшем),
## коробки, цилиндры, сферы, надписи и полосы (дороги, река).

static var _mats := {}


static func mat(c: Color, rough := 0.9, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), rough, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func add(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation = rot
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add(parent, m, pos, c, rot)


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, segs := 8, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return add(parent, m, pos, c, rot)


static func sphere(parent: Node3D, r: float, pos: Vector3, c: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 6
	var mi := add(parent, m, pos, c)
	mi.scale = scale
	return mi


static func capsule(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 2
	return add(parent, m, pos, c, rot)


static func label(parent: Node3D, text: String, pos: Vector3, px: int, c: Color, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.pixel_size = 0.01
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	parent.add_child(l)
	return l


## Плоская полоса по точкам (дорога, река) на высоте y.
static func strip(points: Array, width: float, y: float, c: Color, rough := 0.95) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * width / 2.0
		# продлеваем отрезок на полширины, чтобы стыки не зияли
		var a2 := a - d * width * 0.5
		var b2 := b + d * width * 0.5
		var v := [Vector3(a2.x + n.x, y, a2.y + n.y), Vector3(a2.x - n.x, y, a2.y - n.y), Vector3(b2.x - n.x, y, b2.y - n.y), Vector3(b2.x + n.x, y, b2.y + n.y)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat(c, rough)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Гладкая полоса с переменным центром (река): centers — точки по оси.
static func ribbon(centers: PackedVector2Array, width: float, y: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in centers.size() - 1:
		var a := centers[i]
		var b := centers[i + 1]
		var v := [Vector3(a.x - width / 2.0, y, a.y), Vector3(a.x + width / 2.0, y, a.y), Vector3(b.x + width / 2.0, y, b.y), Vector3(b.x - width / 2.0, y, b.y)]
		var uv := [Vector2(0, a.y / 10.0), Vector2(1, a.y / 10.0), Vector2(1, b.y / 10.0), Vector2(0, b.y / 10.0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
