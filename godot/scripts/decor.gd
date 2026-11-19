extends Node2D
## Пучки травы и камешки одного участка карты (участки отсекаются при отрисовке).

var items: Array = [] # [позиция, вид, размер]


func _ready() -> void:
	z_index = -9


func _draw() -> void:
	for it in items:
		var p: Vector2 = it[0]
		var s: float = it[2]
		if it[1] == 0:
			for i in range(-2, 3):
				draw_line(p, p + Vector2(i * 3.0 * s, -7.0 * s), Color("7d7a3e"), 1.5)
		else:
			draw_circle(p, 2.5 * s, Color("9a8466"))
