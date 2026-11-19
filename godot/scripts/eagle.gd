extends Node3D
## Орёл кружит высоко над пустыней (только для атмосферы).

const AnimalModel := preload("res://scripts/animal_model.gd")

var center := Vector3.ZERO
var radius := 60.0
var height := 45.0
var speed := 0.12
var t := 0.0
var model: Node3D


func _ready() -> void:
	model = AnimalModel.new()
	add_child(model)
	model.setup("eagle", 2.2, PI / 2.0, "CINEMA")
	t = randf() * TAU
	speed *= 1.0 if randf() < 0.5 else -1.0


func _process(delta: float) -> void:
	t += delta * speed
	var p := center + Vector3(cos(t) * radius, height + sin(t * 2.3) * 4.0, sin(t) * radius)
	var vel := Vector3(-sin(t), 0, cos(t)) * signf(speed)
	global_position = p
	rotation.y = atan2(-vel.x, -vel.z)
	rotation.z = -0.35 * signf(speed) # крен в вираже
