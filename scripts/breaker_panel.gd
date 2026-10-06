extends Node3D
## Wall-mounted breaker box. Six switches (I..VI, left to right) + main lever.
## Correct pattern restores power to the exit hall. Wrong pattern: total
## blackout and a lever clang every entity hears.

const ROMAN := ["I", "II", "III", "IV", "V", "VI"]
const BLACKOUT_TIME := 28.0

var puzzle: Puzzle
var switches := [0, 0, 0, 0, 0, 0]
var _levers: Array[Node3D] = []
var _main: Node3D
var _busy := false
var _metal: StandardMaterial3D


func _ready() -> void:
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.42, 0.44, 0.42)
	_metal.metallic = 0.7
	_metal.roughness = 0.5
	var mtex := load("res://textures/metal_albedo.png") if ResourceLoader.exists("res://textures/metal_albedo.png") else null
	if mtex:
		_metal.albedo_texture = mtex
		_metal.albedo_color = Color(0.8, 0.82, 0.8)
	_box(Vector3(0.78, 0.9, 0.14), Vector3(0, 0, 0.07), _metal)
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.1, 0.1, 0.1)
	inner.roughness = 0.8
	_box(Vector3(0.68, 0.78, 0.01), Vector3(0, 0, 0.142), inner)
	# Open door hanging off the left hinge.
	var door := _box(Vector3(0.76, 0.88, 0.012), Vector3(-0.39, 0, 0.14 + 0.38), _metal)
	door.rotation.y = -PI / 2.15
	door.position = Vector3(-0.39 - 0.02, 0, 0.14 + 0.38)
	_label("DANGER\n480 V", Vector3(-0.39, 0.2, 0.53), Color(0.8, 0.1, 0.05), 0.0028, Vector3(0, -PI / 2.15 + PI, 0))
	_label("MAIN DISTRIBUTION  B4", Vector3(0, 0.34, 0.15), Color(0.9, 0.9, 0.85), 0.0012)

	for i in 6:
		var x := -0.24 + i * 0.075
		_label(ROMAN[i], Vector3(x, 0.13, 0.15), Color(0.92, 0.92, 0.85), 0.0016)
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 0.0, 0.15)
		add_child(pivot)
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.05, 0.05, 0.05)
		black.roughness = 0.4
		_box(Vector3(0.05, 0.11, 0.02), Vector3(x, 0, 0.145), inner)
		var handle := _box(Vector3(0.028, 0.055, 0.028), Vector3(0, 0.03, 0.02), black, pivot)
		handle.name = "Handle"
		_levers.append(pivot)
		_set_lever(i, false)
		var hit := Interactable.new("Flip breaker %s" % ROMAN[i], _flip.bind(i))
		hit.add_box(Vector3(0.06, 0.12, 0.08))
		hit.position = Vector3(x, 0, 0.17)
		add_child(hit)

	# Main lever (big, red handle) on the right.
	_main = Node3D.new()
	_main.position = Vector3(0.26, 0.0, 0.16)
	add_child(_main)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.05, 0.03)
	red.roughness = 0.45
	_box(Vector3(0.025, 0.2, 0.025), Vector3(0, 0.1, 0.02), _metal, _main)
	_box(Vector3(0.09, 0.035, 0.04), Vector3(0, 0.2, 0.03), red, _main)
	_main.rotation.x = 0.7
	_label("MAIN", Vector3(0.26, -0.22, 0.15), Color(0.9, 0.9, 0.85), 0.0015)
	var mh := Interactable.new("Pull main lever", _pull_main)
	mh.add_box(Vector3(0.12, 0.3, 0.1), Vector3(0, 0.08, 0))
	mh.position = Vector3(0.26, 0, 0.18)
	add_child(mh)


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label(t: String, pos: Vector3, col: Color, px: float, rot := Vector3.ZERO) -> void:
	var l := Label3D.new()
	l.text = t
	if ResourceLoader.exists("res://fonts/sign.ttf"):
		l.font = load("res://fonts/sign.ttf")
	l.font_size = 48
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.rotation = rot
	add_child(l)


func _set_lever(i: int, animate: bool) -> void:
	var target := -0.55 if switches[i] == 1 else 0.55  # up = tipped toward ceiling
	if animate:
		create_tween().tween_property(_levers[i], "rotation:x", target, 0.07)
	else:
		_levers[i].rotation.x = target


func _flip(_player: Node, i: int) -> void:
	if _busy or Game.power_on:
		return
	switches[i] = 1 - switches[i]
	_set_lever(i, true)
	Audio.play_3d("breaker_switch", global_position, -2.0, 25.0, 0.08)
	Game.emit_noise(global_position, 6.0, "breaker")


func _pull_main(_player: Node) -> void:
	if _busy or Game.power_on:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_main, "rotation:x", -0.7, 0.35).set_trans(Tween.TRANS_BACK)
	await tw.finished
	Audio.play_3d("breaker_switch", global_position, 6.0, 60.0, 0.0)
	# The clunk of a main breaker carries through the whole level.
	Game.emit_noise(global_position, 70.0, "lever")
	await get_tree().create_timer(0.6).timeout
	if puzzle.mask_matches(switches):
		Audio.play_3d("power_on", global_position, 2.0, 80.0, 0.0)
		Game.set_power(true)
		await get_tree().create_timer(2.5).timeout
		Game.say("breaker_done")
	else:
		Audio.play_2d("light_pop", -2.0)
		Game.set_blackout(true)
		Game.say("dark")
		await get_tree().create_timer(BLACKOUT_TIME).timeout
		Game.set_blackout(false)
		Audio.play_2d("power_on", -10.0)
		var back := create_tween()
		back.tween_property(_main, "rotation:x", 0.7, 0.5)
	_busy = false
