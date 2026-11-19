extends Node3D
## Модель животного со скелетом и анимациями (Sketchfab). Размер и уровень
## земли считаются по костям в позе анимации — габариты меша у таких моделей
## часто неточные. Клипы движения и стойки зацикливаются.

var model: Node3D
var ap: AnimationPlayer
var skel: Skeleton3D
var _current := ""


## file — имя модели в assets/models, length — длина тела в метрах,
## yaw — поворот, чтобы голова смотрела в −Z, first — клип для замера.
func setup(file: String, length: float, yaw: float, first: String) -> void:
	var fix := Node3D.new()
	add_child(fix)
	model = Models.scene(file).instantiate()
	fix.add_child(model)
	model.rotation.y = yaw
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	ap = aps[0] if not aps.is_empty() else null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	skel = sks[0] if not sks.is_empty() else null
	if ap:
		for a in ap.get_animation_list():
			var l := a.to_lower()
			var once := l.contains("death") or l.contains("hit") or l.contains("trans") or l.contains("attack") or l.contains("jump")
			ap.get_animation(a).loop_mode = Animation.LOOP_NONE if once else Animation.LOOP_LINEAR
		play(first, 1.0, 0.0)
		ap.seek(0.2, true)
	# габариты по костям
	var box := AABB()
	var ok := false
	if skel:
		for i in skel.get_bone_count():
			var p := to_local(skel.global_transform * skel.get_bone_global_pose(i).origin)
			box = AABB(p, Vector3.ZERO) if not ok else box.expand(p)
			ok = true
	if not ok:
		for mi in Models.meshes(model):
			var b: AABB = Models.mesh_box(mi.mesh, Models.rel_xf(mi, self))
			box = b if not ok else box.merge(b)
			ok = true
	var dim := maxf(box.size.x, box.size.z)
	var s := length / maxf(dim, 0.0001)
	fix.scale = Vector3.ONE * s
	var c := box.get_center() * s
	fix.position = Vector3(-c.x, -box.position.y * s, -c.z)
	for mi in Models.meshes(model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func find(part: String) -> String:
	if ap == null:
		return ""
	for a in ap.get_animation_list():
		if a.ends_with(part) or a.ends_with(part + " ") or a.ends_with(part + "  ") or a.ends_with("|" + part):
			return a
	for a in ap.get_animation_list():
		if a.contains(part):
			return a
	return ""


func play(part: String, rate := 1.0, blend := 0.25) -> void:
	if ap == null:
		return
	var a := find(part)
	if a == "":
		return
	if _current != a:
		_current = a
		ap.play(a, blend)
	ap.speed_scale = rate
