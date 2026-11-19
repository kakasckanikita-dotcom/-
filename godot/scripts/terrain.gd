extends Node3D
## Рельеф Территории Мескаль: пологие холмы и ступенчатые столовые горы,
## русло реки. Города, лагеря, дороги и мосты остаются ровными (высота 0).
## Карта высот считается один раз и кэшируется в user://, поэтому на телефоне
## повторные запуски быстрые. height(x, z) — высота земли в любой точке.

const STEP := 6.0 # шаг сетки, м
const MIN := -240.0 # сетка покрывает мир с запасом для горизонта
const MAX := 1240.0
const CHUNKS := 8
const CACHE := "user://terrain_v2.bin"
const RIVER_BED := -1.5 # глубина русла
const WATER_Y := -0.45

var n := 0 # точек на сторону
var heights := PackedFloat32Array()
var world: Node3D
var material: Material


func build(w: Node3D, mat: Material) -> void:
	world = w
	material = mat
	n = int((MAX - MIN) / STEP) + 1
	if not _load_cache():
		_compute()
		_save_cache()
	_build_meshes()
	_build_collision()


func _load_cache() -> bool:
	if not FileAccess.file_exists(CACHE):
		return false
	var f := FileAccess.open(CACHE, FileAccess.READ)
	if f == null:
		return false
	var buf := f.get_buffer(f.get_length())
	var arr := buf.to_float32_array()
	if arr.size() != n * n:
		return false
	heights = arr
	return true


func _save_cache() -> void:
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_buffer(heights.to_byte_array())


## Высота «сырой» местности (без учёта ровных мест).
func _raw(x: float, z: float, base: FastNoiseLite, ridge: FastNoiseLite) -> float:
	var b := base.get_noise_2d(x, z) # −1..1
	var r := 1.0 - absf(ridge.get_noise_2d(x, z))
	var h := maxf(0.0, b * 0.7 + 0.15) * 30.0 + pow(r, 6.0) * 22.0
	# к краям карты местность поднимается к горам
	var edge := minf(minf(x, z), minf(world.WORLD - x, world.WORLD - z))
	h += smoothstep(120.0, -60.0, edge) * 28.0
	# ступени — столовые горы с крутыми боками и плоскими вершинами
	var stepv := 6.0
	var t := h / stepv
	h = stepv * (floor(t) + smoothstep(0.38, 0.62, fposmod(t, 1.0)))
	return h


func _compute() -> void:
	var base := FastNoiseLite.new()
	base.seed = 4242
	base.frequency = 0.0032
	base.fractal_octaves = 4
	var ridge := FastNoiseLite.new()
	ridge.seed = 777
	ridge.frequency = 0.0055
	ridge.fractal_octaves = 2
	heights.resize(n * n)
	var towns: Array = world.towns
	var camps: Array = world.camps
	var roads: Array = world.roads
	for j in n:
		var z := MIN + j * STEP
		var rx: float = world.river_x(z)
		for i in n:
			var x := MIN + i * STEP
			var p := Vector2(x, z)
			# расстояние до ровных мест
			var d := INF
			for t in towns:
				d = minf(d, p.distance_to(t["pos"]) - 75.0)
			for c in camps:
				d = minf(d, p.distance_to(Vector2(c.position.x, c.position.z)) - 16.0)
			if d > 0.0:
				for r in roads:
					for k in r.size() - 1:
						d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, r[k], r[k + 1])) - 6.0)
						if d <= 0.0:
							break
			var dr: float = absf(x - rx) - world.RIVER_W / 2.0
			d = minf(d, dr - 6.0)
			var h := 0.0
			if d > 0.0:
				h = _raw(x, z, base, ridge) * smoothstep(0.0, 70.0, d)
			# русло реки
			if dr < 8.0:
				h = lerpf(RIVER_BED, h, smoothstep(-2.0, 8.0, dr))
			heights[j * n + i] = h


func _at(i: int, j: int) -> float:
	return heights[clampi(j, 0, n - 1) * n + clampi(i, 0, n - 1)]


## Высота земли в точке (с мостами).
func height(x: float, z: float) -> float:
	if world.on_bridge(z) and absf(x - world.river_x(z)) < world.RIVER_W / 2.0 + 5.0:
		return 0.25
	var fx := (x - MIN) / STEP
	var fz := (z - MIN) / STEP
	var i := int(floor(fx))
	var j := int(floor(fz))
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_at(i, j), _at(i + 1, j), tx)
	var b := lerpf(_at(i, j + 1), _at(i + 1, j + 1), tx)
	return lerpf(a, b, tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := STEP
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


func _build_meshes() -> void:
	var per := (n - 1) / CHUNKS
	for cj in CHUNKS:
		for ci in CHUNKS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var i0 := ci * per
			var j0 := cj * per
			var i1 := mini(i0 + per, n - 1)
			var j1 := mini(j0 + per, n - 1)
			var w := i1 - i0 + 1
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var x := MIN + i * STEP
					var z := MIN + j * STEP
					var nv := Vector3(_at(i - 1, j) - _at(i + 1, j), 2.0 * STEP, _at(i, j - 1) - _at(i, j + 1)).normalized()
					st.set_normal(nv)
					st.add_vertex(Vector3(x, _at(i, j), z))
			for j in range(j1 - j0):
				for i in range(w - 1):
					var a := j * w + i
					var b := a + 1
					var c := a + w
					var d := c + 1
					st.add_index(a)
					st.add_index(b)
					st.add_index(c)
					st.add_index(b)
					st.add_index(d)
					st.add_index(c)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 16 # слой 5 — рельеф (пули, взгляд, камера)
	body.collision_mask = 0
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for k in n * n:
		data[k] = heights[k] / STEP
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * STEP
	var mid := (MIN + MAX) / 2.0
	cs.position = Vector3(mid, 0, mid)
	body.add_child(cs)
