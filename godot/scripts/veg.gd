extends Node3D
## Растительность пустыни: пучки сухой травы и кусты полыни. Текстуры
## рисуются кодом при запуске, плоскости перекрещены звёздочкой. Мир разбит
## на участки со своим MultiMesh и дальностью видимости — на телефоне
## рисуется только то, что рядом с игроком.

const VegShader := preload("res://scripts/veg.gdshader")
const CELL := 100.0

var rng := RandomNumberGenerator.new()


func build(world: Node3D) -> void:
	rng.seed = 9090
	var grass_tex := _grass_texture()
	var bush_tex := _bush_texture()
	var grass_mesh := _star_mesh(3, 0.9, 0.7)
	var bush_mesh := _star_mesh(4, 1.6, 1.3)
	var gm := _mat(grass_tex, 0.08, 70.0)
	var bm := _mat(bush_tex, 0.05, 160.0)
	var cells := {}
	var W: float = world.WORLD
	# трава — гуще на «кустистых» участках (там же, где зеленоватый оттенок земли)
	var mask := FastNoiseLite.new()
	mask.seed = 11
	mask.frequency = 0.01
	for i in 60000:
		var p := Vector2(rng.randf_range(0, W), rng.randf_range(0, W))
		var dens := mask.get_noise_2d(p.x, p.y) * 0.5 + 0.5
		if rng.randf() > dens * 1.4 - 0.15:
			continue
		var kind := 1 if rng.randf() < 0.12 else 0
		if not _ok(world, p, kind == 1):
			continue
		var s := rng.randf_range(0.6, 1.3) * (1.0 if kind == 0 else rng.randf_range(0.7, 1.4))
		var y: float = world.ground(p.x, p.y) - 0.05
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), Vector3(p.x, y, p.y))
		var tint := Color(1, 1, 1).lerp(Color(1.1, 1.0, 0.75), rng.randf()) * rng.randf_range(0.85, 1.1)
		var key := Vector2i(int(p.x / CELL), int(p.y / CELL))
		if not cells.has(key):
			cells[key] = [[], [], [], []]
		cells[key][kind * 2].append(xf)
		cells[key][kind * 2 + 1].append(tint)
	for key in cells:
		var c: Array = cells[key]
		_chunk(grass_mesh, gm, c[0], c[1], 70.0)
		_chunk(bush_mesh, bm, c[2], c[3], 160.0)


func _ok(world: Node3D, p: Vector2, bush: bool) -> bool:
	var v := Vector3(p.x, 0, p.y)
	if world.in_water(v) or world.near_road(p, 4.5) or world.town_at(v) != null:
		return false
	for c in world.camps:
		if p.distance_to(Vector2(c.position.x, c.position.z)) < 14.0:
			return false
	if bush:
		for o in world.obstacles:
			if p.distance_to(o[0]) < o[1] + 1.0:
				return false
	# на крутых склонах не растёт
	return world.terrain == null or world.terrain.normal_at(p.x, p.y).y > 0.85


func _chunk(mesh: Mesh, mat: Material, xforms: Array, tints: Array, far: float) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = far + CELL * 0.7
	add_child(mmi)


func _mat(t: Texture2D, sway: float, far: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VegShader
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("fade_far", far)
	return m


## n вертикальных плоскостей, повёрнутых звездой вокруг оси Y.
func _star_mesh(n: int, w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in n:
		var a := PI * k / n
		var d := Vector3(cos(a), 0, sin(a)) * w / 2.0
		var v := [-d, d, d + Vector3(0, h, 0), -d + Vector3(0, h, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	return st.commit()


## Пучок сухой травы: изогнутые стебли от основания, соломенные и зеленоватые.
func _grass_texture() -> ImageTexture:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for b in 70:
		var x0 := S / 2.0 + rng.randf_range(-20, 20)
		var lean := rng.randf_range(-0.9, 0.9)
		var length := rng.randf_range(0.45, 0.95) * S
		var col := Color("b9a066").lerp(Color("8d8a4c"), rng.randf()).lerp(Color("d8c48a"), rng.randf() * 0.4)
		var steps := int(length)
		for i in steps:
			var t := float(i) / steps
			var x := x0 + lean * t * t * S * 0.35
			var y := S - 1 - i
			var wdt := 1.6 * (1.0 - t) + 0.4
			for dx in range(-2, 3):
				if absf(dx) <= wdt:
					var px := int(x) + dx
					if px >= 0 and px < S and y >= 0:
						img.set_pixel(px, y, col.darkened((1.0 - t) * 0.35))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Куст полыни: серо-зелёная округлая крона из мелких листочков на тёмных ветках.
func _bush_texture() -> ImageTexture:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# ветки
	for b in 14:
		var a := rng.randf_range(-1.2, 1.2)
		var l := rng.randf_range(0.35, 0.6) * S
		for i in int(l):
			var x := int(S / 2.0 + sin(a) * i)
			var y := int(S - 1 - cos(a) * i * 0.9)
			if x >= 0 and x < S and y >= 0 and y < S:
				img.set_pixel(x, y, Color("4a3a28"))
	# листва
	for k in 900:
		var r := sqrt(rng.randf()) * S * 0.42
		var a := rng.randf() * TAU
		var cx := S / 2.0 + cos(a) * r
		var cy := S * 0.52 + sin(a) * r * 0.75
		var col := Color("8a9370").lerp(Color("6b7552"), rng.randf()).lerp(Color("b0aa80"), rng.randf() * 0.3)
		col = col.darkened(clampf((cy - S * 0.3) / S, 0.0, 0.4))
		var rr := rng.randi_range(1, 3)
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if dx * dx + dy * dy <= rr * rr:
					var px := int(cx) + dx
					var py := int(cy) + dy
					if px >= 0 and px < S and py >= 0 and py < S:
						img.set_pixel(px, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
