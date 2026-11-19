extends StaticBody2D
## Здание города. Узел стоит у нижнего края, чтобы правильно сортироваться по Y.

const NAMES := {"saloon": "САЛУН", "store": "ЛАВКА", "sheriff": "ШЕРИФ", "bank": "БАНК", "house": ""}
const ROOF := {"saloon": Color("7b3b22"), "store": Color("5d6b3a"), "sheriff": Color("4a4f5c"), "bank": Color("6d6553"), "house": Color("7a5a3a")}

var rect: Rect2 # в мировых координатах
var type := "house"
var door := Vector2.ZERO
var town: Dictionary


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = rect.size
	cs.shape = s
	cs.position = Vector2(0, -rect.size.y / 2.0)
	add_child(cs)


func _draw() -> void:
	var r := Rect2(rect.position - position, rect.size)
	draw_rect(Rect2(r.position + Vector2(8, 8), r.size), Color(0, 0, 0, 0.28))
	draw_rect(r, Color("8a6440"))
	draw_rect(r.grow(-4), ROOF[type])
	var x := r.position.x + 12.0
	while x < r.end.x - 4:
		draw_line(Vector2(x, r.position.y + 4), Vector2(x, r.end.y - 4), Color(0, 0, 0, 0.25), 1.0)
		x += 10.0
	draw_line(Vector2(r.position.x + 4, r.get_center().y), Vector2(r.end.x - 4, r.get_center().y), Color(0, 0, 0, 0.4), 3.0)
	var south := door.y > rect.get_center().y
	var porch_y := r.end.y if south else r.position.y - 14.0
	draw_rect(Rect2(r.position.x, porch_y, r.size.x, 14), Color("6e4a2c"))
	var dl := door - position
	draw_rect(Rect2(dl.x - 12, (r.end.y - 4) if south else r.position.y, 24, 4), Color("3a2412"))
	var nm: String = NAMES[type]
	if nm != "":
		var sy := r.end.y - 26.0 if south else r.position.y + 8.0
		var sr := Rect2(r.get_center().x - 42, sy, 84, 20)
		draw_rect(sr, Color("e9d6ae"))
		draw_rect(sr, Color("3a2412"), false, 2.0)
		Gfx.text(self, Vector2(sr.get_center().x, sy + 15), nm, 13, Color("3a2412"))
