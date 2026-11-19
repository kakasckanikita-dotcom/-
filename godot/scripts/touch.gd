extends Control
## Сенсорное управление для телефона: джойстик слева, обзор правым пальцем,
## кнопки действий справа. Кнопки отправляют обычные игровые действия
## (shoot, focus, interact…), поэтому код героя один и тот же на ПК и телефоне.

var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_pos := Vector2.ZERO
var look_id := -1
var held := {} # индекс касания -> действие
var buttons: Array = []
var u := 1.0
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font


func _layout() -> void:
	var W := size
	u = clampf(minf(W.x, W.y) / 720.0, 0.75, 1.6)
	buttons = [
		{"label": "ОГОНЬ", "action": "shoot", "c": W - Vector2(125, 135) * u, "r": 66.0 * u},
		{"label": "ГЛАЗ", "action": "focus", "c": W - Vector2(280, 78) * u, "r": 46.0 * u},
		{"label": "ДЕЙСТВИЕ", "action": "interact", "c": W - Vector2(100, 300) * u, "r": 48.0 * u},
		{"label": "ГАЛОП", "action": "sprint", "c": W - Vector2(275, 215) * u, "r": 46.0 * u, "mounted": true},
	]
	var small := [["ЗАРЯД", "reload"], ["АПТЕЧКА", "medkit"], ["ТОНИК", "tonic"], ["СВИСТ", "whistle"], ["КАРТА", "map"]]
	for i in small.size():
		buttons.append({"label": small[i][0], "action": small[i][1], "c": Vector2(W.x * 0.34 + i * 84.0 * u, W.y - 46.0 * u), "r": 34.0 * u})


func _visible_buttons() -> Array:
	var pl = Game.world.player if Game.world else null
	return buttons.filter(func(b): return not b.get("mounted", false) or (pl and pl.mounted))


func _button_at(p: Vector2) -> Variant:
	for b in _visible_buttons():
		if p.distance_to(b["c"]) < b["r"] * 1.15:
			return b
	return null


func _release_all() -> void:
	for idx in held:
		Game.press(held[idx], false)
	held.clear()
	joy_id = -1
	look_id = -1
	Game.touch_move = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if Game.world == null:
		return
	if Game.world.hud.ui_open():
		if not held.is_empty() or joy_id != -1:
			_release_all()
		return
	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed:
			var b: Variant = _button_at(event.position)
			if b:
				held[idx] = b["action"]
				Game.press(b["action"], true)
			elif Game.world.player.focus_on:
				Game.world.player.mark_at_screen(event.position)
			elif event.position.x < size.x * 0.4 and joy_id == -1:
				joy_id = idx
				joy_origin = event.position
				joy_pos = event.position
			elif look_id == -1:
				look_id = idx
			get_viewport().set_input_as_handled()
		else:
			if held.has(idx):
				Game.press(held[idx], false)
				held.erase(idx)
			if idx == joy_id:
				joy_id = -1
				Game.touch_move = Vector2.ZERO
			if idx == look_id:
				look_id = -1
	elif event is InputEventScreenDrag:
		var idx: int = event.index
		if idx == joy_id:
			joy_pos = event.position
			Game.touch_move = ((joy_pos - joy_origin) / (70.0 * u)).limit_length(1.0)
			get_viewport().set_input_as_handled()
		elif idx == look_id:
			Game.touch_look += event.relative * 1.3 / u
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_layout()
	queue_redraw()


func _draw() -> void:
	if Game.world == null or Game.world.hud.ui_open():
		return
	# джойстик
	var base := joy_origin if joy_id != -1 else Vector2(150, size.y - 150) * Vector2(u, 1.0) + Vector2(0, -0.0)
	if joy_id == -1:
		base = Vector2(150 * u, size.y - 150 * u)
	draw_circle(base, 70.0 * u, Color(0, 0, 0, 0.22))
	draw_arc(base, 70.0 * u, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)
	var knob := base + Game.touch_move * 70.0 * u
	draw_circle(knob, 30.0 * u, Color(1, 1, 1, 0.45 if joy_id != -1 else 0.25))
	# кнопки
	for b in _visible_buttons():
		var pressed: bool = held.values().has(b["action"])
		var col := Color(0.42, 0.27, 0.14, 0.75) if not pressed else Color(0.7, 0.45, 0.2, 0.9)
		if b["action"] == "focus" and Game.world.player.focus_on:
			col = Color(0.85, 0.55, 0.1, 0.9)
		draw_circle(b["c"], b["r"], col)
		draw_arc(b["c"], b["r"], 0, TAU, 32, Color(1, 0.9, 0.7, 0.6), 2.0)
		var fs := int((15.0 if b["r"] > 40.0 * u else 11.0) * u)
		var w := font.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, b["c"] + Vector2(-w / 2.0, fs * 0.35), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Game.CREAM)
