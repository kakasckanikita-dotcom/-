extends Node3D
## Мешочек, выпавший с бандита: деньги и патроны.

var money := 5
var ammo := 3
var title := "" # «Шкура койота» и т.п.
var t := 0.0
var bag: Node3D


func _ready() -> void:
	add_to_group("loot")
	bag = Node3D.new()
	add_child(bag)
	Mk.sphere(bag, 0.22, Vector3(0, 0.25, 0), Color("6a4520"), Vector3(1, 0.8, 1))
	var coin := Mk.cyl(bag, 0.09, 0.09, 0.03, Vector3(0, 0.5, 0), Color("e8c35a"), 10, Vector3(PI / 2.0, 0, 0))
	coin.material_override = Mk.mat(Color("e8c35a"), 0.3, 1.5)


func _process(delta: float) -> void:
	t += delta
	bag.rotation.y = t * 1.5
	bag.position.y = sin(t * 3.0) * 0.05
