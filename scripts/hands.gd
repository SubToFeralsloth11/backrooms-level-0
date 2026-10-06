class_name Hands
extends Node3D
## Procedurally built first-person forearms + articulated hands (3-bone fingers,
## 2-bone thumb, SSS skin, jacket sleeves). Right hand grips the flashlight;
## left hand hangs low, reaches for interactions, and holds journal pages.
## Motion: inertial sway, walk/run pumping synced to the step phase, breathing.

const SKIN := Color(0.66, 0.49, 0.4)

var flashlight: SpotLight3D
var lens_mat: StandardMaterial3D
var paper_label: Label3D
var paper: Node3D

var _skin: StandardMaterial3D
var _sleeve: StandardMaterial3D
var _right: Node3D
var _left: Node3D
var _r_fingers: Array = []
var _l_fingers: Array = []
var _r_rest := Vector3(0.2, -0.24, -0.4)
var _l_rest := Vector3(-0.3, -0.52, -0.28)
var _l_target := Vector3.ZERO
var _l_target_rot := Vector3.ZERO
var _reach := 0.0
var _reading := false
var _sway := Vector2.ZERO
var _sway_vel := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = SKIN
	_skin.roughness = 0.52
	_skin.subsurf_scatter_enabled = true
	_skin.subsurf_scatter_strength = 0.55
	_skin.subsurf_scatter_skin_mode = true
	_skin.rim_enabled = true
	_skin.rim = 0.15
	_skin.rim_tint = 0.6
	var pores := NoiseTexture2D.new()
	pores.width = 256
	pores.height = 256
	pores.seamless = true
	pores.as_normal_map = true
	pores.bump_strength = 3.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.22
	fn.fractal_octaves = 3
	pores.noise = fn
	_skin.normal_enabled = true
	_skin.normal_texture = pores
	_skin.normal_scale = 0.35
	_skin.uv1_scale = Vector3(6, 6, 6)

	_sleeve = StandardMaterial3D.new()
	_sleeve.albedo_color = Color(0.11, 0.12, 0.13)
	_sleeve.roughness = 0.95
	var weave := NoiseTexture2D.new()
	weave.width = 128
	weave.height = 128
	weave.seamless = true
	weave.as_normal_map = true
	weave.bump_strength = 5.0
	var wn := FastNoiseLite.new()
	wn.frequency = 0.5
	weave.noise = wn
	_sleeve.normal_enabled = true
	_sleeve.normal_texture = weave
	_sleeve.uv1_scale = Vector3(4, 4, 4)

	_right = _build_arm(1.0, _r_fingers)
	_left = _build_arm(-1.0, _l_fingers)
	_right.position = _r_rest
	_left.position = _l_rest
	_right.rotation = Vector3(0.1, 0.12, 0.0)
	_left.rotation = Vector3(0.25, -0.25, 0.35)
	_build_flashlight()
	_build_paper()
	_pose(_r_fingers, [1.35, 1.45, 1.5, 1.55], 1.0)
	_pose(_l_fingers, [0.35, 0.45, 0.55, 0.65], 0.4)


func _mi(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return c


## Arm local frame: wrist at origin, fingers point -Z, palm faces -Y (down), +X = thumb side for left.
func _build_arm(side: float, fingers: Array) -> Node3D:
	var arm := Node3D.new()
	add_child(arm)
	# Forearm: tapered, slightly flattened.
	var fa := CylinderMesh.new()
	fa.top_radius = 0.025
	fa.bottom_radius = 0.032
	fa.height = 0.3
	fa.radial_segments = 16
	var forearm := _mi(fa, _skin, arm, Vector3(0, 0, 0.15), Vector3(PI / 2, 0, 0))
	forearm.scale = Vector3(1.15, 1.0, 0.85)
	# Sleeve + cuff.
	var sl := CylinderMesh.new()
	sl.top_radius = 0.042
	sl.bottom_radius = 0.058
	sl.height = 0.42
	sl.radial_segments = 18
	_mi(sl, _sleeve, arm, Vector3(0, 0.002, 0.28), Vector3(PI / 2, 0, 0))
	var cuff := TorusMesh.new()
	cuff.inner_radius = 0.036
	cuff.outer_radius = 0.047
	cuff.rings = 16
	cuff.ring_segments = 8
	_mi(cuff, _sleeve, arm, Vector3(0, 0.002, 0.07), Vector3(PI / 2, 0, 0))
	# Wrist + palm (flattened ellipsoids give soft, fleshy volume).
	var wrist := SphereMesh.new()
	wrist.radius = 0.03
	wrist.height = 0.05
	_mi(wrist, _skin, arm, Vector3(0, 0, 0.0)).scale = Vector3(1.25, 0.8, 1.0)
	var palm := SphereMesh.new()
	palm.radius = 0.046
	palm.height = 0.09
	palm.radial_segments = 20
	palm.rings = 10
	var pm := _mi(palm, _skin, arm, Vector3(0, -0.002, -0.05))
	pm.scale = Vector3(1.0, 0.36, 1.05)
	# Knuckle ridge.
	var kn := CapsuleMesh.new()
	kn.radius = 0.011
	kn.height = 0.085
	_mi(kn, _skin, arm, Vector3(0, 0.006, -0.088), Vector3(0, 0, PI / 2))
	# Fingers: index..pinky across X; lengths of real phalanges (m).
	var lens := [[0.043, 0.026, 0.02], [0.047, 0.029, 0.021], [0.044, 0.027, 0.02], [0.034, 0.02, 0.018]]
	var radii := [0.0088, 0.009, 0.0085, 0.0075]
	for f in 4:
		var x := side * (-0.03 + f * 0.0205)
		var root := Node3D.new()
		root.position = Vector3(x, 0.0, -0.092 + absf(f - 1.4) * 0.006)
		root.rotation.y = side * (f - 1.5) * -0.05
		arm.add_child(root)
		var joints := []
		var parent := root
		for s in 3:
			var j := Node3D.new()
			parent.add_child(j)
			var L: float = lens[f][s]
			var r: float = radii[f] * (1.0 - s * 0.1)
			_mi(_capsule(r, L + r * 1.6), _skin, j, Vector3(0, 0, -L * 0.5), Vector3(PI / 2, 0, 0))
			if s == 2:  # fingernail
				var nail := BoxMesh.new()
				nail.size = Vector3(r * 1.5, 0.0015, L * 0.6)
				var nm := StandardMaterial3D.new()
				nm.albedo_color = Color(0.88, 0.72, 0.68)
				nm.roughness = 0.25
				_mi(nail, nm, j, Vector3(0, r * 0.92, -L * 0.6))
			joints.append(j)
			var next := Node3D.new()
			next.position = Vector3(0, 0, -L)
			j.add_child(next)
			parent = next
		fingers.append(joints)
	# Thumb: from the palm side, angled across.
	var troot := Node3D.new()
	troot.position = Vector3(-side * 0.035, -0.008, -0.025)
	troot.rotation = Vector3(0.2, -side * 0.75, -side * 0.6)
	arm.add_child(troot)
	var tj := []
	var tparent := troot
	for s in 3:
		var j := Node3D.new()
		tparent.add_child(j)
		var L: float = [0.035, 0.03, 0.024][s]
		var r: float = [0.013, 0.0105, 0.0095][s]
		_mi(_capsule(r, L + r * 1.6), _skin, j, Vector3(0, 0, -L * 0.5), Vector3(PI / 2, 0, 0))
		tj.append(j)
		var next := Node3D.new()
		next.position = Vector3(0, 0, -L)
		j.add_child(next)
		tparent = next
	fingers.append(tj)
	return arm


## curls: per finger base curl (rad); joints scale distally. thumb_curl for the thumb.
func _pose(fingers: Array, curls: Array, thumb_curl: float) -> void:
	for f in 4:
		var c: float = curls[f]
		fingers[f][0].rotation.x = -c * 0.85
		fingers[f][1].rotation.x = -c * 1.0
		fingers[f][2].rotation.x = -c * 0.7
	var th: Array = fingers[4]
	th[1].rotation.x = -thumb_curl * 0.5
	th[2].rotation.x = -thumb_curl * 0.6


func _build_flashlight() -> void:
	var body := Node3D.new()
	body.position = Vector3(0.006, -0.018, -0.07)
	_right.add_child(body)
	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color(0.06, 0.06, 0.065)
	alu.metallic = 0.85
	alu.roughness = 0.38
	var knurl := NoiseTexture2D.new()
	knurl.width = 64
	knurl.height = 64
	knurl.as_normal_map = true
	knurl.bump_strength = 8.0
	var kn := FastNoiseLite.new()
	kn.frequency = 0.6
	knurl.noise = kn
	alu.normal_enabled = true
	alu.normal_texture = knurl
	var tube := CylinderMesh.new()
	tube.top_radius = 0.0155
	tube.bottom_radius = 0.0155
	tube.height = 0.15
	tube.radial_segments = 20
	_mi(tube, alu, body, Vector3(0, 0, 0.0), Vector3(PI / 2, 0, 0))
	var head := CylinderMesh.new()
	head.top_radius = 0.0215
	head.bottom_radius = 0.016
	head.height = 0.045
	head.radial_segments = 20
	_mi(head, alu, body, Vector3(0, 0, -0.095), Vector3(-PI / 2, 0, 0))
	lens_mat = StandardMaterial3D.new()
	lens_mat.albedo_color = Color(0.8, 0.8, 0.75)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.92, 0.78)
	lens_mat.emission_energy_multiplier = 3.0
	var lens := CylinderMesh.new()
	lens.top_radius = 0.019
	lens.bottom_radius = 0.019
	lens.height = 0.002
	_mi(lens, lens_mat, body, Vector3(0, 0, -0.118), Vector3(PI / 2, 0, 0))
	var btn := BoxMesh.new()
	btn.size = Vector3(0.008, 0.004, 0.012)
	var rub := StandardMaterial3D.new()
	rub.albedo_color = Color(0.02, 0.02, 0.02)
	rub.roughness = 0.9
	_mi(btn, rub, body, Vector3(0, 0.016, 0.02))
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0, 0, -0.125)
	flashlight.light_color = Color(1.0, 0.93, 0.8)
	flashlight.light_energy = 2.4
	flashlight.spot_range = 18.0
	flashlight.spot_angle = 30.0
	flashlight.spot_angle_attenuation = 1.6  # soft spill falling off from the hotspot
	flashlight.spot_attenuation = 1.6
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.03
	flashlight.light_size = 0.02
	# cookie-like falloff via projector would be ideal; a soft inner spill light helps
	body.add_child(flashlight)


func _build_paper() -> void:
	paper = Node3D.new()
	paper.visible = false
	add_child(paper)
	paper.position = Vector3(-0.02, -0.035, -0.3)
	paper.rotation = Vector3(0.12, 0, 0.0)
	var mi := MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(0.21, 0.297)
	mi.mesh = pm
	var mat := preload("res://scripts/pickup.gd").paper_material()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paper.add_child(mi)
	paper_label = Label3D.new()
	if ResourceLoader.exists("res://fonts/journal.ttf"):
		paper_label.font = load("res://fonts/journal.ttf")
	paper_label.font_size = 52
	paper_label.pixel_size = 0.00025
	paper_label.width = 680
	paper_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	paper_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	paper_label.line_spacing = -6
	paper_label.modulate = Color(0.08, 0.08, 0.16)
	paper_label.outline_size = 0
	paper_label.shaded = false
	paper_label.position = Vector3(-0.0875, 0.138, 0.0008)  # Label3D box grows right from its origin
	paper.add_child(paper_label)


func set_reading(on: bool, text := "") -> void:
	_reading = on
	paper.visible = on
	if on:
		paper_label.text = text


## Brightness of the held page's ink (0..1), set by the player from local lighting.
func set_paper_light(v: float) -> void:
	paper_label.modulate.a = clampf(v, 0.08, 0.92)


func reach() -> void:
	_reach = 1.0


func set_flashlight_visual(on: bool, level: float) -> void:
	flashlight.visible = on and level > 0.0
	flashlight.light_energy = 2.4 * level
	lens_mat.emission_energy_multiplier = 3.0 * level if on else 0.0


## Called every frame by the player.
## step_phase: radians of gait cycle; speed01: 0 idle..1 sprint; look_delta: mouse delta this frame.
func animate(delta: float, step_phase: float, speed01: float, crouch01: float, look_delta: Vector2, wall_close: float) -> void:
	_t += delta
	# Inertial sway: hands lag behind camera rotation, spring back.
	_sway_vel += (-look_delta * 0.0009 - _sway * 60.0) * delta
	_sway_vel *= exp(-12.0 * delta)
	_sway += _sway_vel
	_sway = _sway.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))
	var breathe := sin(_t * 1.6) * 0.0035
	var pump := sin(step_phase) * 0.012 * speed01 * (1.0 + speed01 * 2.2)
	var lift := absf(cos(step_phase)) * 0.008 * speed01 * (1.0 + speed01)
	var pull_back := wall_close * 0.16
	# Right hand: flashlight aims slightly ahead of the view.
	var rp := _r_rest + Vector3(_sway.x - pump * 0.6, _sway.y + breathe - lift - crouch01 * 0.015, pull_back + pump * 0.4)
	_right.position = _right.position.lerp(rp, 1.0 - exp(-18.0 * delta))
	_right.rotation = Vector3(0.1 + _sway.y * 2.0 + pump * 2.0 + speed01 * 0.3, 0.12 + _sway.x * 2.0, -pump * 3.0)
	# Left hand: idle low, reach forward on interact, raise page when reading.
	_reach = maxf(0.0, _reach - delta * 2.4)
	var reach_curve := sin(_reach * PI)
	var lp := _l_rest + Vector3(_sway.x + pump * 0.6, _sway.y + breathe * 1.2 - lift + reach_curve * 0.14, pull_back - pump * 0.5 - reach_curve * 0.16)
	var lr := Vector3(0.25 + reach_curve * -0.35 + speed01 * 0.4, -0.25, 0.35 + pump * 3.0)
	if _reading:
		lp = Vector3(-0.115, -0.165, -0.34) + Vector3(_sway.x, _sway.y + breathe, 0)
		lr = Vector3(0.9, -0.15, 1.35)
		_pose(_l_fingers, [0.2, 0.25, 0.3, 0.35], -0.3)
	else:
		var c := 0.35 + reach_curve * -0.3
		_pose(_l_fingers, [c, c + 0.1, c + 0.2, c + 0.3], 0.4)
	_left.position = _left.position.lerp(lp, 1.0 - exp(-14.0 * delta))
	_left.rotation = _left.rotation.lerp(lr, 1.0 - exp(-12.0 * delta))
	if _reading:
		paper.position = paper.position.lerp(Vector3(-0.02, -0.03 + breathe, -0.3) + Vector3(_sway.x, _sway.y, 0) * 0.7, 1.0 - exp(-14.0 * delta))
