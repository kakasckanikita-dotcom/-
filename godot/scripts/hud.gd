extends Control
## Интерфейс: показатели героя, прицел, уведомления, миникарта и большая
## карта, титульный экран и меню зданий (салун, лавка, шериф, банк).

const PAPER := Color("e9d6ae")
const INK := Color("3a2412")
const WOOD := Color("6b4423")
const WOOD2 := Color("8a5a2f")
const BOUNTY_NAMES := ["Эйб «Хромой» Таттл", "Сайлас Грач", "Вдова Мэг Холлоуэй", "Эзра Шрам", "Билли Две Луны", "Кальвин «Пастор» Ридж", "Хуан Ферро", "Одноглазый Норрис"]

const CREDITS := "3D-модели (Sketchfab, CC BY 4.0): конь «Horse» — henry_7; анимации людей — «Bearded man» (Agor_), «Business Man» (manoeldarochadeoliveira), «Police_ru combat online» (eqisX); ковбой «Western Cowboy (Rigged)» — stevedaman; «Lowpoly cowboy» — Sololopenko; «Low Poly Colt Single-Action Army» — TastyTony; «Old Western Bank» — elvair; «General Store» — sixpence; «Western Town House 1» — FearlessAstroStar; «Western church», «Wanted Table» — adam127; «Low Poly Western Watertower» — staticcc; «Stagecoach» — Tuuttipingu; «Wooden Covered Wagon» — BytesCrafter; «Stylized Rocks Asset Pack» — deadzik; «Low Poly Western» — gallacs; горожанин «Bearded man» — Agor_; реквизит: «Wooden Barrels», «Dead Tree» — MaX3Dd; «Old wooden Wagon» — Peter.Nox; «Fence and Gate (Wood)» — trentspice; «Hitching Post» — Ellen_Ennest; «Water Trough» (CC0) — Avramania; «Old West Windmill & Water Tower» — DanielGrps; «Low Poly: Dead Tree» — clintonabbott.art; «Low Poly Cow Skull» — Tohst; «LP_Oil_Lantern» — Vitor.Gomes1; «Old gallows» — adam127; животные: вилорог — WildMesh_3D, койот — tech.service.allwe, корова — rukh3d, орёл — GremorySaiyan, заяц — bluekiwi.dog. Звуки, музыка и голоса — ElevenLabs. Шрифты Old Standard TT и PT Sans Narrow — SIL OFL."
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
var tfont: Font # заголовки
var hit_t := 0.0 # отметка попадания у прицела
var hit_kill := false
var _fade := 0.0 # затемнение экрана при переходах
var _fade_dir := 0.0
var _fade_cb: Callable


func _ready() -> void:
	font = UiKit.font_body()
	tfont = UiKit.font_title()
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


## Плавно затемнить экран, сделать cb (например, перенести героя), открыть.
func fade(cb: Callable) -> void:
	_fade_cb = cb
	_fade_dir = 1.0


## Попадание по цели: белая отметка, при убийстве — красная.
func hit(kill: bool) -> void:
	hit_kill = kill
	hit_t = 0.35 if kill else 0.25


func ui_open() -> bool:
	return title_root.visible or menu_root.visible or big_map


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	hit_t = maxf(0.0, hit_t - real)
	if _fade_dir != 0.0:
		_fade = clampf(_fade + _fade_dir * real * 3.0, 0.0, 1.0)
		if _fade >= 1.0 and _fade_dir > 0.0:
			_fade_dir = -1.0
			if _fade_cb.is_valid():
				_fade_cb.call()
		elif _fade <= 0.0 and _fade_dir < 0.0:
			_fade_dir = 0.0
	for t in toasts:
		t["life"] -= real
	while not toasts.is_empty() and toasts[0]["life"] <= 0.0:
		toasts.pop_front()
	var s := 130.0 if size.y < 600.0 else 170.0
	minimap.size = Vector2(s, s)
	minimap.position = Vector2(size.x - s - 14, 82)
	minimap.visible = not ui_open() and Game.world != null and not (Game.world.interior and Game.world.interior.inside)
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
	ui_theme.default_font = font
	ui_theme.default_font_size = 22 if Game.touch_mode else 18
	ui_theme.set_stylebox("normal", "Button", UiKit.wood_box(false))
	ui_theme.set_stylebox("hover", "Button", UiKit.wood_box(true))
	ui_theme.set_stylebox("pressed", "Button", UiKit.wood_box(true))
	var dis := UiKit.wood_box(false)
	dis.modulate_color = Color(1, 1, 1, 0.45)
	ui_theme.set_stylebox("disabled", "Button", dis)
	ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ui_theme.set_color(c, "Button", Color("f3e3c0"))
	ui_theme.set_color("font_hover_color", "Button", Color("ffe9a8"))
	ui_theme.set_color("font_disabled_color", "Button", Color("f3e3c0", 0.55))
	ui_theme.set_color("font_outline_color", "Button", Color(0.1, 0.05, 0.02, 0.8))
	ui_theme.set_constant("outline_size", "Button", 3)
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_stylebox("panel", "PanelContainer", UiKit.paper_box(30.0))
	var sep := StyleBoxLine.new()
	sep.color = Color(INK, 0.4)
	sep.thickness = 2
	ui_theme.set_stylebox("separator", "HSeparator", sep)


func _screen() -> Array:
	var root := ColorRect.new()
	root.color = Color(0.05, 0.03, 0.01, 0.55)
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
	var vig := TextureRect.new()
	vig.texture = UiKit.vignette()
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.move_child(vig, 0)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(minf(640.0, get_viewport_rect().size.x - 32.0), 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	return [root, vb]


func _label(parent: Control, text: String, font_size := 16, align := HORIZONTAL_ALIGNMENT_LEFT, alpha := 1.0, title := false) -> Label:
	var l := Label.new()
	l.text = text
	if title:
		l.add_theme_font_override("font", tfont)
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
	var t := _label(vb, "ПЫЛЬ И СВИНЕЦ", 50, HORIZONTAL_ALIGNMENT_CENTER, 1.0, true)
	t.add_theme_color_override("font_color", Color("5a1a0e"))
	_label(vb, "— Территория Мескаль, 1889 год —", 18, HORIZONTAL_ALIGNMENT_CENTER, 0.8, true)
	vb.add_child(HSeparator.new())
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
	vb.add_child(HSeparator.new())
	_label(vb, CREDITS, 11, HORIZONTAL_ALIGNMENT_CENTER, 0.6)


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
	var tl := _label(menu_box, title, 32, HORIZONTAL_ALIGNMENT_CENTER, 1.0, true)
	tl.add_theme_color_override("font_color", Color("5a1a0e"))
	_label(menu_box, sub, 17, HORIZONTAL_ALIGNMENT_CENTER, 0.8)
	menu_box.add_child(HSeparator.new())
	_label(menu_box, "В кармане: $%d   ·   Патроны: %d   ·   Аптечки: %d   ·   Тоники: %d" % [Game.money, Game.ammo, Game.medkits, Game.tonics], 15, HORIZONTAL_ALIGNMENT_CENTER)
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
func _text(pos: Vector2, s: String, sz: int, col: Color, align := 0, f: Font = null, shadow := true) -> void:
	var ff := f if f else font
	var w := ff.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := pos.x
	if align == 0:
		x -= w / 2.0
	elif align == 1:
		x -= w
	if shadow:
		draw_string_outline(ff, Vector2(x, pos.y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, maxi(2, sz / 6), Color(0.06, 0.03, 0.01, col.a * 0.75))
	draw_string(ff, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _tw(s: String, sz: int, f: Font = null) -> float:
	return (f if f else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


## Тёмная лента с прозрачными краями (уведомления, подсказки).
func _ribbon(c: Vector2, w: float, h: float, a := 1.0, col := Color(0.07, 0.04, 0.02)) -> void:
	var e := minf(60.0, w * 0.25)
	var x0 := c.x - w / 2.0 - e
	var x1 := c.x + w / 2.0 + e
	var y0 := c.y - h / 2.0
	var y1 := c.y + h / 2.0
	var solid := Color(col, 0.72 * a)
	var clear := Color(col, 0.0)
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + e, y0), Vector2(x0 + e, y1), Vector2(x0, y1)]), PackedColorArray([clear, solid, solid, clear]))
	draw_rect(Rect2(x0 + e, y0, w, h), solid)
	draw_polygon(PackedVector2Array([Vector2(x1 - e, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x1 - e, y1)]), PackedColorArray([solid, clear, clear, solid]))
	draw_line(Vector2(x0 + e * 0.5, y0), Vector2(x1 - e * 0.5, y0), Color(0.85, 0.66, 0.3, 0.45 * a), 1.0)
	draw_line(Vector2(x0 + e * 0.5, y1), Vector2(x1 - e * 0.5, y1), Color(0.85, 0.66, 0.3, 0.45 * a), 1.0)


func _box(r: Rect2) -> void:
	draw_rect(r, Color(0.08, 0.05, 0.02, 0.6))


## Круглый показатель с кольцом и значком в центре.
func _core(c: Vector2, r: float, v: float, col: Color, icon: Callable, low := false) -> void:
	draw_circle(c, r + 3.0, Color(0.05, 0.03, 0.01, 0.55))
	draw_arc(c, r - 2.0, 0, TAU, 40, Color(0.2, 0.14, 0.08, 0.85), 5.0)
	var vv := clampf(v, 0.0, 1.0)
	if vv > 0.001:
		draw_arc(c, r - 2.0, -PI / 2.0, -PI / 2.0 + TAU * vv, maxi(6, int(40 * vv)), col, 5.0)
	var ic := col.lightened(0.15)
	if low:
		ic = ic.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	icon.call(c, r * 0.48, ic)


## Барабан револьвера: латунные гильзы в гнёздах.
func _cylinder(c: Vector2, r: float) -> void:
	draw_circle(c, r + 3.0, Color(0.05, 0.03, 0.01, 0.6))
	draw_circle(c, r, Color(0.22, 0.2, 0.19, 0.95))
	draw_arc(c, r, 0, TAU, 32, Color(0.5, 0.47, 0.42), 2.0)
	for i in 6:
		var p := c + Vector2.from_angle(i / 6.0 * TAU - PI / 2) * r * 0.58
		draw_circle(p, r * 0.24, Color(0.08, 0.07, 0.06))
		if i < Game.clip:
			draw_circle(p, r * 0.2, Color("d6a84a"))
			draw_circle(p, r * 0.08, Color("8a6424"))
	draw_circle(c, r * 0.14, Color(0.4, 0.38, 0.35))


func _star(c: Vector2, r: float, col: Color) -> void:
	UiKit.star(self, c, r + 1.5, Color(0.05, 0.03, 0.01, col.a * 0.8))
	UiKit.star(self, c, r, col)


func _draw() -> void:
	var W := size
	var w = Game.world
	if w == null or title_root.visible:
		return
	var pl = w.player
	var tm := Game.touch_mode
	# кинематографичная виньетка; в «Глазе ястреба» — сепия
	draw_texture_rect(UiKit.vignette(), Rect2(Vector2.ZERO, W), false, Color(1, 1, 1, 0.55))
	if pl.focus_on or not pl.exec_q.is_empty():
		draw_rect(Rect2(Vector2.ZERO, W), Color(0.55, 0.3, 0.06, 0.22))
		draw_texture_rect(UiKit.vignette(), Rect2(Vector2.ZERO, W), false, Color(0.6, 0.25, 0.05, 0.9))
	if pl.flash > 0.0:
		draw_texture_rect(UiKit.vignette(), Rect2(Vector2.ZERO, W), false, Color(0.75, 0.0, 0.0, minf(1.0, pl.flash * 1.6)))
	if Game.hp < 30.0 and not pl.dead:
		var pulse := 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		draw_texture_rect(UiKit.vignette(), Rect2(Vector2.ZERO, W), false, Color(0.6, 0.0, 0.0, pulse))

	# метки «Глаза ястреба»
	for m in pl.marks + pl.exec_q:
		if is_instance_valid(m) and not m.dead:
			var wp: Vector3 = m.global_position + Vector3(0, m.head_height() - 0.3, 0)
			if not pl.cam.is_position_behind(wp):
				var sp: Vector2 = pl.cam.unproject_position(wp)
				draw_line(sp + Vector2(-10, -10), sp + Vector2(10, 10), Color(0.1, 0.0, 0.0, 0.7), 7.0)
				draw_line(sp + Vector2(10, -10), sp + Vector2(-10, 10), Color(0.1, 0.0, 0.0, 0.7), 7.0)
				draw_line(sp + Vector2(-9, -9), sp + Vector2(9, 9), Color("e0261a"), 4.0)
				draw_line(sp + Vector2(9, -9), sp + Vector2(-9, 9), Color("e0261a"), 4.0)

	# прицел: точка, при наведении на цель — красный и раскрывается
	if not pl.dead and not big_map:
		var c := W / 2.0
		var on_target = pl.target_under_crosshair() != null
		var cc := Color("ff4a3a") if on_target else Color(1, 1, 1, 0.9)
		draw_circle(c, 3.2, Color(0, 0, 0, 0.5))
		draw_circle(c, 2.2, cc)
		if on_target or pl.aim_t > 0.0:
			var g := 7.0 if on_target else 10.0
			for k in 4:
				var d := Vector2.from_angle(k * PI / 2.0)
				draw_line(c + d * g, c + d * (g + 6.0), Color(0, 0, 0, 0.5), 3.5)
				draw_line(c + d * g, c + d * (g + 6.0), cc, 1.8)
		if hit_t > 0.0:
			var hc := Color(1, 0.2, 0.15, hit_t / 0.35) if hit_kill else Color(1, 1, 1, hit_t / 0.25)
			for k in 4:
				var d := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
				draw_line(c + d * 6.0, c + d * 14.0, hc, 2.5)

	# слева сверху: деньги, время, честь — текст с тенью, без плашек
	_text(Vector2(20, 44), "$%d" % Game.money, 34, Color("f0c75a"), -1, tfont)
	var hh := int(Game.game_time / 60.0)
	var mm := int(fmod(Game.game_time, 60.0))
	_text(Vector2(22, 68), "День %d  ·  %02d:%02d" % [Game.day, hh, mm], 18, Game.CREAM, -1)
	var hcol: Color = Game.GOOD if Game.honor >= 0 else Game.BAD
	_star(Vector2(30, 85), 7.0, hcol)
	_text(Vector2(42, 92), "Честь %+d    Убито %d" % [Game.honor, Game.kills], 17, Game.CREAM, -1)

	# розыск
	if Game.wanted > 0:
		for i in 5:
			_star(Vector2(W.x - 26 - (4 - i) * 30, 34), 12, Color("ff5a3a") if i < Game.wanted else Color(0.35, 0.25, 0.18, 0.7))
		var txt := "Скрываетесь… %d" % ceili(25.0 - Game.evade) if Game.evade > 0.5 else "РАЗЫСКИВАЕТСЯ"
		_text(Vector2(W.x - 16, 64), txt, 16, Color("ffb39a"), 1, tfont)

	# задание
	if Game.bounty != null:
		var txt := "Награда ждёт у шерифа: $%d" % Game.bounty["reward"] if Game.bounty["done"] else "%s — «%s»" % [Game.bounty["name"], Game.bounty["camp"].camp_name]
		UiKit.star(self, Vector2(28, 113), 6.0, Game.GOLD)
		_text(Vector2(40, 119), txt, 17, Game.GOLD, -1)

	# уведомления — ленты по центру сверху
	for i in toasts.size():
		var t: Dictionary = toasts[i]
		var a := minf(1.0, t["life"])
		var tw := _tw(t["t"], 19) + 20.0
		var cy := 84.0 + i * 34.0
		_ribbon(Vector2(W.x / 2.0, cy), tw, 28.0, a)
		_text(Vector2(W.x / 2.0, cy + 7.0), t["t"], 19, Color(t["c"], a))

	# круглые показатели и барабан: на ПК внизу слева, на телефоне — под деньгами
	var cr := 26.0
	var cy2 := (172.0 if Game.bounty != null else 150.0) if tm else W.y - 52.0
	var cx := 20.0 + cr
	_core(Vector2(cx, cy2), cr, Game.hp / 100.0, Color("c8321e"), func(c, r, col): UiKit.heart(self, c, r, col), Game.hp < 30.0)
	cx += cr * 2.0 + 12.0
	_core(Vector2(cx, cy2), cr, Game.focus / 100.0, Color("d9a22a"), func(c, r, col): UiKit.eye(self, c, r, col))
	if pl.mounted:
		cx += cr * 2.0 + 12.0
		_core(Vector2(cx, cy2), cr, Game.stam / 100.0, Color("5a93b8"), func(c, r, col): UiKit.horseshoe(self, c, r, col))
	cx += cr * 2.0 + 16.0
	_cylinder(Vector2(cx, cy2), cr - 2.0)
	var tx := cx + cr + 8.0
	_text(Vector2(tx, cy2 - 2.0), "Перезарядка…" if pl.reload_t > 0.0 else "%d" % Game.clip, 26 if pl.reload_t <= 0.0 else 18, Game.CREAM, -1, tfont)
	if pl.reload_t <= 0.0:
		_text(Vector2(tx + _tw("%d" % Game.clip, 26, tfont) + 4.0, cy2 - 2.0), "/ %d" % Game.ammo, 17, Color(Game.CREAM, 0.75), -1)
	UiKit.cross(self, Vector2(tx + 6.0, cy2 + 15.0), 5.0, Color("d04030"))
	_text(Vector2(tx + 15.0, cy2 + 21.0), "%d" % Game.medkits, 15, Game.CREAM, -1)
	UiKit.bottle(self, Vector2(tx + 40.0, cy2 + 15.0), 5.5, Color("6fb0c8"))
	_text(Vector2(tx + 49.0, cy2 + 21.0), "%d" % Game.tonics, 15, Game.CREAM, -1)
	if Game.clip == 0 and Game.ammo == 0:
		_text(Vector2(20, cy2 - cr - 10.0), "Нет патронов — в лавку!", 15, Game.BAD, -1)

	# подсказка действия: клавиша в кружке
	if pl.hint != "" and not pl.dead:
		var key := "!" if tm else "E"
		var hw := _tw(pl.hint, 18) + 44.0
		var hy := W.y * 0.64
		_ribbon(Vector2(W.x / 2.0, hy), hw, 32.0)
		var kc := Vector2(W.x / 2.0 - hw / 2.0 + 14.0, hy)
		draw_circle(kc, 12.0, Color("e8d2a2"))
		draw_arc(kc, 12.0, 0, TAU, 20, Color(0.2, 0.12, 0.05), 1.5)
		_text(kc + Vector2(0, 6), key, 16, INK, 0, font, false)
		_text(Vector2(kc.x + 22.0, hy + 7.0), pl.hint, 18, Game.CREAM, -1)

	if pl.focus_on:
		var how := "касайтесь целей" if tm else "наведите и щёлкните по целям"
		_text(Vector2(W.x / 2, W.y * 0.24), "ГЛАЗ ЯСТРЕБА", 30, Game.GOLD, 0, tfont)
		_text(Vector2(W.x / 2, W.y * 0.24 + 26), "%s · %d / %d" % [how, pl.marks.size(), Game.clip], 18, Game.CREAM)

	if big_map:
		_draw_big_map()

	if pl.dead:
		draw_rect(Rect2(Vector2.ZERO, W), Color(0.08, 0.0, 0.0, minf(0.7, pl.dead_t * 0.3)))
		draw_texture_rect(UiKit.vignette(), Rect2(Vector2.ZERO, W), false, Color(0, 0, 0, minf(1.0, pl.dead_t * 0.5)))
		_text(W / 2, "ВЫ ПОГИБЛИ", 64, Color("c83a2a"), 0, tfont)
		_text(W / 2 + Vector2(0, 40), "Пустыня не прощает ошибок", 22, Game.CREAM)
	if _fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, W), Color(0, 0, 0, _fade))


func _draw_big_map() -> void:
	var w = Game.world
	var S := minf(size.x, size.y) - 80.0
	var o := (size - Vector2(S, S)) / 2.0
	var sc: float = S / w.WORLD
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.65))
	draw_texture_rect(UiKit.wood(), Rect2(o - Vector2(14, 14), Vector2(S + 28, S + 28)), false)
	draw_texture_rect(UiKit.paper(), Rect2(o, Vector2(S, S)), false, Color(0.95, 0.88, 0.75))
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
		_text(c - Vector2(0, 13), t["name"], 18, INK, 0, tfont, false)
	for c in w.camps:
		if not c.known:
			continue
		var p: Vector2 = o + w.v2(c.position) * sc
		draw_circle(p, 5.0, Color("666666") if c.cleared else Color("a01a10"))
		_text(p + Vector2(0, 18), c.camp_name, 14, INK, 0, font, false)
	if Game.bounty != null and not Game.bounty["done"]:
		var bp: Vector2 = o + w.v2(Game.bounty["camp"].position) * sc
		draw_line(bp + Vector2(-8, -8), bp + Vector2(8, 8), Color("d4a017"), 3.0)
		draw_line(bp + Vector2(8, -8), bp + Vector2(-8, 8), Color("d4a017"), 3.0)
	var pp: Vector2 = o + w.v2(w.player.global_position) * sc
	draw_circle(pp, 6.0, Color.BLACK)
	draw_circle(pp, 4.5, Color.WHITE)
	var close_hint := "коснитесь, чтобы закрыть" if Game.touch_mode else "[M] закрыть"
	_text(Vector2(size.x / 2, maxf(o.y - 22, 24)), "ТЕРРИТОРИЯ МЕСКАЛЬ  ·  " + close_hint, 22, Game.CREAM, 0, tfont)
