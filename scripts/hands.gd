class_name Hands
extends Node3D
## First-person arms: skinned hand models (models/hands, WebXR generic hand,
## 25-joint rig) posed per finger, on procedural forearms with jacket sleeves
## that hinge at the wrist and reach back to a fixed elbow. Right hand grips a
## procedural flashlight; left hand hangs low, reaches for interactions, holds
## journal pages, swaps batteries and throws.
## Motion: inertial sway, walk/run pumping synced to the step phase, breathing,
## fear tremor. The beam is decoupled from the hand: it follows the camera with
## a slight lag, so running and sway never throw the light around.

const SKIN := Color(0.72, 0.53, 0.43)
const HAND_MODEL := "res://models/hands/%s.glb"
const FINGERS := ["index-finger", "middle-finger", "ring-finger", "pinky-finger"]
const BEAM_LAG := 14.0

var flashlight: SpotLight3D
var lens_mat: StandardMaterial3D
var paper_label: Label3D
var paper: Node3D

var _skin: StandardMaterial3D
var _sleeve: StandardMaterial3D
var _right: Node3D
var _left: Node3D
var _r_forearm: Node3D
var _l_forearm: Node3D
var _r_rig := {}
var _l_rig := {}
var _torch: Node3D
var _lens_anchor: Node3D
var _r_rest := Vector3(0.17, -0.22, -0.36)
var _l_rest := Vector3(-0.3, -0.5, -0.28)
var _r_elbow := Vector3(0.3, -0.62, 0.02)
var _l_elbow := Vector3(-0.34, -0.72, 0.06)
var _r_basis := Basis()
var _reach := 0.0
var _reading := false
var _swap := 0.0
var _throw := 0.0
var _fumble := 0.0
var _fear := 0.0
var _sway := Vector2.ZERO
var _sway_vel := Vector2.ZERO
var _beam_q := Quaternion.IDENTITY
var _beam_init := false
var _t := 0.0


func _ready() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = SKIN
	_skin.roughness = 0.55
	_skin.subsurf_scatter_enabled = true
	_skin.subsurf_scatter_strength = 0.6
	_skin.subsurf_scatter_skin_mode = true
	_skin.rim_enabled = true
	_skin.rim = 0.18
	_skin.rim_tint = 0.65
	_skin.normal_enabled = true
	_skin.normal_texture = _noise_tex(256, 0.22, 3.0, true)
	_skin.normal_scale = 0.3
	# Blotchy roughness: oilier knuckles/palm, drier backs.
	_skin.roughness_texture = _noise_tex(128, 0.05, 0.0, false)
	_skin.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	_skin.uv1_triplanar = true
	_skin.uv1_scale = Vector3(18, 18, 18)

	_sleeve = StandardMaterial3D.new()
	_sleeve.albedo_color = Color(0.11, 0.12, 0.13)
	_sleeve.roughness = 0.95
	_sleeve.normal_enabled = true
	_sleeve.normal_texture = _noise_tex(128, 0.5, 5.0, true)
	_sleeve.uv1_scale = Vector3(4, 4, 4)

	_right = Node3D.new()
	add_child(_right)
	_left = Node3D.new()
	add_child(_left)
	_r_rig = _load_hand("right", _right)
	_l_rig = _load_hand("left", _left)
	_r_forearm = _build_forearm()
	_l_forearm = _build_forearm()
	_r_basis = _grip_basis()
	_right.position = _r_rest
	_right.basis = _r_basis
	_left.position = _l_rest
	_left.rotation = Vector3(0.25, -0.25, 0.35)
	_build_flashlight()
	_build_paper()
	_pose(_r_rig, [1.25, 1.3, 1.35, 1.4], 0.9)
	_pose(_l_rig, [0.35, 0.45, 0.55, 0.65], 0.3)


func _noise_tex(size: int, freq: float, bump: float, normal: bool) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = normal
	if normal:
		t.bump_strength = bump
	else:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.38, 0.38, 0.38))
		ramp.set_color(1, Color(0.72, 0.72, 0.72))
		t.color_ramp = ramp
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	fn.fractal_octaves = 3
	t.noise = fn
	return t


func _mi(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(r_top: float, r_bottom: float, h: float, seg := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Instances the skinned hand under `parent`, re-framed so the wrist joint is the
## origin, fingers point -Z, the palm faces -Y and the thumb points inward
## (-X right hand, +X left hand). The source rig: fingers -Y, back of hand ±X.
func _load_hand(side: String, parent: Node3D) -> Dictionary:
	var model: Node3D = load(HAND_MODEL % side).instantiate()
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var s := 1.0 if side == "right" else -1.0
	var b := Basis(Vector3(0, s, 0), Vector3(0, 0, 1), Vector3(s, 0, 0))
	var wrist := sk.get_bone_global_rest(sk.find_bone("wrist")).origin
	model.transform = Transform3D(b, -(b * wrist))
	parent.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _skin
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The rig is flat (every joint is a root, posed in skeleton space, as WebXR
	# hand tracking delivers them), so finger curls are chained here by FK.
	var fingers := []
	for f in FINGERS:
		var chain := []
		for j in ["phalanx-proximal", "phalanx-intermediate", "phalanx-distal", "tip"]:
			chain.append(sk.find_bone("%s-%s" % [f, j]))
		fingers.append(chain)
	var thumb := []
	for j in ["metacarpal", "phalanx-proximal", "phalanx-distal", "tip"]:
		thumb.append(sk.find_bone("thumb-" + j))
	var rest := {}
	for i in sk.get_bone_count():
		rest[i] = sk.get_bone_rest(i)
	return {"sk": sk, "fingers": fingers, "thumb": thumb, "rest": rest, "side": s}


## Forearm skin + sleeve + cuff, local +Z runs from the wrist (origin) to the elbow.
func _build_forearm() -> Node3D:
	var fa := Node3D.new()
	add_child(fa)
	var skin := _mi(_cyl(0.024, 0.03, 0.16, 16), _skin, fa, Vector3(0, 0, 0.07), Vector3(PI / 2, 0, 0))
	skin.scale = Vector3(1.15, 1.0, 0.8)
	_mi(_cyl(0.04, 0.058, 0.62, 18), _sleeve, fa, Vector3(0, 0.0, 0.38), Vector3(PI / 2, 0, 0))
	var cuff := TorusMesh.new()
	cuff.inner_radius = 0.034
	cuff.outer_radius = 0.046
	cuff.rings = 16
	cuff.ring_segments = 8
	_mi(cuff, _sleeve, fa, Vector3(0, 0, 0.075), Vector3(PI / 2, 0, 0))
	return fa


## Right-hand orientation that holds the diagonally gripped torch level and
## forward with the palm turned inward (thumb on top).
func _grip_basis() -> Basis:
	var t_h := Vector3(-0.42, 0.0, -1.0).normalized()
	var p_h := Vector3(0, -1, 0)
	var t_w := Vector3(-0.04, 0.02, -1.0).normalized()
	var p_w := Vector3(-1.0, -0.55, 0.0)
	p_w = (p_w - t_w * p_w.dot(t_w)).normalized()
	var hand := Basis(t_h, p_h, t_h.cross(p_h))
	var world := Basis(t_w, p_w, t_w.cross(p_w))
	return world * hand.transposed()


## curls: per finger base curl (rad), joints scale distally. thumb_curl for the thumb.
func _pose(rig: Dictionary, curls: Array, thumb_curl: float) -> void:
	for f in 4:
		var c: float = curls[f]
		_curl_chain(rig, rig.fingers[f], [c * 0.9, c * 1.05, c * 0.7], Vector3.RIGHT)
	var tc := thumb_curl
	_curl_chain(rig, rig.thumb, [tc * 0.3, tc * 0.55, tc * 0.7], Vector3.RIGHT)


## Flexes joint k of `chain` by angles[k] about its local `axis` (palm-ward for
## negative X in the WebXR joint frame: -Z toward the tip, +Y dorsal) and carries
## every distal joint along.
func _curl_chain(rig: Dictionary, chain: Array, angles: Array, axis: Vector3) -> void:
	var sk: Skeleton3D = rig.sk
	var rest: Dictionary = rig.rest
	var prev_rest: Transform3D = rest[chain[0]]
	var cur: Transform3D = prev_rest
	for k in chain.size():
		var bi: int = chain[k]
		var r: Transform3D = rest[bi]
		if k > 0:
			cur = cur * (prev_rest.affine_inverse() * r)
		prev_rest = r
		if k < angles.size():
			cur = cur * Transform3D(Basis(axis, -float(angles[k])), Vector3.ZERO)
		sk.set_bone_pose_position(bi, cur.origin)
		sk.set_bone_pose_rotation(bi, cur.basis.get_rotation_quaternion())


## Procedural aluminium torch: knurled grip, tail cap, flared head with
## reflector and lens, rubber switch, pocket clip. Axis runs along the grip
## diagonal of the right palm.
func _build_flashlight() -> void:
	_torch = Node3D.new()
	_torch.position = Vector3(0.0, -0.034, -0.062)
	_right.add_child(_torch)
	var axis := Basis.looking_at(Vector3(-0.42, 0.0, -1.0).normalized(), Vector3.UP)
	_torch.basis = axis  # torch -Z = beam direction
	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color(0.07, 0.07, 0.075)
	alu.metallic = 0.8
	alu.roughness = 0.42
	var knurl := StandardMaterial3D.new()
	knurl.albedo_color = Color(0.06, 0.06, 0.065)
	knurl.metallic = 0.75
	knurl.roughness = 0.55
	var kt := NoiseTexture2D.new()
	kt.width = 64
	kt.height = 64
	kt.seamless = true
	kt.as_normal_map = true
	kt.bump_strength = 12.0
	var kn := FastNoiseLite.new()
	kn.noise_type = FastNoiseLite.TYPE_CELLULAR
	kn.frequency = 0.35
	kt.noise = kn
	knurl.normal_enabled = true
	knurl.normal_texture = kt
	knurl.uv1_scale = Vector3(6, 3, 1)
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.85, 0.85, 0.85)
	chrome.metallic = 1.0
	chrome.roughness = 0.08
	var rub := StandardMaterial3D.new()
	rub.albedo_color = Color(0.025, 0.025, 0.025)
	rub.roughness = 0.9
	var down := Vector3(PI / 2, 0, 0)
	# Body: tail cap, knurled grip, smooth neck, flared head.
	_mi(_cyl(0.0145, 0.0145, 0.022), alu, _torch, Vector3(0, 0, 0.086), down)
	_mi(_cyl(0.0152, 0.0152, 0.004), rub, _torch, Vector3(0, 0, 0.074), down)
	_mi(_cyl(0.0152, 0.0152, 0.1, 24), knurl, _torch, Vector3(0, 0, 0.022), down)
	_mi(_cyl(0.0145, 0.0145, 0.02), alu, _torch, Vector3(0, 0, -0.038), down)
	_mi(_cyl(0.0215, 0.0148, 0.04, 24), alu, _torch, Vector3(0, 0, -0.068), down)
	_mi(_cyl(0.0225, 0.0225, 0.006, 24), alu, _torch, Vector3(0, 0, -0.091), down)
	# Grip rings.
	for z in [-0.01, 0.054]:
		_mi(_cyl(0.0158, 0.0158, 0.003), alu, _torch, Vector3(0, 0, z), down)
	# Reflector cone + lens.
	var refl := _cyl(0.019, 0.005, 0.014, 24)
	_mi(refl, chrome, _torch, Vector3(0, 0, -0.087), down)
	lens_mat = StandardMaterial3D.new()
	lens_mat.albedo_color = Color(0.8, 0.8, 0.75, 0.55)
	lens_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens_mat.roughness = 0.05
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.92, 0.78)
	lens_mat.emission_energy_multiplier = 3.0
	_mi(_cyl(0.0195, 0.0195, 0.0015), lens_mat, _torch, Vector3(0, 0, -0.0945), down)
	# Rubber switch on top + pocket clip.
	_mi(_cyl(0.005, 0.0055, 0.004, 12), rub, _torch, Vector3(0, 0.0155, -0.03))
	var clip := BoxMesh.new()
	clip.size = Vector3(0.006, 0.0015, 0.06)
	_mi(clip, alu, _torch, Vector3(0.0, -0.0168, 0.04))
	_lens_anchor = Node3D.new()
	_lens_anchor.position = Vector3(0, 0, -0.1)
	_torch.add_child(_lens_anchor)
	flashlight = SpotLight3D.new()
	flashlight.top_level = true
	flashlight.light_color = Color(1.0, 0.93, 0.8)
	flashlight.light_energy = 2.4
	flashlight.spot_range = 18.0
	flashlight.spot_angle = 30.0
	flashlight.spot_angle_attenuation = 1.6  # soft spill falling off from the hotspot
	flashlight.spot_attenuation = 1.6
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.03
	flashlight.light_size = 0.02
	add_child(flashlight)


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


## Left hand twists the tail cap off, swaps cells, screws it back (~0.9 s).
func swap_batteries() -> void:
	_swap = 1.0


## Wind-up (back) then release (forward) with the left hand; the bottle leaves
## at ~35 % of the motion (THROW_RELEASE seconds after the call).
const THROW_RELEASE := 0.22
func throw() -> void:
	_throw = 1.0


## Quick empty pat at the pockets: the action failed.
func fumble() -> void:
	_fumble = 1.0


func set_flashlight_visual(on: bool, level: float) -> void:
	flashlight.visible = on and level > 0.0
	flashlight.light_energy = 2.4 * level
	lens_mat.emission_energy_multiplier = 3.0 * level if on else 0.0


## Called every frame by the player.
## step_phase: radians of gait cycle; speed01: 0 idle..1 sprint; look_delta: mouse delta this frame;
## fear: 0..1 tremor amount.
func animate(delta: float, step_phase: float, speed01: float, crouch01: float, look_delta: Vector2, wall_close: float, fear := 0.0) -> void:
	_t += delta
	_fear = lerpf(_fear, fear, 1.0 - exp(-3.0 * delta))
	# Inertial sway: hands lag behind camera rotation, spring back.
	_sway_vel += (-look_delta * 0.0009 - _sway * 60.0) * delta
	_sway_vel *= exp(-12.0 * delta)
	_sway += _sway_vel
	_sway = _sway.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))
	var breathe := sin(_t * 1.6) * 0.0035 * (1.0 + _fear)
	var pump := sin(step_phase) * 0.012 * speed01 * (1.0 + speed01 * 2.2)
	var lift := absf(cos(step_phase)) * 0.008 * speed01 * (1.0 + speed01)
	var pull_back := wall_close * 0.16
	# Fear tremor: small high-frequency shake, stronger in the beam hand's wrist.
	var tremor := Vector3(sin(_t * 31.0) + sin(_t * 47.0) * 0.6, sin(_t * 37.0 + 1.3) + sin(_t * 53.0) * 0.5, 0.0) * 0.0018 * _fear
	_fumble = maxf(0.0, _fumble - delta * 2.2)
	var fum := sin(_fumble * PI * 3.0) * _fumble
	_swap = maxf(0.0, _swap - delta / 0.9)
	var sw := sin(_swap * PI)  # 0 → 1 → 0 over the swap
	_throw = maxf(0.0, _throw - delta / 0.65)
	var tp := 1.0 - _throw  # progress 0..1
	var wind := smoothstep(0.0, 0.3, tp) * (1.0 - smoothstep(0.3, 0.45, tp)) if _throw > 0.0 else 0.0
	var fling := smoothstep(0.3, 0.45, tp) * (1.0 - smoothstep(0.55, 1.0, tp)) if _throw > 0.0 else 0.0

	# Right hand: torch held forward; tipped up and in during a battery swap.
	var rp := _r_rest + Vector3(_sway.x - pump * 0.6, _sway.y + breathe - lift - crouch01 * 0.015, pull_back + pump * 0.4) + tremor
	rp += Vector3(-0.07, 0.03, 0.08) * sw
	_right.position = _right.position.lerp(rp, 1.0 - exp(-18.0 * delta))
	var r_off := Basis.from_euler(Vector3(_sway.y * 2.0 + pump * 2.0 + speed01 * 0.25 + sw * 0.9 + tremor.y * 4.0, _sway.x * 2.0 + tremor.x * 4.0, -pump * 3.0 - sw * 0.6))
	_right.basis = r_off * _r_basis

	# Left hand: idle low, reach forward on interact, raise page when reading.
	_reach = maxf(0.0, _reach - delta * 2.4)
	var reach_curve := sin(_reach * PI)
	var lp := _l_rest + Vector3(_sway.x + pump * 0.6, _sway.y + breathe * 1.2 - lift + reach_curve * 0.14, pull_back - pump * 0.5 - reach_curve * 0.16) + tremor * 0.6
	var lr := Vector3(0.25 + reach_curve * -0.35 + speed01 * 0.4, -0.25, 0.35 + pump * 3.0)
	var curl := 0.35 + reach_curve * -0.3
	var l_curls := [curl, curl + 0.1, curl + 0.2, curl + 0.3]
	var l_thumb := 0.3
	if _reading:
		lp = Vector3(-0.115, -0.165, -0.34) + Vector3(_sway.x, _sway.y + breathe, 0) + tremor * 0.5
		lr = Vector3(0.9, -0.15, 1.35)
		l_curls = [0.2, 0.25, 0.3, 0.35]
		l_thumb = -0.3
	elif _swap > 0.0:
		# Cup the torch's tail cap and twist.
		var tail := _right.transform * (_torch.transform * Vector3(0, 0, 0.09))
		lp = lp.lerp(tail + Vector3(-0.03, -0.035, 0.03), sw)
		lr = lr.lerp(Vector3(0.4, -0.6, 1.3 + sin(_t * 18.0) * 0.25), sw)
		var g := lerpf(curl, 1.0, sw)
		l_curls = [g, g, g + 0.05, g + 0.1]
		l_thumb = lerpf(0.3, 0.8, sw)
	elif _throw > 0.0:
		lp += Vector3(-0.05, 0.16, 0.22) * wind + Vector3(0.12, 0.18, -0.3) * fling
		lr += Vector3(-0.9, 0.2, 0.0) * wind + Vector3(-0.4, 0.3, -0.2) * fling
		var g := 1.15 * (1.0 - smoothstep(0.35, 0.5, tp))
		l_curls = [g, g, g, g]
		l_thumb = g
	elif _fumble > 0.0:
		lp += Vector3(0.03, -0.06 + fum * 0.03, 0.08) * minf(1.0, _fumble * 3.0)
		lr += Vector3(fum * 0.4, 0.0, fum * 0.3)
		var g := curl + fum * 0.4
		l_curls = [g, g + 0.05, g + 0.1, g + 0.15]
	_pose(_l_rig, l_curls, l_thumb)
	_left.position = _left.position.lerp(lp, 1.0 - exp(-14.0 * delta))
	_left.rotation = _left.rotation.lerp(lr, 1.0 - exp(-12.0 * delta))
	_aim_forearm(_r_forearm, _right.position, _r_elbow + Vector3(_sway.x, _sway.y - lift, 0) * 0.5)
	_aim_forearm(_l_forearm, _left.position, _l_elbow + Vector3(_sway.x, _sway.y - lift, 0) * 0.5)
	if _reading:
		paper.position = paper.position.lerp(Vector3(-0.02, -0.03 + breathe, -0.3) + Vector3(_sway.x, _sway.y, 0) * 0.7, 1.0 - exp(-14.0 * delta))
	_aim_beam(delta)


func _aim_forearm(fa: Node3D, wrist: Vector3, elbow: Vector3) -> void:
	fa.position = wrist
	var dir := (elbow - wrist).normalized()
	fa.basis = Basis.looking_at(-dir, Vector3.UP)  # local +Z toward the elbow


## The beam leaves the lens but aims where the camera looks (a point 10 m out),
## trailing camera turns slightly. Hand sway/pump only nudge its origin.
func _aim_beam(delta: float) -> void:
	var cam := get_parent() as Node3D
	if cam == null or not is_inside_tree():
		return
	var origin := _lens_anchor.global_position
	var target := cam.global_position - cam.global_basis.z * 10.0
	var want := Basis.looking_at((target - origin).normalized(), cam.global_basis.y).get_rotation_quaternion()
	if not _beam_init:
		_beam_q = want
		_beam_init = true
	_beam_q = _beam_q.slerp(want, 1.0 - exp(-BEAM_LAG * delta))
	flashlight.global_transform = Transform3D(Basis(_beam_q), origin)
