class_name Interactable
extends StaticBody3D
## Thin collider the player's look-ray hits. Layer 4 (value 8).

const LAYER := 8

var prompt := ""
var action: Callable
var enabled := true


func _init(p := "", cb := Callable()) -> void:
	prompt = p
	action = cb
	collision_layer = LAYER
	collision_mask = 0


func add_box(size: Vector3, offset := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	add_child(cs)


func interact(player: Node) -> void:
	if enabled and action.is_valid():
		action.call(player)
