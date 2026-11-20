class_name UiKit
extends RefCounted
## Оформление интерфейса в духе Дикого Запада: шрифты (заголовки — Old
## Standard, текст — PT Sans Narrow, оба OFL), состаренная бумага, дерево,
## виньетка и простые значки. Текстуры рисуются кодом один раз и кешируются.

static var _cache := {}


static func font_title() -> Font:
	return _font("res://assets/fonts/OldStandard-Bold.ttf")


static func font_body() -> Font:
	return _font("res://assets/fonts/PTSansNarrow-Bold.ttf")


static func font_regular() -> Font:
	return _font("res://assets/fonts/PTSansNarrow-Regular.ttf")


static func _font(path: String) -> Font:
	if not _cache.has(path):
		var f: Font = load(path)
		_cache[path] = f if f else ThemeDB.fallback_font
	return _cache[path]


## Состаренная бумага: пятна, волокна, потемневшие края.
static func paper() -> Texture2D:
	if _cache.has("paper"):
		return _cache["paper"]
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.02
	n.fractal_octaves = 5
	var f := FastNoiseLite.new()
	f.seed = 5
	f.frequency = 0.25
	var base := Color("e6d0a2")
	for y in S:
		for x in S:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var fib := f.get_noise_2d(x * 0.3, y * 2.0) * 0.5 + 0.5
			var c := base.darkened(v * 0.16 + fib * 0.05)
			# потемневшие края
			var ex := minf(x, S - 1 - x) / float(S)
			var ey := minf(y, S - 1 - y) / float(S)
			var e := 1.0 - smoothstep(0.0, 0.12, minf(ex, ey) + v * 0.03)
			c = c.lerp(Color("7a5228"), e * 0.6)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_cache["paper"] = t
	return t


## Доска: продольные волокна, сучки, тёмные края.
static func wood(light := false) -> Texture2D:
	var key := "wood%s" % light
	if _cache.has(key):
		return _cache[key]
	var W := 256
	var H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 31
	n.frequency = 0.05
	var base := Color("8a5a30") if light else Color("6a4222")
	for y in H:
		for x in W:
			var g := sin(y * 0.55 + n.get_noise_2d(x * 0.15, y) * 6.0) * 0.5 + 0.5
			var c := base.darkened(g * 0.22 + (n.get_noise_2d(x, y * 4.0) * 0.5 + 0.5) * 0.08)
			var e := 1.0 - smoothstep(0.0, 4.0, minf(minf(x, W - 1 - x), minf(y, H - 1 - y)))
			c = c.darkened(e * 0.45)
			img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## Тёмные углы экрана — кинематографичная рамка.
static func vignette() -> Texture2D:
	if _cache.has("vig"):
		return _cache["vig"]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.add_point(0.62, Color(0, 0, 0, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0.85))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.08, 1.08)
	t.width = 256
	t.height = 256
	_cache["vig"] = t
	return t


static func paper_box(margin := 26.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = paper()
	s.set_texture_margin_all(40)
	s.set_content_margin_all(margin)
	return s


static func wood_box(light := false, margin := 12.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = wood(light)
	s.set_texture_margin_all(6)
	s.set_content_margin_all(margin)
	s.content_margin_left = margin + 6
	return s


# ---------- значки (рисуются в CanvasItem) ----------
static func heart(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.45, -r * 0.2), r * 0.52, col)
	ci.draw_circle(c + Vector2(r * 0.45, -r * 0.2), r * 0.52, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.95, 0.0), c + Vector2(r * 0.95, 0.0), c + Vector2(0, r * 0.95)]), col)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.25), Vector2(r, r * 0.4)), col)


static func eye(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := i / 16.0 * TAU
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.55 * (1.0 if sin(a) < 0 else 0.8)))
	ci.draw_colored_polygon(pts, col)
	ci.draw_circle(c, r * 0.36, Color(0.12, 0.07, 0.03))
	ci.draw_circle(c + Vector2(-r * 0.1, -r * 0.1), r * 0.1, col)


static func horseshoe(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.7, PI * 0.95, PI * 2.05, 14, col, r * 0.34)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.86, r * 0.05), Vector2(r * 0.34, r * 0.7)), col)
	ci.draw_rect(Rect2(c + Vector2(r * 0.52, r * 0.05), Vector2(r * 0.34, r * 0.7)), col)


static func cross(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_rect(Rect2(c - Vector2(r * 0.3, r), Vector2(r * 0.6, r * 2.0)), col)
	ci.draw_rect(Rect2(c - Vector2(r, r * 0.3), Vector2(r * 2.0, r * 0.6)), col)


static func bottle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.3), Vector2(r, r * 1.3)), col)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.2, -r), Vector2(r * 0.4, r * 0.75)), col)


static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(c + Vector2.from_angle(-PI / 2 + i * PI / 5) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, col)
