extends Node2D
## Мешочек, выпавший с бандита: деньги и патроны.

var money := 5
var ammo := 3


func _ready() -> void:
	z_index = -4
	add_to_group("loot")


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color("5a3a1a"))
	draw_circle(Vector2(0, -1), 2.0, Color("e8c35a"))
