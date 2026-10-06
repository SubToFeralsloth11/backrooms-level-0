extends Node3D
## Set dressing pass run at the end of Level.generate(): wall/ceiling/floor
## damage, door frames, outlets and vents, scattered office junk (downloaded
## CC0 models), broken sparking fluorescent panels, believable almond-water
## placement and smashed-bottle decoys. Static detail is batched into
## MultiMeshes; models fade out with visibility ranges; sparking lights are
## capped at MAX_SPARKERS and only run near the camera.

const Lighting := preload("res://scripts/lighting.gd")
const MAX_SPARKERS := 4
const SPARK_RANGE := 18.0
const MODEL_FADE := 26.0
const DOOR_TOP := 2.3

## name -> [path, target height (0 = native scale), collide, keep only these
## node names (optional), tint for flat-coloured low-poly models (optional)]
const MODELS := {
	"office_chair": ["res://models/props/chairDesk.glb", 0.95, true, [], Color(0.16, 0.16, 0.17)],
	"school_chair": ["res://models/props/SchoolChair_01/SchoolChair_01.gltf", 0.0, true],
	"plastic_chair": ["res://models/props/plastic_monobloc_chair_01/plastic_monobloc_chair_01.gltf", 0.0, true],
	"box": ["res://models/props/cardboard_box_01/cardboard_box_01.gltf", 0.0, true],
	"box_open": ["res://models/props/cardboardBoxOpen.glb", 0.32, true, [], Color(0.62, 0.46, 0.28)],
	"wet_sign": ["res://models/props/WetFloorSign_01/WetFloorSign_01.gltf", 0.0, false],
	"trash_can": ["res://models/props/metal_trash_can/metal_trash_can.gltf", 0.0, true, ["metal_trash_can_rust", "metal_trash_can_rust_handle_left", "metal_trash_can_rust_handle_right"]],
	"crate": ["res://models/props/plastic_crate_01/plastic_crate_01.gltf", 0.0, true],
	"notepads": ["res://models/props/office_notepads/office_notepads.gltf", 0.0, false, ["office_notepads_a4_stack"]],
	"paper": ["res://models/props/office_notepads/office_notepads.gltf", 0.0, false, ["office_notepads_a4_a"]],
	"pad": ["res://models/props/office_notepads/office_notepads.gltf", 0.0, false, ["office_notepads_yellow_pad"]],
	"binder": ["res://models/props/binder_notebook/binder_notebook.gltf", 0.0, false, ["binder_notebook_closed"]],
	"toolbox": ["res://models/props/metal_toolbox/metal_toolbox.gltf", 0.0, false],
	"trashbag": ["res://models/props/trashbag/trashbag.gltf", 0.0, false],
	"monitor": ["res://models/props/computerScreen.glb", 0.38, false, [], Color(0.78, 0.75, 0.66)],
	"keyboard": ["res://models/props/computerKeyboard.glb", 0.03, false, [], Color(0.75, 0.72, 0.64)],
}

var level: Level
var rng := RandomNumberGenerator.new()
var _used: Array = []  # world positions kept clear of clutter
var _mm := {}  # key -> {mesh, xforms}
var _mats := {}
var _model_cache := {}
var _sparkers: Array[Dictionary] = []
var _danglers: Array[Dictionary] = []
var _t := 0.0


static func decorate(lvl: Level) -> void:
	var p: Node3D = (load("res://scripts/props.gd") as GDScript).new()
	p.name = "Props"
	lvl.add_child(p)
	p.call("_build", lvl)


func _build(lvl: Level) -> void:
	level = lvl
	rng.seed = lvl.rng.seed ^ 0x5eed
	_collect_reserved()
	_make_materials()
	Lighting.apply(level)
	_door_frames()
	_broken_panels()
	_ceiling_damage()
	_wall_damage()
	_wall_fixtures()
	_floor_detail()
	_clutter()
	_place_bottles()
	_smashed_bottles()
	_flush_multimeshes()
	var nd := 0
	for ch in get_children():
		if ch is Decal: nd += 1


# ---------------------------------------------------------------- helpers

func _collect_reserved() -> void:
	_used.append(level.cell_center(level.spawn_cell))
	for b in level.blood_spots:
		_used.append(b.pos)
	for p in level.drip_spots:
		_used.append(p)
	for n in level.get_children():
		if n is Interactable:
			_used.append((n as Node3D).position)
	for n in [level.breaker_panel, level.keypad, level.exit_door]:
		if n:
			_used.append((n as Node3D).position)


func _clear(p: Vector3, r: float) -> bool:
	for u in _used:
		if Vector2(p.x - u.x, p.z - u.z).length() < r:
			return false
	return true


func _mat(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _make_materials() -> void:
	_mats.drywall = _mat(Color(0.86, 0.85, 0.8), 0.95)
	_mats.drywall_core = _mat(Color(0.93, 0.92, 0.88), 1.0)
	_mats.stud = _mat(Color(0.62, 0.47, 0.29), 0.9)
	_mats.cavity = _mat(Color(0.03, 0.025, 0.02), 1.0)
	_mats.frame = _mat(Color(0.72, 0.66, 0.5), 0.6)
	_mats.plate = _mat(Color(0.86, 0.83, 0.74), 0.5)
	_mats.slot = _mat(Color(0.05, 0.05, 0.05), 0.9)
	_mats.vent = _mat(Color(0.7, 0.69, 0.64), 0.45, 0.6)
	_mats.cable = _mat(Color(0.06, 0.06, 0.06), 0.6)
	_mats.cable_red = _mat(Color(0.45, 0.05, 0.04), 0.6)
	_mats.copper = _mat(Color(0.85, 0.5, 0.3), 0.3, 1.0)
	_mats.bucket = _mat(Color(0.85, 0.65, 0.05), 0.45)
	_mats.mop = _mat(Color(0.75, 0.72, 0.62), 1.0)
	_mats.handle = _mat(Color(0.25, 0.3, 0.4), 0.4, 0.5)
	_mats.paper = _mat(Color(0.86, 0.83, 0.72), 0.95)
	_mats.paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := _mat(Color(0.82, 0.9, 0.84, 0.4), 0.04)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.glass = glass
	_mats.label = _mat(Color(0.85, 0.82, 0.7), 0.7)
	_mats.label.cull_mode = BaseMaterial3D.CULL_DISABLED


func _box(size: Vector3, mat: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	return b


## Queue a static instance into a shared MultiMesh keyed by `key`.
func _add(key: String, mesh: Mesh, xf: Transform3D) -> void:
	if not _mm.has(key):
		_mm[key] = {"mesh": mesh, "xforms": []}
	_mm[key].xforms.append(xf)


func _flush_multimeshes() -> void:
	for key in _mm:
		var e: Dictionary = _mm[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e.mesh
		mm.instance_count = e.xforms.size()
		for i in e.xforms.size():
			mm.set_instance_transform(i, e.xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + key
		mmi.multimesh = mm
		if key == "flaps":
			mmi.layers = 2
		if key in ["shards", "outlets", "debris", "paper", "chips"]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_mm.clear()


func _decal(tex: String, pos: Vector3, size: Vector3, basis: Basis, modulate := Color.WHITE, wet := false) -> Decal:
	var d := Decal.new()
	d.texture_albedo = load("res://textures/props/%s.png" % tex)
	if wet:
		d.texture_orm = _wet_orm()
	d.size = size
	d.modulate = modulate
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.normal_fade = 0.5  # no smearing onto perpendicular ceilings/floors
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 22.0
	d.distance_fade_length = 6.0
	d.basis = basis
	add_child(d)
	d.position = pos
	return d


func _wet_orm() -> Texture2D:
	if not _mats.has("wet_orm"):
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(1.0, 0.18, 0.0))  # AO 1, roughness low, non-metal
		_mats.wet_orm = ImageTexture.create_from_image(img)
	return _mats.wet_orm


func _ceiling_basis(yaw: float) -> Basis:
	# decals project along local -Y; flip to project up into the ceiling
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI)


func _side(dir: Vector3) -> Vector3:
	return Vector3(-dir.z, 0, dir.x)


func _wall_spot(zone := -1, sep := 2.0) -> Dictionary:
	var s := level.wall_spot(zone, _used, sep)
	return s


## Open cell with walls on two perpendicular sides: {cell, a, b} (dirs into walls).
func _corner(zone := -1, sep := 2.0) -> Dictionary:
	for i in 600:
		var c := level.random_open_cell(zone)
		var p := level.cell_center(c)
		if not _clear(p, sep):
			continue
		var dx := 1 if level.is_wall(c + Vector2i(1, 0)) else (-1 if level.is_wall(c + Vector2i(-1, 0)) else 0)
		var dz := 1 if level.is_wall(c + Vector2i(0, 1)) else (-1 if level.is_wall(c + Vector2i(0, -1)) else 0)
		if dx != 0 and dz != 0 and level.is_open(c - Vector2i(dx, 0)) and level.is_open(c - Vector2i(0, dz)):
			return {"cell": c, "a": Vector3(dx, 0, 0), "b": Vector3(0, 0, dz)}
	return {}


func _zone_pick() -> int:
	var r := rng.randf()
	return Level.Zone.MAIN if r < 0.72 else (Level.Zone.DARK if r < 0.92 else Level.Zone.EXIT)


# ---------------------------------------------------------------- door frames

func _door_frames() -> void:
	var skip: Array[Vector2i] = [level.wing_door, level.breaker_door, level.exit_hall_door]
	var trim := _box(Vector3.ONE, _mats.frame)
	var fill := _box(Vector3.ONE, level._mat.wall)
	for axis in [Vector2i(1, 0), Vector2i(0, 1)]:
		var side: Vector2i = axis
		var d := Vector2i(side.y, side.x)
		for y in range(2, Level.H - 2):
			for x in range(2, Level.W - 2):
				var c := Vector2i(x, y)
				if not level.is_open(c) or not level.is_wall(c - side) or not level.is_wall(c - side * 2):
					continue
				if not (level.is_open(c - side + d) and level.is_open(c - side - d)):
					continue
				var k := 0
				while k < 5 and level.is_open(c + side * k) and level.is_open(c + side * k + d) and level.is_open(c + side * k - d):
					k += 1
				if k < 1 or k > 4 or not level.is_wall(c + side * k) or not level.is_wall(c + side * (k + 1)):
					continue
				var near_sign := false
				for s in skip:
					if (s - c).length() < 6:
						near_sign = true
				if near_sign or (level.exit_door and level.cell_center(c).distance_to(level.exit_door.position) < 4.0):
					continue
				var sv := Vector3(side.x, 0, side.y)
				var dv := Vector3(d.x, 0, d.y)
				var a := level.cell_center(c) - sv * Level.CELL * 0.5
				var b := level.cell_center(c + side * (k - 1)) + sv * Level.CELL * 0.5
				var mid := (a + b) * 0.5
				var width := k * Level.CELL
				var depth := Level.CELL + 0.05
				var rot := Basis(Vector3.UP, 0.0 if side.x != 0 else PI * 0.5)
				# jambs: (along side, height, depth)
				for e in [[a, 1.0], [b, -1.0]]:
					var p: Vector3 = e[0] + sv * (0.035 * float(e[1])) + Vector3(0, DOOR_TOP * 0.5, 0)
					_add("frame", trim, Transform3D(rot.scaled_local(Vector3(0.07, DOOR_TOP, depth)), p))
				_add("frame", trim, Transform3D(rot.scaled_local(Vector3(width, 0.07, depth)), mid + Vector3(0, DOOR_TOP + 0.035, 0)))
				var fh := Level.WALL_H - DOOR_TOP - 0.07
				_add("door_fill", fill, Transform3D(rot.scaled_local(Vector3(width, fh, Level.CELL)), mid + Vector3(0, DOOR_TOP + 0.07 + fh * 0.5, 0)))
				# scuffed kick zone on the jambs' neighbouring wall
				if rng.randf() < 0.4:
					_decal("scuff_1", a - sv * 0.3 + dv * (Level.CELL * 0.5) + Vector3(0, 0.6, 0), Vector3(0.7, 0.3, 0.9), level.wall_basis(-dv), Color(1, 1, 1, 0.6))


# ---------------------------------------------------------------- broken panels

func _broken_panels() -> void:
	var spawn := level.cell_center(level.spawn_cell)
	var cands: Array[Dictionary] = []
	for pd in level.panels:
		if pd.zone == Level.Zone.DARK or pd.kind == "flicker":
			continue
		var p: Vector3 = pd.pos
		if p.distance_to(spawn) < 7.0:
			continue
		cands.append(pd)
	cands.shuffle()
	var sites: Array[Vector3] = []
	var dangling := 0
	for pd in cands:
		if _sparkers.size() >= MAX_SPARKERS and dangling >= 5:
			break
		var p: Vector3 = pd.pos
		var ok := true
		for s in sites:
			if s.distance_to(p) < 14.0:
				ok = false
		if not ok:
			continue
		sites.append(p)
		_kill_panel(pd)
		var spark := _sparkers.size() < MAX_SPARKERS
		_hanging_panel(pd, spark)
		if spark:
			_add_sparker(pd)
		else:
			dangling += 1
	# a couple more dead panels in the dark wing hang loose too
	var wing := 0
	for pd in level.panels:
		if wing >= 3:
			break
		if pd.zone == Level.Zone.DARK and rng.randf() < 0.12:
			_kill_panel(pd)
			_hanging_panel(pd, false)
			wing += 1


func _kill_panel(pd: Dictionary) -> void:
	pd.kind = "dead"
	pd.level = 0.0
	var p: Vector3 = pd.pos
	for g in level._panel_mm:
		var mm: MultiMesh = level._panel_mm[g].multimesh
		for i in mm.instance_count:
			if mm.get_instance_transform(i).origin.is_equal_approx(p):
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), p + Vector3(0, 50, 0)))
				return
	if pd.has("node"):
		(pd.node as Node3D).visible = false


func _hanging_panel(pd: Dictionary, sparking: bool) -> void:
	var p: Vector3 = pd.pos
	var ceil_y := Level.WALL_H - 0.005
	# dark recess where the fixture was
	var hole := MeshInstance3D.new()
	var hm := PlaneMesh.new()
	hm.size = Vector2(0.62, 1.22)
	hm.flip_faces = true
	hm.material = _mats.cavity
	hole.mesh = hm
	hole.position = Vector3(p.x, ceil_y, p.z)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hole)
	if sparking:
		_decal("scorch", Vector3(p.x, Level.WALL_H, p.z), Vector3(1.6, 0.3, 2.2), _ceiling_basis(rng.randf() * TAU), Color(1, 1, 1, 0.85))
	# fixture hangs from one short edge, swinging gently on its wires
	var pivot := Node3D.new()
	var end := 1.0 if rng.randf() < 0.5 else -1.0
	pivot.position = Vector3(p.x, ceil_y - 0.01, p.z + 0.6 * end)
	add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = level._panel_mesh(false)
	mi.position = Vector3(0, 0, -0.6 * end)
	pivot.add_child(mi)
	var ang := rng.randf_range(0.9, 1.35) * end
	pivot.rotation = Vector3(-ang, rng.randf_range(-0.25, 0.25), rng.randf_range(-0.12, 0.12))
	# wires from the recess down to the loose end
	var tip := Vector3(p.x + rng.randf_range(-0.15, 0.15), ceil_y - rng.randf_range(0.45, 0.8), p.z - 0.2 * end)
	for w in 2:
		var off := Vector3(0.05 * (w * 2 - 1), 0, 0)
		_cable(Vector3(p.x, ceil_y, p.z) + off, tip + off * 0.5, 0.05, _mats.cable if w == 0 else _mats.cable_red, 0.006)
	_danglers.append({"pivot": pivot, "base": pivot.rotation, "phase": rng.randf() * TAU, "amp": rng.randf_range(0.02, 0.05)})
	pd["spark_tip"] = tip


func _add_sparker(pd: Dictionary) -> void:
	var tip: Vector3 = pd.spark_tip
	var parts := GPUParticles3D.new()
	parts.amount = 48
	parts.lifetime = 1.1
	parts.one_shot = true
	parts.explosiveness = 0.85
	parts.randomness = 0.5
	parts.emitting = false
	parts.local_coords = false
	parts.collision_base_size = 0.01
	parts.visibility_aabb = AABB(Vector3(-2.5, -3.0, -2.5), Vector3(5, 3.5, 5))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.3, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.35
	pm.collision_friction = 0.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.02, 0.0))
	ramp.add_point(0.35, Color(1.0, 0.7, 0.2, 1.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	parts.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(4.0, 3.0, 1.6)  # HDR so sparks bloom
	q.material = sm
	parts.draw_pass_1 = q
	parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(parts)
	parts.position = tip
	var floor_col := GPUParticlesCollisionBox3D.new()
	floor_col.size = Vector3(6, 0.2, 6)
	add_child(floor_col)
	floor_col.position = Vector3(tip.x, -0.1, tip.z)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.45)
	light.omni_range = 5.0
	light.omni_attenuation = 1.6
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	light.position = tip + Vector3(0, -0.1, 0)
	_sparkers.append({"pos": tip, "parts": parts, "light": light, "zone": pd.zone, "timer": rng.randf_range(1.0, 5.0), "flash": 0.0})


func _process(delta: float) -> void:
	_t += delta
	for d in _danglers:
		var piv: Node3D = d.pivot
		piv.rotation = d.base + Vector3(sin(_t * 0.9 + d.phase) * d.amp, 0, sin(_t * 0.6 + d.phase * 1.7) * d.amp * 0.6)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var powered := not Game.blackout
	for s in _sparkers:
		var l: OmniLight3D = s.light
		var live: bool = powered and (s.zone != Level.Zone.EXIT or Game.power_on)
		if s.flash > 0.0:
			s.flash -= delta
			l.light_energy = rng.randf_range(0.6, 2.4) * clampf(s.flash * 3.0, 0.0, 1.0)
			if s.flash <= 0.0:
				l.visible = false
		if not live or cp.distance_to(s.pos) > SPARK_RANGE:
			continue
		s.timer -= delta
		if s.timer <= 0.0:
			s.timer = rng.randf_range(1.8, 8.0) if rng.randf() < 0.75 else rng.randf_range(0.15, 0.5)
			var parts: GPUParticles3D = s.parts
			parts.amount_ratio = rng.randf_range(0.35, 1.0)
			parts.restart()
			s.flash = rng.randf_range(0.12, 0.35)
			l.visible = true
			Audio.play_3d("light_pop" if rng.randf() < 0.6 else "light_flicker", s.pos, -6.0 + rng.randf() * 4.0, 22.0, 0.15)


# ---------------------------------------------------------------- ceiling

func _ceiling_damage() -> void:
	var tile := 0.6
	var ceiling_mat: Material = level._mat.ceiling
	var chunk := _box(Vector3.ONE, ceiling_mat)
	var placed := 0
	for i in 400:
		if placed >= 30:
			break
		var c := level.random_open_cell(_zone_pick())
		var p := level.cell_center(c)
		# snap to the 0.6 m tile grid, away from light fixtures
		p.x = (floor(p.x / tile) + 0.5) * tile
		p.z = (floor(p.z / tile) + 0.5) * tile
		if level.is_wall(level.world_to_cell(p + Vector3(0.35, 0, 0.35))) or level.is_wall(level.world_to_cell(p - Vector3(0.35, 0, 0.35))):
			continue
		var near_panel := false
		for pd in level.panels:
			var pp: Vector3 = pd.pos
			if absf(pp.x - p.x) < 0.75 and absf(pp.z - p.z) < 1.05:
				near_panel = true
				break
		if near_panel or not _clear(p, 1.2):
			continue
		placed += 1
		var kind := placed % 3
		if kind == 0:
			_missing_tile(p, tile, chunk)
		elif kind == 1:
			_sagging_tile(p, tile, ceiling_mat)
		else:
			_decal("ceiling_stain", Vector3(p.x, Level.WALL_H, p.z), Vector3(rng.randf_range(0.7, 1.6), 0.3, rng.randf_range(0.7, 1.6)), _ceiling_basis(rng.randf() * TAU), Color(1, 1, 1, rng.randf_range(0.55, 0.95)))


func _missing_tile(p: Vector3, tile: float, chunk: Mesh) -> void:
	# dark void above the grid with a lip of torn tile
	var box := _box(Vector3(tile - 0.02, 0.5, tile - 0.02), _mats.cavity)
	box.flip_faces = true
	_add("tile_void", box, Transform3D(Basis(), Vector3(p.x, Level.WALL_H + 0.24, p.z)))
	_decal("ceiling_stain", Vector3(p.x, Level.WALL_H, p.z), Vector3(1.3, 0.3, 1.3), _ceiling_basis(rng.randf() * TAU), Color(1, 1, 1, 0.7))
	if rng.randf() < 0.6:
		var top := Vector3(p.x + rng.randf_range(-0.2, 0.2), Level.WALL_H + 0.1, p.z + rng.randf_range(-0.2, 0.2))
		_cable(top, top + Vector3(rng.randf_range(-0.3, 0.3), -rng.randf_range(0.6, 1.3), rng.randf_range(-0.3, 0.3)), 0.12, _mats.cable, 0.008)
	# fallen tile broken on the carpet below
	var fall := p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	for k in rng.randi_range(2, 4):
		var sz := Vector3(rng.randf_range(0.12, 0.34), 0.016, rng.randf_range(0.1, 0.3))
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
		var at := fall + Vector3(rng.randf_range(-0.35, 0.35), 0.008 + k * 0.004, rng.randf_range(-0.35, 0.35))
		if level.is_open(level.world_to_cell(at)):
			_add("tile_chunks", chunk, Transform3D(b.scaled_local(sz), at))
	_dust(fall, 14, 0.5)


func _sagging_tile(p: Vector3, tile: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 6
	var sag := rng.randf_range(0.05, 0.12)
	var tilt := Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
	var pts := []
	for j in n + 1:
		for i in n + 1:
			var u := i / float(n) - 0.5
			var v := j / float(n) - 0.5
			var y := -sag * cos(u * PI) * cos(v * PI) + tilt.x * u + tilt.y * v
			pts.append(Vector3(u * tile, minf(y, 0.0), v * tile))
	for j in n:
		for i in n:
			var a: Vector3 = pts[j * (n + 1) + i]
			var b: Vector3 = pts[j * (n + 1) + i + 1]
			var c: Vector3 = pts[(j + 1) * (n + 1) + i + 1]
			var d: Vector3 = pts[(j + 1) * (n + 1) + i]
			for v in [a, c, b, a, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = Vector3(p.x, Level.WALL_H - 0.004, p.z)
	add_child(mi)
	_decal("ceiling_stain", Vector3(p.x, Level.WALL_H - sag * 0.5, p.z), Vector3(0.75, 0.5, 0.75), _ceiling_basis(rng.randf() * TAU), Color(1, 1, 1, 0.95))
	_decal("wet_carpet", p, Vector3(1.0, 0.3, 1.0), Basis(Vector3.UP, rng.randf() * TAU), Color(1, 1, 1, 0.8), true)


## Thin tube following a sagging curve from a to b.
func _cable(a: Vector3, b: Vector3, slack: float, mat: Material, radius: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8
	var ring := 5
	var pts: Array[Vector3] = []
	for i in seg + 1:
		var t := i / float(seg)
		pts.append(a.lerp(b, t) + Vector3(0, -slack * sin(t * PI), 0) - a)
	for i in seg:
		var dir := (pts[i + 1] - pts[i]).normalized()
		var x := dir.cross(Vector3.FORWARD if absf(dir.y) > 0.9 else Vector3.UP).normalized()
		var y := dir.cross(x)
		for k in ring:
			var a0 := TAU * k / ring
			var a1 := TAU * (k + 1) / ring
			var o0 := (x * cos(a0) + y * sin(a0)) * radius
			var o1 := (x * cos(a1) + y * sin(a1)) * radius
			for v in [pts[i] + o0, pts[i + 1] + o0, pts[i + 1] + o1, pts[i] + o0, pts[i + 1] + o1, pts[i] + o1]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = a
	add_child(mi)
	# bare copper at the free end
	_add("copper", _box(Vector3(0.006, 0.03, 0.006), _mats.copper), Transform3D(Basis(), b))


func _dust(center: Vector3, count: int, radius: float) -> void:
	var chip := _box(Vector3(0.025, 0.012, 0.02), _mats.drywall_core)
	for i in count:
		var at := center + Vector3(rng.randf_range(-radius, radius), 0.006, rng.randf_range(-radius, radius))
		if level.is_open(level.world_to_cell(at)):
			var s := rng.randf_range(0.5, 2.2)
			_add("chips", chip, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s)), at))


# ---------------------------------------------------------------- walls

func _wall_damage() -> void:
	for i in 34:
		var s := _wall_spot(_zone_pick(), 1.5)
		if s.is_empty():
			continue
		var sz := rng.randf_range(0.5, 1.4)
		_decal("crack_%d" % (1 + i % 3), level.wall_point(s, rng.randf_range(0.3 + sz * 0.3, Level.WALL_H - sz * 0.5)), Vector3(sz, 0.3, sz), level.wall_basis(s.dir, rng.randf() * TAU), Color(1, 1, 1, rng.randf_range(0.6, 1.0)))
	for i in 24:
		var s := _wall_spot(-1, 1.5)
		if s.is_empty():
			continue
		var sz := rng.randf_range(0.22, 0.45)
		_decal("dent_1", level.wall_point(s, rng.randf_range(0.5, 1.3)), Vector3(sz, 0.25, sz), level.wall_basis(s.dir, rng.randf() * TAU), Color(1, 1, 1, 0.85))
	for i in 28:
		var s := _wall_spot(-1, 1.0)
		if s.is_empty():
			continue
		_decal("scuff_1", level.wall_point(s, rng.randf_range(0.12, 0.4)), Vector3(rng.randf_range(0.8, 1.6), 0.25, 0.5), level.wall_basis(s.dir), Color(1, 1, 1, rng.randf_range(0.4, 0.8)))
	for i in 8:
		var s := _wall_spot(Level.Zone.MAIN if i < 5 else -1, 6.0)
		if not s.is_empty():
			_wall_hole(s)


## Punched-through drywall: torn edge, dark cavity, studs, debris below.
func _wall_hole(s: Dictionary) -> void:
	var dir: Vector3 = s.dir
	var side := _side(dir)
	var h := rng.randf_range(0.45, 1.3)
	var w := rng.randf_range(0.45, 0.75)
	var hh := rng.randf_range(0.4, 0.75)
	var face := level.wall_point(s, h)
	var basis := Basis(side, Vector3.UP, -dir)  # local +Z points out of the wall
	var root := Node3D.new()
	add_child(root)
	root.transform = Transform3D(basis, face)
	_decal("hole_1", face, Vector3(w * 1.35, 0.25, hh * 1.35), level.wall_basis(dir, rng.randf_range(-0.3, 0.3)))
	# cavity backing (set just proud of the wall face so it overrides it)
	var back := MeshInstance3D.new()
	back.mesh = _box(Vector3(w * 0.6, hh * 0.6, 0.004), _mats.cavity)
	back.layers = 2  # outside the hole decal's cull mask
	back.position = Vector3(0, 0, 0.004)
	root.add_child(back)
	# studs and a fibreglass-ish insulation strip
	var stud_x := rng.randf_range(-w * 0.25, w * 0.25)
	var stud := MeshInstance3D.new()
	stud.mesh = _box(Vector3(0.045, hh * 0.62, 0.012), _mats.stud)
	stud.layers = 2
	stud.position = Vector3(stud_x, 0, 0.01)
	root.add_child(stud)
	# torn drywall flaps around the rim, bent outward
	var flap := _box(Vector3.ONE, _mats.drywall)
	for k in rng.randi_range(5, 8):
		var ang := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
		var rim := Vector3(cos(ang) * w * 0.33, sin(ang) * hh * 0.33, 0.0)
		var fb := Basis(Vector3(0, 0, 1), ang + PI * 0.5) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.2))
		var gx := root.transform * Transform3D(fb.scaled_local(Vector3(rng.randf_range(0.06, 0.16), 0.012, rng.randf_range(0.03, 0.07))), rim + Vector3(0, 0, 0.012))
		_add("flaps", flap, gx)
	# debris on the carpet beneath
	var floor_p := level.cell_center(s.cell) + dir * (Level.CELL * 0.5 - 0.2)
	var chunk := _box(Vector3.ONE, _mats.drywall_core)
	for k in rng.randi_range(4, 7):
		var at := floor_p + side * rng.randf_range(-w * 0.6, w * 0.6) - dir * rng.randf_range(0.0, 0.35)
		var sz := Vector3(rng.randf_range(0.05, 0.18), 0.012, rng.randf_range(0.05, 0.15))
		_add("debris", chunk, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)).scaled_local(sz), at + Vector3(0, 0.01, 0)))
	_dust(floor_p - dir * 0.15, 18, 0.35)
	_used.append(level.cell_center(s.cell))


func _wall_fixtures() -> void:
	# outlets: beige plate with two dark slots, one surface each
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(_box(Vector3(0.07, 0.115, 0.008), null), 0, Transform3D(Basis(), Vector3(0, 0, 0.004)))
	var outlet := st.commit()
	outlet.surface_set_material(0, _mats.plate)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in [-0.025, 0.025]:
		st2.append_from(_box(Vector3(0.026, 0.024, 0.004), null), 0, Transform3D(Basis(), Vector3(0, y, 0.009)))
	st2.commit(outlet)
	outlet.surface_set_material(1, _mats.slot)
	for i in 46:
		var s := _wall_spot(-1, 1.0)
		if s.is_empty():
			continue
		var dir: Vector3 = s.dir
		var b := Basis(_side(dir), Vector3.UP, -dir)
		var p := level.wall_point(s, 0.3 if rng.randf() < 0.85 else 1.1) - dir * 0.001
		var tilt := Basis(Vector3(0, 0, 1), rng.randf_range(-0.05, 0.05)) if rng.randf() < 0.2 else Basis()
		_add("outlets", outlet, Transform3D(b * tilt, p))
		if rng.randf() < 0.25:
			_decal("scorch", p + Vector3(0, 0.06, 0), Vector3(0.18, 0.2, 0.25), level.wall_basis(dir), Color(1, 1, 1, 0.5))
	# return-air vents high on the walls, slatted
	var vst := SurfaceTool.new()
	vst.begin(Mesh.PRIMITIVE_TRIANGLES)
	vst.append_from(_box(Vector3(0.46, 0.022, 0.02), null), 0, Transform3D(Basis(), Vector3(0, 0.12, 0.01)))
	vst.append_from(_box(Vector3(0.46, 0.022, 0.02), null), 0, Transform3D(Basis(), Vector3(0, -0.12, 0.01)))
	vst.append_from(_box(Vector3(0.022, 0.26, 0.02), null), 0, Transform3D(Basis(), Vector3(0.22, 0, 0.01)))
	vst.append_from(_box(Vector3(0.022, 0.26, 0.02), null), 0, Transform3D(Basis(), Vector3(-0.22, 0, 0.01)))
	for k in 6:
		vst.append_from(_box(Vector3(0.42, 0.03, 0.004), null), 0, Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(0, -0.09 + k * 0.036, 0.01)))
	var vent := vst.commit()
	vent.surface_set_material(0, _mats.vent)
	var vback := StandardMaterial3D.new()
	vback.albedo_color = Color(0.02, 0.02, 0.02)
	var vbst := SurfaceTool.new()
	vbst.begin(Mesh.PRIMITIVE_TRIANGLES)
	vbst.append_from(_box(Vector3(0.44, 0.24, 0.003), null), 0, Transform3D(Basis(), Vector3(0, 0, 0.002)))
	vbst.commit(vent)
	vent.surface_set_material(1, vback)
	for i in 18:
		var s := _wall_spot(-1, 3.0)
		if s.is_empty():
			continue
		var dir: Vector3 = s.dir
		var b := Basis(_side(dir), Vector3.UP, -dir)
		var p := level.wall_point(s, Level.WALL_H - 0.3) - dir * 0.001
		_add("vents", vent, Transform3D(b, p))
		# grime streaking down from the grille
		_decal("scorch", p + Vector3(0, -0.28, 0), Vector3(0.5, 0.2, 0.5), level.wall_basis(dir), Color(1, 1, 1, 0.35))


# ---------------------------------------------------------------- floor

func _floor_detail() -> void:
	for i in 16:
		var c := level.random_open_cell(_zone_pick())
		var p := level.cell_center(c)
		var s := rng.randf_range(0.9, 2.2)
		_decal("wet_carpet", p, Vector3(s, 0.3, s * rng.randf_range(0.6, 1.0)), Basis(Vector3.UP, rng.randf() * TAU), Color(1, 1, 1, rng.randf_range(0.6, 0.9)), true)
	# loose paper sheets drifting along walls
	var sheet := QuadMesh.new()
	sheet.size = Vector2(0.21, 0.297)
	sheet.orientation = PlaneMesh.FACE_Y
	sheet.material = _mats.paper
	for i in 22:
		var s := _wall_spot(-1, 2.0)
		if s.is_empty():
			continue
		var base := level.cell_center(s.cell) + (s.dir as Vector3) * 0.1
		for k in rng.randi_range(1, 4):
			var at := base + Vector3(rng.randf_range(-0.35, 0.35), 0.004 + k * 0.002, rng.randf_range(-0.35, 0.35))
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
			_add("paper", sheet, Transform3D(b, at))


# ---------------------------------------------------------------- models

func _model(name: String) -> Node3D:
	var info: Array = MODELS[name]
	if not _model_cache.has(name):
		var scene: PackedScene = load(info[0])
		var probe: Node3D = scene.instantiate()
		_strip(probe, info)
		var aabb := _aabb(probe, Transform3D())
		probe.free()
		var target: float = info[1]
		var sc := target / aabb.size.y if target > 0.0 and aabb.size.y > 0.0 else 1.0
		_model_cache[name] = {"scene": scene, "aabb": aabb, "scale": sc}
	var e: Dictionary = _model_cache[name]
	var root := Node3D.new()
	var inst: Node3D = (e.scene as PackedScene).instantiate()
	_strip(inst, info)
	if info.size() > 4:
		_tint(inst, info[4])
	inst.scale = Vector3.ONE * e.scale
	var aabb: AABB = e.aabb
	# sit the model's footprint centre on the root origin
	inst.position = -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) * e.scale
	root.add_child(inst)
	_fade(inst)
	if info[2]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = aabb.size * e.scale * Vector3(0.85, 1.0, 0.85)
		cs.shape = bs
		cs.position = Vector3(0, bs.size.y * 0.5, 0)
		body.add_child(cs)
		root.add_child(body)
	root.set_meta("size", aabb.size * e.scale)
	add_child(root)
	return root


## Keep only the named meshes of a multi-object asset sheet.
func _strip(root: Node, info: Array) -> void:
	if info.size() < 4 or (info[3] as Array).is_empty():
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not (n.name in info[3]):
			n.get_parent().remove_child(n)
			n.free()


## Grey-scale the flat palette and multiply by `tint` so cartoon colours read as worn office kit.
func _tint(root: Node, tint: Color) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			var m := StandardMaterial3D.new()
			var l := 0.5 + 0.5 * (src.albedo_color.get_luminance() if src else 0.5)
			m.albedo_color = Color(tint.r * l, tint.g * l, tint.b * l)
			m.roughness = 0.75
			mi.set_surface_override_material(i, m)


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D())
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb(c, t)
		if ca.size == Vector3.ZERO:
			continue
		out = ca if first else out.merge(ca)
		first = false
	return out


func _fade(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_end = MODEL_FADE
		g.visibility_range_end_margin = 2.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for c in n.get_children():
		_fade(c)


## Place a model against the wall of spot s; `along` slides it along the wall.
func _against(name: String, cell: Vector2i, dir: Vector3, along := 0.0, yaw_jitter := 0.25, face_out := true) -> Node3D:
	var m := _model(name)
	var size: Vector3 = m.get_meta("size")
	var yaw := atan2(dir.x, dir.z) + (PI if face_out else 0.0) + rng.randf_range(-yaw_jitter, yaw_jitter)
	m.rotation.y = yaw
	var depth := maxf(size.x, size.z) * 0.5
	var p := level.cell_center(cell) + dir * (Level.CELL * 0.5 - depth - 0.03) + _side(dir) * along
	m.position = Vector3(p.x, 0, p.z)
	return m


func _clutter() -> void:
	var spawn := level.cell_center(level.spawn_cell)
	_used.append(spawn)
	var recipes := ["boxes", "boxes", "chair", "chair", "office", "trash", "mop", "papers", "crates", "boxes", "chair", "trash"]
	var placed := 0
	for i in 70:
		if placed >= 46:
			break
		var z := _zone_pick()
		var recipe: String = recipes[rng.randi() % recipes.size()]
		if z == Level.Zone.DARK and rng.randf() < 0.5:
			recipe = ["crates", "crates", "toolbox", "boxes", "mop"][rng.randi() % 5]
		var corner := rng.randf() < 0.45
		var s: Dictionary
		if corner:
			var cn := _corner(z, 3.5)
			if cn.is_empty():
				continue
			s = {"cell": cn.cell, "dir": cn.a, "dir2": cn.b}
		else:
			s = _wall_spot(z, 3.5)
			if s.is_empty():
				continue
		var p := level.cell_center(s.cell)
		if p.distance_to(spawn) < 2.5:
			continue
		_recipe(recipe, s)
		_used.append(p)
		placed += 1


func _recipe(recipe: String, s: Dictionary) -> void:
	var c: Vector2i = s.cell
	var dir: Vector3 = s.dir
	var dir2: Vector3 = s.get("dir2", Vector3.ZERO)
	var corner_slide := 0.0
	if dir2 != Vector3.ZERO:
		# push toward the second wall as far as the cell allows
		corner_slide = 0.15 * signf(_side(dir).dot(dir2))
	match recipe:
		"boxes":
			var b := _against("box" if rng.randf() < 0.7 else "box_open", c, dir, corner_slide, 0.4)
			if rng.randf() < 0.45:
				var top := _against("box", c, dir, corner_slide + rng.randf_range(-0.05, 0.05), 0.6)
				top.position.y = (b.get_meta("size") as Vector3).y
			if rng.randf() < 0.5:
				var b2 := _against("box_open" if rng.randf() < 0.5 else "box", c, dir, corner_slide - 0.45 * signf(corner_slide + 0.01), 0.5, false)
				if rng.randf() < 0.3:
					b2.rotation.x = PI * 0.5  # tipped over
					b2.position.y = 0.0
			if rng.randf() < 0.4:
				var lp := level.cell_center(c) - dir * 0.15
				if level.is_open(level.world_to_cell(lp)):
					var n := _model(["notepads", "binder", "paper", "pad"][rng.randi() % 4])
					n.position = lp + _side(dir) * rng.randf_range(-0.2, 0.2)
					n.rotation.y = rng.randf() * TAU
		"chair":
			var kind: String = ["office_chair", "office_chair", "school_chair", "plastic_chair"][rng.randi() % 4]
			var ch := _model(kind)
			var p := level.cell_center(c) + dir * rng.randf_range(0.0, 0.08)
			ch.position = Vector3(p.x, 0, p.z)
			ch.rotation.y = rng.randf() * TAU
			if kind != "office_chair" and rng.randf() < 0.35:
				# knocked over onto its back
				ch.rotation = Vector3(-PI * 0.5 + 0.1, rng.randf() * TAU, 0)
				ch.position.y = 0.04
		"office":
			var m := _against("monitor", c, dir, corner_slide, 0.5)
			if rng.randf() < 0.4:
				m.rotation.x = -PI * 0.5  # face down
				m.position.y = 0.03
			var kb := _model("keyboard")
			var kp := level.cell_center(c) - dir * 0.1
			kb.position = Vector3(kp.x, 0, kp.z)
			kb.rotation.y = rng.randf() * TAU
			var top := level.cell_center(c) + dir * 0.2 + Vector3(0, 0.01, 0)
			_cable(top + _side(dir) * 0.15, level.cell_center(c) - dir * 0.05 + Vector3(0, 0.01, 0), -0.0, _mats.cable, 0.004)
		"trash":
			_against("trash_can", c, dir, corner_slide, 0.6)
			if rng.randf() < 0.7:
				_against("trashbag", c, dir, -0.4 if corner_slide >= 0 else 0.4, 1.5)
		"mop":
			_mop_bucket(level.cell_center(c) + dir * 0.12 - _side(dir) * 0.1, atan2(dir.x, dir.z))
			var sp := level.cell_center(c) - dir * 0.35 + _side(dir) * 0.35
			if level.is_open(level.world_to_cell(sp)):
				var sign := _model("wet_sign")
				sign.position = Vector3(sp.x, 0, sp.z)
				sign.rotation.y = rng.randf() * TAU
			_decal("wet_carpet", level.cell_center(c) - dir * 0.3, Vector3(1.4, 0.3, 1.1), Basis(Vector3.UP, rng.randf() * TAU), Color(1, 1, 1, 0.85), true)
		"papers":
			for k in rng.randi_range(2, 3):
				var n := _model(["notepads", "binder", "paper", "pad"][(k + rng.randi()) % 4])
				var lp := level.cell_center(c) + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
				n.position = lp
				n.rotation.y = rng.randf() * TAU
		"crates":
			var cr := _against("crate", c, dir, corner_slide, 0.3)
			if rng.randf() < 0.5:
				var top := _against("crate", c, dir, corner_slide, 0.2)
				top.position.y = (cr.get_meta("size") as Vector3).y
		"toolbox":
			_against("toolbox", c, dir, corner_slide, 0.8)
			if rng.randf() < 0.6:
				_against("crate", c, dir, -0.4 if corner_slide >= 0 else 0.4, 0.3)


func _mop_bucket(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(p.x, 0, p.z)
	root.rotation.y = yaw + rng.randf_range(-0.6, 0.6)
	var body := CylinderMesh.new()
	body.top_radius = 0.2
	body.bottom_radius = 0.17
	body.height = 0.32
	body.material = _mats.bucket
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.position.y = 0.21
	root.add_child(mi)
	var water := CylinderMesh.new()
	water.top_radius = 0.19
	water.bottom_radius = 0.19
	water.height = 0.01
	water.material = _mat(Color(0.25, 0.22, 0.12), 0.05)
	var wi := MeshInstance3D.new()
	wi.mesh = water
	wi.position.y = 0.3
	root.add_child(wi)
	for x in [-0.12, 0.12]:
		var wheel := MeshInstance3D.new()
		wheel.mesh = _box(Vector3(0.04, 0.05, 0.04), _mats.cable)
		wheel.position = Vector3(x, 0.025, 0.12)
		root.add_child(wheel)
	var wringer := MeshInstance3D.new()
	wringer.mesh = _box(Vector3(0.2, 0.16, 0.12), _mats.bucket)
	wringer.position = Vector3(0, 0.42, -0.12)
	root.add_child(wringer)
	# mop leaning on the rim
	var stick := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.012
	sm.bottom_radius = 0.012
	sm.height = 1.35
	sm.material = _mats.handle
	stick.mesh = sm
	stick.position = Vector3(0.02, 0.85, 0.02)
	stick.rotation = Vector3(0.22, 0, 0.12)
	root.add_child(stick)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.05
	hm.bottom_radius = 0.11
	hm.height = 0.22
	hm.material = _mats.mop
	head.mesh = hm
	head.position = Vector3(-0.05, 0.22, -0.08)
	root.add_child(head)
	_fade(root)
	var sb := StaticBody3D.new()
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.2
	shape.height = 0.5
	cs.shape = shape
	cs.position.y = 0.25
	sb.add_child(cs)
	root.add_child(sb)


# ---------------------------------------------------------------- bottles

## Bottles go where things end up in a building: along walls, tucked into
## corners, beside boxes; some fallen over.
func _place_bottles() -> void:
	for n in level.get_children():
		if not (n is Interactable) or n.get("kind") != "bottle":
			continue
		var b := n as Node3D
		var home := level.world_to_cell(b.position)
		var spot := _bottle_spot(home)
		if spot.is_empty():
			continue
		var cell: Vector2i = spot.cell
		var dir: Vector3 = spot.dir
		var side := _side(dir)
		var lying := rng.randf() < 0.35
		var p := level.cell_center(cell) + dir * (Level.CELL * 0.5 - 0.07)
		if spot.has("dir2"):
			p += (spot.dir2 as Vector3) * (Level.CELL * 0.5 - 0.07)
		else:
			p += side * rng.randf_range(-0.28, 0.28)
		if lying:
			# roll along the wall, label up-ish
			var yaw := atan2(side.x, side.z) + rng.randf_range(-0.35, 0.35)
			b.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, rng.randf() * TAU)
			p += -dir * 0.02 + Vector3(0, 0.033, 0)
		else:
			b.basis = Basis(Vector3.UP, rng.randf() * TAU)
		b.position = p
		if not lying and rng.randf() < 0.35:
			var box := _model("box")
			var bs: Vector3 = box.get_meta("size")
			box.rotation.y = atan2(dir.x, dir.z) + rng.randf_range(-0.3, 0.3)
			var bp := p + side * (0.12 + maxf(bs.x, bs.z) * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0) - dir * (maxf(bs.x, bs.z) * 0.5 - 0.07)
			if level.is_open(level.world_to_cell(bp)):
				box.position = Vector3(bp.x, 0, bp.z)
			else:
				box.queue_free()
		_used.append(p)


func _bottle_spot(home: Vector2i) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var c := home + Vector2i(dx, dy)
			if not level.is_open(c):
				continue
			var walls: Array[Vector3] = []
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if level.is_wall(c + d):
					walls.append(Vector3(d.x, 0, d.y))
			if walls.is_empty() or not _clear(level.cell_center(c), 0.9):
				continue
			var score := float(dx * dx + dy * dy) + rng.randf() * 4.0
			var is_corner := walls.size() >= 2 and absf(walls[0].dot(walls[1])) < 0.5
			if is_corner:
				score -= 6.0
			if score < best_d:
				best_d = score
				best = {"cell": c, "dir": walls[0]}
				if is_corner:
					best["dir2"] = walls[1]
	return best


func _smashed_bottles() -> void:
	var shard := _shard_mesh()
	var bottom := CylinderMesh.new()
	bottom.top_radius = 0.033
	bottom.bottom_radius = 0.032
	bottom.height = 0.05
	bottom.cap_top = false
	bottom.radial_segments = 12
	bottom.material = _mats.glass
	var neck := CylinderMesh.new()
	neck.top_radius = 0.013
	neck.bottom_radius = 0.03
	neck.height = 0.07
	neck.cap_bottom = false
	neck.radial_segments = 10
	neck.material = _mats.glass
	var label := QuadMesh.new()
	label.size = Vector2(0.08, 0.05)
	label.orientation = PlaneMesh.FACE_Y
	label.material = _mats.label
	var sites := 0
	for i in 60:
		if sites >= 10:
			break
		var s := _wall_spot(_zone_pick(), 4.0)
		if s.is_empty():
			continue
		var dir: Vector3 = s.dir
		# smashed against the wall: wet splash on the wall, glass fanning back out
		var center := level.cell_center(s.cell) + dir * rng.randf_range(0.0, 0.2)
		for k in rng.randi_range(10, 18):
			var r := rng.randf_range(0.03, 0.55) * sqrt(rng.randf())
			var ang := rng.randf() * TAU
			var at := center + Vector3(cos(ang) * r, 0.003, sin(ang) * r) - dir * rng.randf_range(0.0, 0.25)
			if level.is_wall(level.world_to_cell(at)):
				continue
			var sc := rng.randf_range(0.5, 1.6)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
			_add("shards", shard, Transform3D(b.scaled(Vector3(sc, 1.0, sc)), at))
		if rng.randf() < 0.75:
			_add("bottle_bottoms", bottom, Transform3D(Basis(Vector3.RIGHT, rng.randf_range(0.0, 1.3)).rotated(Vector3.UP, rng.randf() * TAU), center - dir * 0.15 + Vector3(0, 0.025, 0)))
		if rng.randf() < 0.6:
			_add("bottle_necks", neck, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5).rotated(Vector3.UP, rng.randf() * TAU), center - dir * rng.randf_range(0.1, 0.35) + Vector3(0, 0.02, 0)))
		_add("labels", label, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), center - dir * 0.2 + Vector3(0, 0.004, 0)))
		_decal("wet_carpet", center - dir * 0.1, Vector3(0.9, 0.3, 0.7), Basis(Vector3.UP, rng.randf() * TAU), Color(1, 1, 1, 0.7), true)
		_used.append(center)
		sites += 1


func _shard_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.012, 0, -0.01), Vector3(0.016, 0.0, -0.004), Vector3(0.002, 0.004, 0.02)]
	st.set_normal(Vector3.UP)
	for v in pts:
		st.add_vertex(v)
	var m := st.commit()
	m.surface_set_material(0, _mats.glass)
	return m
