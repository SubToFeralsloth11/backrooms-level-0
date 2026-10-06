extends RigidBody3D
## Thrown almond-water bottle: its first hard impact is a loud distraction.

var _impacts := 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	mass = 0.6
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 0.033
	c.height = 0.23
	cs.shape = c
	cs.position.y = 0.11
	add_child(cs)
	add_child(preload("res://scripts/pickup.gd").bottle_mesh())
	body_entered.connect(_on_hit)
	get_tree().create_timer(40.0).timeout.connect(queue_free)


func _on_hit(_body: Node) -> void:
	var v := linear_velocity.length()
	if v < 1.2 or _impacts >= 3:
		return
	_impacts += 1
	var loud := clampf(v / 8.0, 0.3, 1.0)
	Audio.play_3d("bottle_impact", global_position, lerpf(-12.0, 2.0, loud), 45.0, 0.12)
	Game.emit_noise(global_position, 24.0 * loud, "bottle")
