extends Node3D
## Wall-mounted breaker box. Six switches (I..VI, left to right) + main lever.
## Correct pattern restores power to the exit hall (a muffled clunk). Wrong
## pattern: total blackout, a lever clang every entity hears, and
## Game.wrong_lever (wakes the Watcher early).

const ROMAN := ["I", "II", "III", "IV", "V", "VI"]
const BLACKOUT_TIME := 28.0

var puzzle: Puzzle
var switches := [0, 0, 0, 0, 0, 0]
var _levers: Array[Node3D] = []
var _flags: Array[StandardMaterial3D] = []
var _main: Node3D
var _busy := false
var _metal: StandardMaterial3D


func _ready() -> void:
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.62, 0.64, 0.6)
	_metal.metallic = 0.7
	_metal.roughness = 0.5
	var mtex := load("res://textures/metal_albedo.png") if ResourceLoader.exists("res://textures/metal_albedo.png") else null
	if mtex:
		_metal.albedo_texture = mtex
		_metal.albedo_color = Color(1.0, 1.0, 0.96)
	_box(Vector3(0.78, 0.9, 0.14), Vector3(0, 0, 0.07), _metal)
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.34, 0.33, 0.3)
	inner.roughness = 0.8
	_box(Vector3(0.68, 0.78, 0.01), Vector3(0, 0, 0.142), inner)
	# Open door hanging off the left hinge.
	var door := _box(Vector3(0.76, 0.88, 0.012), Vector3(-0.39, 0, 0.14 + 0.38), _metal)
	door.rotation.y = -PI / 2.15
	door.position = Vector3(-0.39 - 0.02, 0, 0.14 + 0.38)
	_label("DANGER\n480 V", Vector3(-0.39, 0.2, 0.53), Color(0.8, 0.1, 0.05), 0.0028, Vector3(0, -PI / 2.15 + PI, 0))
	_label("MAIN DISTRIBUTION  B4", Vector3(0, 0.34, 0.15), Color(1, 1, 0.95), 0.0012)

	for i in 6:
		var x := -0.24 + i * 0.075
		_label(ROMAN[i], Vector3(x, 0.13, 0.15), Color(1, 1, 0.95), 0.0016)
		_label("ON", Vector3(x, 0.085, 0.163), Color(1, 0.85, 0.6), 0.0008)
		_label("OFF", Vector3(x, -0.085, 0.163), Color(0.85, 0.9, 1), 0.0008)
		# Mechanical flag window: bright red when up/ON, pale when down/OFF.
		var flag := StandardMaterial3D.new()
		flag.emission_enabled = true
		_box(Vector3(0.042, 0.022, 0.004), Vector3(x, -0.118, 0.153), flag)
		_flags.append(flag)
		var pivot := Node3D.new()
		pivot.position = Vector3(x, 0.0, 0.15)
		add_child(pivot)
		var handle_mat := StandardMaterial3D.new()
		handle_mat.albedo_color = Color(0.78, 0.76, 0.7)  # worn cream bakelite toggle
		handle_mat.roughness = 0.35
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.4, 0.4, 0.38)
		base_mat.roughness = 0.5
		_box(Vector3(0.05, 0.11, 0.02), Vector3(x, 0, 0.152), base_mat)
		var handle := _box(Vector3(0.026, 0.06, 0.026), Vector3(0, 0.032, 0.025), handle_mat, pivot)
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
	var flag := _flags[i]
	flag.albedo_color = Color(0.9, 0.08, 0.04) if switches[i] == 1 else Color(0.7, 0.72, 0.7)
	flag.emission = flag.albedo_color
	flag.emission_energy_multiplier = 0.6 if switches[i] == 1 else 0.08
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
	var right: bool = puzzle.mask_matches(switches)
	if right:
		# A clean throw: a dull clunk that carries only through the wing.
		Audio.play_3d("breaker_switch", global_position, 0.0, 30.0, 0.0)
		Game.emit_noise(global_position, 30.0, "lever")
	else:
		# Arcing on a bad pattern: the clang carries through the whole level.
		Audio.play_3d("breaker_switch", global_position, 6.0, 60.0, 0.0)
		Game.emit_noise(global_position, 70.0, "lever")
	await get_tree().create_timer(0.6, false).timeout
	if right:
		Audio.play_3d("power_on", global_position, 2.0, 80.0, 0.0)
		Game.set_power(true)
		await get_tree().create_timer(2.5, false).timeout
		Game.say("breaker_done")
	else:
		Audio.play_2d("light_pop", -2.0)
		Game.wrong_lever.emit()
		Game.set_blackout(true)
		Game.say("dark")
		await get_tree().create_timer(BLACKOUT_TIME, false).timeout
		Game.set_blackout(false)
		Audio.play_2d("power_on", -10.0)
		var back := create_tween()
		back.tween_property(_main, "rotation:x", 0.7, 0.5)
	_busy = false
