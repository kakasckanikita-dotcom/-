extends Node2D
## Бандитский лагерь: палатки и костёр, который ночью светит.

var camp_name := ""
var tents: Array = [] # [смещение, угол]
var cleared := false
var timer := 0.0
var known := false
var t := 0.0
var light: PointLight2D


func _ready() -> void:
	z_index = -5
	light = PointLight2D.new()
	light.texture = Game.light_texture()
	light.texture_scale = 2.2
	light.color = Color(1.0, 0.6, 0.25)
	add_child(light)


func _process(delta: float) -> void:
	t += delta
	light.energy = 0.0 if cleared else Game.darkness() * 2.2 * (0.9 + 0.1 * sin(t * 20.0))
	if not cleared:
		queue_redraw()
		if randf() < 0.3:
			Game.world.fx.add(global_position + Vector2(randf_range(-4, 4), 0), Vector2(randf_range(-8, 8), -randf_range(20, 40)), 1.2, Color(0.5, 0.5, 0.5, 0.5), 4.0)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 130.0, Color(0.35, 0.24, 0.12, 0.3))
	for tent in tents:
		var xf := Transform2D(tent[1], tent[0])
		Gfx.rect(self, xf, Rect2(-20, -14, 46, 32), Color(0, 0, 0, 0.25))
		Gfx.rect(self, xf, Rect2(-22, -18, 44, 32), Color("cbb894"))
		Gfx.rect(self, xf, Rect2(-22, -2, 44, 16), Color("a8946e"))
		Gfx.line(self, xf, Vector2(-22, -2), Vector2(22, -2), Color("6b5a3a"), 1.0)
	for i in 7:
		draw_circle(Vector2.from_angle(i / 7.0 * TAU) * 14.0, 4.0, Color("555555"))
	if cleared:
		draw_circle(Vector2.ZERO, 8.0, Color("333333"))
	else:
		var f := sin(t * 12.0) * 2.0
		draw_circle(Vector2.ZERO, 9.0 + f, Color("e8701a"))
		draw_circle(Vector2.ZERO, 5.0 - f * 0.5, Color("ffd27a"))
