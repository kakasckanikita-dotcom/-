class_name Gfx
extends RefCounted
## Процедурная отрисовка персонажей, коней и значков. Все фигуры строятся
## из многоугольников, поэтому игре не нужны картинки.

const SKIN := Color("e0b48a")
const SHADOW := Color(0, 0, 0, 0.25)
const SEG := 20

static var UNIT := _unit_circle()


static func _unit_circle() -> PackedVector2Array:
	var a := PackedVector2Array()
	for i in SEG:
		a.append(Vector2.from_angle(TAU * i / SEG))
	return a


static func ell(ci: CanvasItem, xf: Transform2D, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(SEG)
	for i in SEG:
		pts[i] = xf * (c + UNIT[i] * Vector2(rx, ry))
	ci.draw_colored_polygon(pts, col)


static func line(ci: CanvasItem, xf: Transform2D, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(xf * a, xf * b, col, w)


static func rect(ci: CanvasItem, xf: Transform2D, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)])
	ci.draw_colored_polygon(pts, col)


static func man(ci: CanvasItem, pos: Vector2, ang: float, body: Color, hat: Color, gun := true, star := false, bandana := false) -> void:
	ell(ci, Transform2D(0.0, pos), Vector2(3, 4), 12, 12, SHADOW)
	var xf := Transform2D(ang, pos)
	if gun:
		line(ci, xf, Vector2(2, 6), Vector2(14, 4), SKIN, 4)
		line(ci, xf, Vector2(13, 4), Vector2(23, 4), Color("222222"), 3)
	ell(ci, xf, Vector2.ZERO, 8, 12, body)
	if star:
		ell(ci, xf, Vector2(2, -5), 2.5, 2.5, Color("e8c35a"))
	if bandana:
		rect(ci, xf, Rect2(4, -4, 4, 8), Color("b8392a"))
	ell(ci, xf, Vector2.ZERO, 10, 10, hat)
	ell(ci, xf, Vector2.ZERO, 6, 5.5, Color(1, 1, 1, 0.12))


static func corpse(ci: CanvasItem, pos: Vector2, ang: float, body: Color, hat: Color) -> void:
	var xf := Transform2D(ang, pos)
	ell(ci, xf, Vector2(2, 3), 16, 9, Color(0, 0, 0, 0.2))
	ell(ci, xf, Vector2.ZERO, 15, 8, body)
	ell(ci, xf, Vector2(14, 0), 5, 5, SKIN)
	ell(ci, xf, Vector2(24, 6), 7, 7, hat)


static func horse(ci: CanvasItem, pos: Vector2, ang: float, col: Color, saddle: bool, t: float) -> void:
	var xf := Transform2D(ang, pos)
	ell(ci, xf, Vector2(3, 4), 27, 12, SHADOW)
	line(ci, xf, Vector2(-24, 0), Vector2(-34, sin(t * 8.0) * 3.0), Color("2a1a10"), 3)
	ell(ci, xf, Vector2.ZERO, 24, 10, col)
	ell(ci, xf, Vector2(24, 0), 11, 6, col)
	rect(ci, xf, Rect2(12, -2, 12, 4), Color("2a1a10"))
	if saddle:
		rect(ci, xf, Rect2(-8, -8, 14, 16), Color("3a2412"))


static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + i * PI / 5) * rad)
	ci.draw_colored_polygon(pts, col)


static func cross(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w)
	ci.draw_line(c + Vector2(s, -s), c + Vector2(-s, s), col, w)


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align := 0) -> void:
	# align: 0 — по центру, -1 — слева, 1 — справа
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == 0:
		x -= w / 2.0
	elif align == 1:
		x -= w
	ci.draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func text_width(s: String, size: int) -> float:
	return ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
