extends Control
## Интерфейс: показатели героя, прицел, уведомления, миникарта и большая
## карта, титульный экран и меню зданий (салун, лавка, шериф, банк).

const PAPER := Color("e9d6ae")
const INK := Color("3a2412")
const WOOD := Color("6b4423")
const WOOD2 := Color("8a5a2f")
const BOUNTY_NAMES := ["Эйб «Хромой» Таттл", "Сайлас Грач", "Вдова Мэг Холлоуэй", "Эзра Шрам", "Билли Две Луны", "Кальвин «Пастор» Ридж", "Хуан Ферро", "Одноглазый Норрис"]

const CREDITS := "3D-модели (Sketchfab, CC BY 4.0): конь «Horse» — henry_7; анимации людей — «Bearded man» (Agor_), «Business Man» (manoeldarochadeoliveira), «Police_ru combat online» (eqisX); ковбой «Western Cowboy (Rigged)» — stevedaman; «Lowpoly cowboy» — Sololopenko; «Low Poly Colt Single-Action Army» — TastyTony; «Old Western Bank» — elvair; «General Store» — sixpence; «Western Town House 1» — FearlessAstroStar; «Western church», «Wanted Table» — adam127; «Low Poly Western Watertower» — staticcc; «Stagecoach» — Tuuttipingu; «Wooden Covered Wagon» — BytesCrafter; «Stylized Rocks Asset Pack» — deadzik; «Low Poly Western» — gallacs; животные: вилорог — WildMesh_3D, койот — tech.service.allwe, корова — rukh3d, орёл — GremorySaiyan, заяц — bluekiwi.dog. Звуки, музыка и голоса — ElevenLabs."
const MinimapScript := preload("res://scripts/minimap.gd")
const TouchScript := preload("res://scripts/touch.gd")

var toasts: Array = []
var big_map := false
var ui_theme: Theme
var title_root: Control
var menu_root: Control
var menu_box: VBoxContainer
var minimap: Control
var touch: Control
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	Game.toast.connect(_on_toast)
	_build_theme()
	minimap = MinimapScript.new()
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	if Game.touch_mode:
		touch = TouchScript.new()
		touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(touch)
		touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := _screen()
	menu_root = m[0]
	menu_box = m[1]
	menu_root.hide()
	_build_title()
	get_tree().paused = true


func _on_toast(text: String, color: Color) -> void:
	toasts.append({"t": text, "c": color, "life": 4.0})
	if toasts.size() > 4:
		toasts.pop_front()


func ui_open() -> bool:
	return title_root.visible or menu_root.visible or big_map


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	for t in toasts:
		t["life"] -= real
	while not toasts.is_empty() and toasts[0]["life"] <= 0.0:
		toasts.pop_front()
	var s := 130.0 if size.y < 600.0 else 170.0
	minimap.size = Vector2(s, s)
	minimap.position = Vector2(size.x - s - 14, 70)
	minimap.visible = not ui_open() and Game.world != null
	minimap.queue_redraw()
	if not Game.touch_mode:
		var want := Input.MOUSE_MODE_VISIBLE if ui_open() else Input.MOUSE_MODE_CAPTURED
		if ui_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = want
	queue_redraw()


func _input(event: InputEvent) -> void:
	if title_root.visible:
		return
	if menu_root.visible:
		if event.is_action_pressed("menu_close") or event.is_action_pressed("interact"):
			close_menu()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") or (big_map and event.is_action_pressed("menu_close")):
		toggle_map()
		get_viewport().set_input_as_handled()
	elif big_map and Game.touch_mode and event is InputEventScreenTouch and event.pressed:
		toggle_map()
		get_viewport().set_input_as_handled()


func toggle_map() -> void:
	big_map = not big_map
	if big_map and Game.world:
		Game.world.player.cancel_focus()
	get_tree().paused = big_map
	if not big_map and not Game.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- элементы интерфейса ----------
func _sb(c: Color, margin := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_content_margin_all(margin)
	s.set_corner_radius_all(3)
	return s


func _build_theme() -> void:
	ui_theme = Theme.new()
	ui_theme.default_font_size = 20 if Game.touch_mode else 16
	ui_theme.set_stylebox("normal", "Button", _sb(WOOD))
	ui_theme.set_stylebox("pressed", "Button", _sb(WOOD2.darkened(0.2)))
	ui_theme.set_stylebox("hover", "Button", _sb(WOOD2))
	ui_theme.set_stylebox("disabled", "Button", _sb(Color(WOOD, 0.45)))
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ui_theme.set_color(c, "Button", Game.CREAM)
	ui_theme.set_color("font_disabled_color", "Button", Color(Game.CREAM, 0.6))
	ui_theme.set_color("font_color", "Label", INK)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PAPER
	panel.border_color = WOOD
	panel.set_border_width_all(4)
	panel.set_content_margin_all(22)
	panel.shadow_color = Color(0, 0, 0, 0.6)
	panel.shadow_size = 20
	ui_theme.set_stylebox("panel", "PanelContainer", panel)


func _screen() -> Array:
	var root := ColorRect.new()
	root.color = Color(0.04, 0.02, 0.01, 0.62)
	root.theme = ui_theme
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(minf(620.0, get_viewport_rect().size.x - 32.0), 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	return [root, vb]


func _label(parent: Control, text: String, font_size := 16, align := HORIZONTAL_ALIGNMENT_LEFT, alpha := 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size + (4 if Game.touch_mode else 0))
	l.modulate.a = alpha
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable, disabled := false, center := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	if Game.touch_mode:
		b.custom_minimum_size.y = 56
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_title() -> void:
	var m := _screen()
	title_root = m[0]
	var vb: VBoxContainer = m[1]
	_label(vb, "ПЫЛЬ И СВИНЕЦ", 40, HORIZONTAL_ALIGNMENT_CENTER)
	_label(vb, "Территория Мескаль, 1889 год", 16, HORIZONTAL_ALIGNMENT_CENTER, 0.75)
	_label(vb, "Вы — Эли Брэнсон, охотник за головами. Банды держат пустыню в страхе, а шериф платит за каждого главаря. Возьмите розыск, найдите лагерь, вернитесь за наградой. Или станьте тем, на кого охотятся сами.", 15)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	vb.add_child(grid)
	var rows: Array
	if Game.touch_mode:
		rows = [["Левый палец", "джойстик — движение"], ["Правый палец", "водите по экрану — камера"], ["ОГОНЬ", "выстрел (с доводкой прицела)"], ["ГЛАЗ", "держите: замедление, касайтесь целей, отпустите — залп"], ["ДЕЙСТВИЕ", "конь, двери, разговор"], ["ГАЛОП", "держите верхом"]]
	else:
		rows = [["WASD", "движение"], ["Мышь / ЛКМ", "камера / выстрел"], ["Shift (держать)", "«Глаз ястреба»: замедление, наведите и щёлкните по целям, отпустите — залп"], ["E", "сесть на коня / слезть / войти"], ["Пробел", "галоп (верхом)"], ["H", "свистнуть коня"], ["R", "перезарядка"], ["Q / F", "аптечка / тоник"], ["M или Tab", "карта"]]
	for row in rows:
		var k := _label(grid, row[0], 14)
		k.autowrap_mode = TextServer.AUTOWRAP_OFF
		var v := _label(grid, row[1], 14)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Game.has_save():
		_button(vb, "Продолжить", func(): _start(true), false, true)
		_button(vb, "Новая игра (сбросить сохранение)", func(): Game.delete_save(); _start(false), false, true)
	else:
		_button(vb, "В седло", func(): _start(false), false, true)
	_label(vb, CREDITS, 10, HORIZONTAL_ALIGNMENT_CENTER, 0.6)


func _start(load_save: bool) -> void:
	if load_save:
		Game.load_game()
	title_root.hide()
	get_tree().paused = false
	if not Game.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.say("Территория Мескаль. Зайдите к шерифу за розыском.", Game.GOLD)


func open_menu(title: String, sub: String, opts: Array) -> void:
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()
	_label(menu_box, title, 26)
	_label(menu_box, sub, 15, HORIZONTAL_ALIGNMENT_LEFT, 0.75)
	_label(menu_box, "В кармане: $%d   Патроны: %d   Аптечки: %d   Тоники: %d" % [Game.money, Game.ammo, Game.medkits, Game.tonics], 14)
	for o in opts:
		var cb: Callable = o[2]
		_button(menu_box, o[0], func(): cb.call(); Game.save_game(), o[1])
	_button(menu_box, "Уйти", close_menu, false, true)
	menu_root.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	menu_root.hide()
	get_tree().paused = false
	if not Game.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


var _door_t := -999.0


func open_building(b: Dictionary) -> void:
	var t: Dictionary = b["town"]
	var reopen := func(): open_building(b)
	# скрип двери и приветствие хозяина (раз в полминуты, а не при каждом обновлении меню)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _door_t > 30.0:
		Game.play("door", -6.0)
	_door_t = now
	# хозяин здоровается (раз в полминуты, а не при каждом обновлении меню)
	var greet := {"saloon": ["shop", 1], "store": ["shop", 2], "bank": ["shop", 3], "hotel": ["shop", 4], "sheriff": ["sheriff", 2 if Game.wanted == 0 else 4]}
	if greet.has(b["type"]):
		Game.vo(greet[b["type"]][0], greet[b["type"]][1], null, "menu_" + b["type"], 30.0, -2.0)
	match b["type"]:
		"saloon":
			open_menu("Салун «Последний Глоток»", t["name"] + ". Пахнет табаком и дешёвым виски.", [
				["Стакан виски — $3 (здоровье полностью)", Game.money < 3 or Game.hp >= 100.0, func():
					Game.money -= 3
					Game.hp = 100.0
					Game.say("Виски обжигает горло. Здоровье восстановлено.")
					reopen.call()],
				["Покер — ставка $10", Game.money < 10, func():
					Game.money -= 10
					if randf() < 0.42:
						Game.money += 22
						Game.say("Фулл-хаус! Выигрыш $22", Game.GOOD)
						Game.play("coin")
					else:
						Game.say("Блеф не удался. −$10", Game.BAD)
					reopen.call()],
			])
		"hotel":
			open_menu("Гостиница «Пыльная Подушка»", t["name"] + ". Скрипучая лестница, чистые простыни.", [
				["Комната на ночь — $8 (спать до утра)", Game.money < 8, func():
					Game.money -= 8
					Game.hp = 100.0
					Game.focus = 100.0
					if Game.game_time >= 420.0:
						Game.day += 1
					Game.game_time = 420.0
					Game.say("Вы выспались. Утро дня %d." % Game.day)
					close_menu()],
			])
		"store":
			open_menu("Лавка Хиггинса", t["name"] + ". «Всё для честного путника»", [
				["Патроны ×12 — $6", Game.money < 6, func():
					Game.money -= 6
					Game.ammo += 12
					reopen.call()],
				["Аптечка — $12 (+60 здоровья)", Game.money < 12, func():
					Game.money -= 12
					Game.medkits += 1
					reopen.call()],
				["Тоник концентрации — $10", Game.money < 10, func():
					Game.money -= 10
					Game.tonics += 1
					reopen.call()],
			])
		"bank":
			var can := Game.bank_cd <= 0.0
			open_menu("Банк «%s»" % t["name"], "Толстые решётки. Кассир нервно поглядывает на ваш револьвер.", [
				["Ограбить банк (розыск: 3 звезды)" if can else "Сейф пуст. Приходите позже.", not can, func():
					var g := randi_range(150, 320)
					Game.money += g
					Game.wanted = maxi(Game.wanted, 3)
					Game.honor -= 30
					Game.bank_cd = 600.0
					Game.say("Вы взяли $%d! За вами погоня!" % g, Game.BAD)
					Game.world.alert_town(b["door"])
					close_menu()],
			])
		"sheriff":
			var opts: Array = []
			if Game.wanted > 0:
				var fine := 50 * Game.wanted
				opts.append(["Заплатить штраф $%d (снять розыск)" % fine, Game.money < fine, func():
					Game.money -= fine
					Game.world.clear_wanted()
					Game.say("Штраф уплачен. Вы чисты перед законом.")
					reopen.call()])
			if Game.bounty != null and Game.bounty["done"]:
				opts.append(["Получить награду: %s, $%d" % [Game.bounty["name"], Game.bounty["reward"]], false, func():
					Game.money += Game.bounty["reward"]
					Game.honor += 15
					Game.say("Награда $%d получена!" % Game.bounty["reward"], Game.GOOD)
					Game.play("coin")
					Game.bounty = null
					reopen.call()])
			elif Game.bounty != null:
				opts.append(["Отказаться от розыска (%s)" % Game.bounty["name"], false, func():
					Game.world.drop_bounty()
					reopen.call()])
			else:
				var avail: Array = Game.world.camps.filter(func(c): return Game.world.v2(c.position).distance_to(t["pos"]) > 120.0)
				avail.shuffle()
				for c in avail.slice(0, 3):
					var bname: String = BOUNTY_NAMES.pick_random()
					var reward := int(60.0 + Game.world.v2(c.position).distance_to(t["pos"]) / 5.0)
					opts.append(["РАЗЫСКИВАЕТСЯ: %s — $%d\nлагерь «%s»" % [bname, reward, c.camp_name], Game.wanted > 0, func():
						Game.world.accept_bounty(bname, reward, c)
						Game.say("Розыск принят: %s. Лагерь отмечен на карте." % bname, Game.GOLD)
						close_menu()])
			var sub := "Шериф держит руку на кобуре: «Вы под розыском, мистер»." if Game.wanted > 0 else "Шериф кивает на доску объявлений: «Живыми или мёртвыми»."
			open_menu("Контора шерифа", sub, opts)


# ---------- отрисовка HUD ----------
func _text(pos: Vector2, s: String, sz: int, col: Color, align := 0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := pos.x
	if align == 0:
		x -= w / 2.0
	elif align == 1:
		x -= w
	draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _tw(s: String, sz: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


func _box(r: Rect2) -> void:
	draw_rect(r, Color(0.08, 0.05, 0.02, 0.72))


func _bar(p: Vector2, w: float, v: float, col: Color, label: String) -> void:
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(w + 4, 18)), Color(0.08, 0.05, 0.02, 0.75))
	draw_rect(Rect2(p, Vector2(w * clampf(v, 0.0, 1.0), 14)), col)
	_text(p + Vector2(4, 11), label, 11, Game.CREAM, -1)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(c + Vector2.from_angle(-PI / 2 + i * PI / 5) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	var W := size
	var w = Game.world
	if w == null or title_root.visible:
		return
	var pl = w.player
	var tm := Game.touch_mode
	if pl.focus_on or not pl.exec_q.is_empty():
		draw_rect(Rect2(Vector2.ZERO, W), Color(0.55, 0.27, 0.04, 0.25))
	if pl.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, W), Color(0.63, 0, 0, pl.flash * 0.6))

	# метки «Глаза ястреба»
	for m in pl.marks + pl.exec_q:
		if is_instance_valid(m) and not m.dead:
			var wp: Vector3 = m.global_position + Vector3(0, m.head_height() - 0.3, 0)
			if not pl.cam.is_position_behind(wp):
				var sp: Vector2 = pl.cam.unproject_position(wp)
				draw_line(sp + Vector2(-9, -9), sp + Vector2(9, 9), Color("e0261a"), 4.0)
				draw_line(sp + Vector2(9, -9), sp + Vector2(-9, 9), Color("e0261a"), 4.0)

	# прицел
	if not pl.dead and not big_map:
		var c := W / 2.0
		var on_target = pl.target_under_crosshair() != null
		var cc := Color("ff4a3a") if on_target else Color(1, 1, 1, 0.85)
		draw_arc(c, 9.0, 0, TAU, 20, cc, 2.0)
		draw_circle(c, 1.8, cc)

	# слева сверху: деньги, время, честь
	_box(Rect2(12, 12, 230, 82))
	_text(Vector2(22, 40), "$%d" % Game.money, 22, Color("e8c35a"), -1)
	var hh := int(Game.game_time / 60.0)
	var mm := int(fmod(Game.game_time, 60.0))
	_text(Vector2(22, 62), "День %d   %02d:%02d" % [Game.day, hh, mm], 15, Game.CREAM, -1)
	_text(Vector2(22, 84), "Честь: %d   Убито: %d" % [Game.honor, Game.kills], 15, Game.GOOD if Game.honor >= 0 else Game.BAD, -1)

	# розыск
	if Game.wanted > 0:
		for i in 5:
			_star(Vector2(W.x - 24 - (4 - i) * 26, 30), 11, Color("ff5a3a") if i < Game.wanted else Color(0.3, 0.2, 0.15, 0.7))
		var txt := "Скрываетесь… %d" % ceili(25.0 - Game.evade) if Game.evade > 0.5 else "РАЗЫСКИВАЕТСЯ"
		_text(Vector2(W.x - 14, 60), txt, 13, Game.CREAM, 1)

	# задание
	if Game.bounty != null:
		var txt := "Награда ждёт у шерифа: $%d" % Game.bounty["reward"] if Game.bounty["done"] else "Цель: %s — «%s»" % [Game.bounty["name"], Game.bounty["camp"].camp_name]
		_box(Rect2(12, 100, _tw(txt, 14) + 20, 26))
		_text(Vector2(22, 118), txt, 14, Game.GOLD, -1)

	# уведомления
	for i in toasts.size():
		var t: Dictionary = toasts[i]
		var a := minf(1.0, t["life"])
		var tw := _tw(t["t"], 17) + 24.0
		draw_rect(Rect2(W.x / 2 - tw / 2, 70 + i * 32, tw, 26), Color(0.08, 0.05, 0.02, 0.75 * a))
		_text(Vector2(W.x / 2, 89 + i * 32), t["t"], 17, Color(t["c"], a))

	# полоски и барабан: на ПК внизу слева, на телефоне — под деньгами
	var by := 136.0 if tm else W.y - 90.0
	if Game.bounty == null and tm:
		by = 106.0
	_bar(Vector2(16, by), 180, Game.hp / 100.0, Color("a8261a"), "Здоровье")
	_bar(Vector2(16, by + 22), 180, Game.focus / 100.0, Color("c8901a"), "Глаз ястреба")
	if pl.mounted:
		_bar(Vector2(16, by + 44), 180, Game.stam / 100.0, Color("4a7a9a"), "Галоп")
	var ax := 206.0
	_box(Rect2(ax, by - 2, 160, 60))
	for i in 6:
		var c := Vector2(ax + 30, by + 26) + Vector2.from_angle(i / 6.0 * TAU - PI / 2) * 14.0
		draw_circle(c, 4.5, Color("e8c35a") if i < Game.clip else Color("3a2a1a"))
	_text(Vector2(ax + 56, by + 24), "Перезарядка" if pl.reload_t > 0.0 else "%d / %d" % [Game.clip, Game.ammo], 16, Game.CREAM, -1)
	_text(Vector2(ax + 56, by + 44), "Аптечки %d  Тоники %d" % [Game.medkits, Game.tonics], 12, Game.CREAM, -1)
	if Game.clip == 0 and Game.ammo == 0:
		_text(Vector2(ax, by - 8), "Нет патронов — в лавку!", 12, Game.BAD, -1)

	# подсказка действия
	if pl.hint != "" and not pl.dead:
		var key := "ДЕЙСТВИЕ" if tm else "E"
		var s := "[%s] %s" % [key, pl.hint]
		var hw := _tw(s, 16) + 24.0
		var hy := W.y * 0.62
		_box(Rect2(W.x / 2 - hw / 2, hy - 20, hw, 28))
		_text(Vector2(W.x / 2, hy), s, 16, Game.CREAM)

	if pl.focus_on:
		var how := "касайтесь целей" if tm else "наведите и щёлкните по целям"
		_text(Vector2(W.x / 2, W.y * 0.25), "ГЛАЗ ЯСТРЕБА — %s (%d/%d)" % [how, pl.marks.size(), Game.clip], 18, Game.GOLD)

	if big_map:
		_draw_big_map()

	if pl.dead:
		draw_rect(Rect2(Vector2.ZERO, W), Color(0, 0, 0, minf(0.75, pl.dead_t * 0.3)))
		_text(W / 2, "ВЫ ПОГИБЛИ", 54, Color("cc3333"))
		_text(W / 2 + Vector2(0, 34), "Пустыня не прощает ошибок", 18, Game.CREAM)


func _draw_big_map() -> void:
	var w = Game.world
	var S := minf(size.x, size.y) - 80.0
	var o := (size - Vector2(S, S)) / 2.0
	var sc: float = S / w.WORLD
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(o - Vector2(8, 8), Vector2(S + 16, S + 16)), PAPER)
	draw_rect(Rect2(o, Vector2(S, S)), Color("d2b27c"))
	for r in w.roads:
		var pts := PackedVector2Array()
		for p in r:
			pts.append(o + p * sc)
		draw_polyline(pts, Color(0.55, 0.4, 0.25, 0.7), 3.0)
	var river := PackedVector2Array()
	var z := 0.0
	while z <= w.WORLD:
		river.append(o + Vector2(w.river_x(z), z) * sc)
		z += 8.0
	draw_polyline(river, Color("3d7896"), maxf(3.0, w.RIVER_W * sc))
	for t in w.towns:
		var c: Vector2 = o + t["pos"] * sc
		draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), INK)
		_text(c - Vector2(0, 13), t["name"], 15, INK)
	for c in w.camps:
		if not c.known:
			continue
		var p: Vector2 = o + w.v2(c.position) * sc
		draw_circle(p, 5.0, Color("666666") if c.cleared else Color("a01a10"))
		_text(p + Vector2(0, 18), c.camp_name, 12, INK)
	if Game.bounty != null and not Game.bounty["done"]:
		var bp: Vector2 = o + w.v2(Game.bounty["camp"].position) * sc
		draw_line(bp + Vector2(-8, -8), bp + Vector2(8, 8), Color("d4a017"), 3.0)
		draw_line(bp + Vector2(8, -8), bp + Vector2(-8, 8), Color("d4a017"), 3.0)
	var pp: Vector2 = o + w.v2(w.player.global_position) * sc
	draw_circle(pp, 6.0, Color.BLACK)
	draw_circle(pp, 4.5, Color.WHITE)
	var close_hint := "коснитесь, чтобы закрыть" if Game.touch_mode else "[M] закрыть"
	_text(Vector2(size.x / 2, maxf(o.y - 16, 20)), "ТЕРРИТОРИЯ МЕСКАЛЬ  ·  " + close_hint, 18, Game.CREAM)
