class_name Models
extends RefCounted
## Загрузка моделей из assets/models: убирает встроенные площадки земли,
## подгоняет размер, ставит основание на y = 0 и центрирует.

static var _scenes := {}
static var _info := {} # имя -> {aabb, strip: [пути к узлам]}


static func scene(model: String) -> PackedScene:
	if not _scenes.has(model):
		_scenes[model] = load("res://assets/models/%s.glb" % model)
	return _scenes[model]


## Преобразование узла относительно корня (без дерева сцены).
static func rel_xf(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func meshes(root: Node) -> Array:
	return root.find_children("*", "MeshInstance3D", true, false)


## inst должен лежать в обёртке wrap: габариты считаются с учётом
## собственного поворота корня модели.
static func _analyze(model: String, inst: Node3D, wrap: Node3D) -> Dictionary:
	if _info.has(model):
		return _info[model]
	var boxes := []
	var full := AABB()
	var first := true
	for mi in meshes(inst):
		var b: AABB = rel_xf(mi, wrap) * mi.get_aabb()
		boxes.append([inst.get_path_to(mi), b])
		full = b if first else full.merge(b)
		first = false
	# плоские огромные детали и детали с «ground» в имени — встроенная земля
	var strip := []
	var foot := full.size.x * full.size.z
	for e in boxes:
		var b: AABB = e[1]
		var nm := String(e[0]).to_lower()
		if nm.contains("ground") or (b.size.y < full.size.y * 0.12 and b.size.x * b.size.z > foot * 0.5):
			strip.append(e[0])
	# оставляем связную группу деталей вокруг самой крупной (без разбросанных мелочей)
	var rest := boxes.filter(func(e): return not (e[0] in strip))
	if rest.is_empty():
		rest = boxes
	rest.sort_custom(func(x, y): return x[1].get_volume() > y[1].get_volume())
	var aabb: AABB = rest[0][1]
	var kept := [rest[0]]
	var changed := true
	while changed:
		changed = false
		var grown := aabb.grow(maxf(aabb.size.length() * 0.05, 0.0001))
		for e in rest:
			if e in kept:
				continue
			if grown.intersects(e[1]):
				kept.append(e)
				aabb = aabb.merge(e[1])
				changed = true
	for e in rest:
		if not (e in kept):
			strip.append(e[0])
	var info := {"aabb": aabb, "strip": strip}
	_info[model] = info
	return info


## Статичный объект. fit: "max" — по наибольшему горизонтальному размеру,
## "h" — по высоте, "x" — по ширине. yaw — поворот модели (до размещения).
static func prop(model: String, size: float, fit := "max", yaw := 0.0, hide: Array = []) -> Node3D:
	var holder := Node3D.new()
	var inst: Node3D = scene(model).instantiate()
	var wrap := Node3D.new()
	wrap.add_child(inst)
	var info := _analyze(model, inst, wrap)
	for p in info["strip"]:
		var n := inst.get_node_or_null(p)
		if n:
			n.free()
	var a: AABB = info["aabb"]
	var dim: float = maxf(a.size.x, a.size.z)
	if fit == "h":
		dim = a.size.y
	elif fit == "x":
		dim = a.size.x
	var s := size / maxf(dim, 0.0001)
	var pivot := Node3D.new()
	pivot.rotation.y = yaw
	holder.add_child(pivot)
	pivot.add_child(wrap)
	wrap.scale = Vector3.ONE * s
	var c := a.get_center()
	wrap.position = Vector3(-c.x * s, -a.position.y * s, -c.z * s)
	for mi in meshes(inst):
		if String(mi.name) in hide:
			mi.free()
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.set_meta("size", Basis(Vector3.UP, yaw) * (a.size * s))
	return holder


## Размер готового объекта (по осям X/Z после поворота, по модулю).
static func size_of(holder: Node3D) -> Vector3:
	var v: Vector3 = holder.get_meta("size", Vector3.ONE)
	return v.abs()


## Отдельные меши набора (например, кактусы из «Low Poly Western») с
## преобразованиями относительно корня модели — для MultiMesh.
static func parts(model: String, name_filter: String) -> Array:
	var inst: Node3D = scene(model).instantiate()
	var wrap := Node3D.new()
	wrap.add_child(inst)
	var res := []
	for mi in meshes(inst):
		if name_filter.is_empty() or mi.name.findn(name_filter) != -1:
			var x := rel_xf(mi, wrap)
			res.append({"name": String(mi.name), "mesh": mi.mesh, "xf": x, "aabb": x * mi.get_aabb()})
	wrap.free()
	return res


static func _in_group(part_name: String, prefix: String) -> bool:
	return part_name == prefix or part_name.begins_with(prefix + "_")


## Части одной группы набора (например, «Cactus1» или «Mountain2») с
## преобразованиями, уже нормализованными: основание на y = 0, по центру,
## наибольший горизонтальный размер (или высота при fit = "h") = size.
static func group(model: String, prefix: String, size := 1.0, fit := "max") -> Array:
	var ps := parts(model, "").filter(func(p): return _in_group(p["name"], prefix))
	if ps.is_empty():
		return []
	var a: AABB = ps[0]["aabb"]
	for p in ps:
		a = a.merge(p["aabb"])
	var dim := a.size.y if fit == "h" else maxf(a.size.x, a.size.z)
	var s := size / maxf(dim, 0.0001)
	var c := a.get_center()
	var norm := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(-c.x * s, -a.position.y * s, -c.z * s))
	var res := []
	for p in ps:
		res.append({"mesh": p["mesh"], "xf": norm * p["xf"], "size": a.size * s})
	return res


## Готовый объект из группы частей набора.
static func group_prop(model: String, prefix: String, size := 1.0, fit := "max", yaw := 0.0) -> Node3D:
	var holder := Node3D.new()
	for p in group(model, prefix, size, fit):
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * p["xf"]
		holder.add_child(mi)
		holder.set_meta("size", Basis(Vector3.UP, yaw) * p["size"])
	return holder
