extends Node3D
## Heavy steel door set into the south border wall. Local origin: bottom centre
## of the 1.5 m opening, room side = -Z. Behind it a concrete stairwell and the
## escape trigger.

var level: Level
var _leaf: Node3D
var _block: StaticBody3D
var _open := false


func _ready() -> void:
	var metal: StandardMaterial3D = level._mat.metal
	var concrete: StandardMaterial3D = level._mat.concrete
	var wall: StandardMaterial3D = level._mat.wall
	var h := Level.WALL_H
	var w := Level.CELL * 2.0
	# Lintel above the door (the border wall cells were carved full-height).
	_box(Vector3(w, h - 2.1, Level.CELL), Vector3(0, 2.1 + (h - 2.1) * 0.5, Level.CELL * 0.5), wall, true)
	# Frame
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.22, 0.23, 0.22)
	frame.metallic = 0.7
	frame.roughness = 0.5
	_box(Vector3(0.07, 2.1, 0.2), Vector3(-w * 0.5 + 0.035, 1.05, 0.02), frame, false)
	_box(Vector3(0.07, 2.1, 0.2), Vector3(w * 0.5 - 0.035, 1.05, 0.02), frame, false)
	_box(Vector3(w, 0.07, 0.2), Vector3(0, 2.065, 0.02), frame, false)
	# Door leaf on a hinge at the left edge, swings outward (+Z).
	_leaf = Node3D.new()
	_leaf.position = Vector3(-w * 0.5 + 0.07, 0, 0.05)
	add_child(_leaf)
	var leaf := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(w - 0.14, 2.03, 0.06)
	lb.material = metal
	leaf.mesh = lb
	leaf.position = Vector3((w - 0.14) * 0.5, 1.015, 0)
	_leaf.add_child(leaf)
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(w * 0.6, 0.05, 0.05)
	bb.material = frame
	bar.mesh = bb
	bar.position = Vector3((w - 0.14) * 0.55, 1.0, -0.06)
	_leaf.add_child(bar)
	var stencil := Label3D.new()
	stencil.text = "NO RE-ENTRY"
	if ResourceLoader.exists("res://fonts/sign.ttf"):
		stencil.font = load("res://fonts/sign.ttf")
	stencil.font_size = 64
	stencil.pixel_size = 0.0018
	stencil.modulate = Color(0.75, 0.72, 0.6)
	stencil.outline_size = 0
	stencil.shaded = true
	stencil.rotation.y = PI
	stencil.position = Vector3((w - 0.14) * 0.5, 1.55, -0.032)
	_leaf.add_child(stencil)
	_block = StaticBody3D.new()
	_block.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 2.1, 0.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.05, 0.05)
	_block.add_child(cs)
	add_child(_block)

	# Stairwell beyond: concrete box, a single caged bulb.
	var depth := 4.0
	_box(Vector3(0.2, h, depth), Vector3(-w * 0.5 - 0.1, h * 0.5, Level.CELL + depth * 0.5 - 0.6), concrete, true)
	_box(Vector3(0.2, h, depth), Vector3(w * 0.5 + 0.1, h * 0.5, Level.CELL + depth * 0.5 - 0.6), concrete, true)
	_box(Vector3(w + 0.4, h, 0.2), Vector3(0, h * 0.5, Level.CELL + depth - 0.5), concrete, true)
	_box(Vector3(w, 0.05, depth), Vector3(0, 0.025, Level.CELL + depth * 0.5 - 0.6), concrete, false)
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.85, 0.6)
	bulb.light_energy = 1.4
	bulb.omni_range = 4.0
	bulb.position = Vector3(0, h - 0.3, Level.CELL + depth * 0.5)
	bulb.visible = false
	bulb.name = "Bulb"
	add_child(bulb)

	var trig := Area3D.new()
	trig.collision_layer = 0
	trig.collision_mask = 2
	var tcs := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(w, 2.0, 1.0)
	tcs.shape = tb
	tcs.position = Vector3(0, 1.0, Level.CELL + 1.6)
	trig.add_child(tcs)
	add_child(trig)
	trig.body_entered.connect(func(_b): Game.win())


func _box(size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		sb.position = pos
		add_child(sb)


func open() -> void:
	if _open:
		return
	_open = true
	await get_tree().create_timer(0.8).timeout
	Audio.play_3d("door_heavy_open", global_position + Vector3(0, 1.2, 0), 2.0, 40.0, 0.0)
	Game.emit_noise(global_position, 30.0, "door")
	get_node("Bulb").visible = true
	var tw := create_tween()
	tw.tween_property(_leaf, "rotation:y", -1.75, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.5).timeout
	_block.queue_free()
