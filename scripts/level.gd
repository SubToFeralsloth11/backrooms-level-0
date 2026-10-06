class_name Level
extends Node3D
## Procedural Level 0: seeded grid of wall cells laid out as irregular
## partitioned rooms, a dark maintenance wing (breaker room) and an unpowered
## exit hall. Builds merged geometry, collision, fluorescent panels with a
## pooled real-light system, decals, signs, and pathfinding.

const CELL := 0.75
const W := 96
const H := 96
const WALL_H := 2.75
const BLOCK := 6
const PANEL_STEP := 4
const LIGHT_POOL := 28
const SHADOW_LIGHTS := 2
const LIGHT_RADIUS := 13.0

enum Zone { MAIN, DARK, EXIT }

## Maintenance wing (dark, Smiler) and exit hall rects in cells.
const WING := Rect2i(62, 0, 34, 34)
const BREAKER := Rect2i(84, 0, 12, 11)
const EXIT_HALL := Rect2i(0, 74, 22, 22)

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var grid := PackedByteArray()  # 1 = wall
var zones := PackedByteArray()
var protected := PackedByteArray()
var astar := AStarGrid2D.new()
var puzzle: Puzzle

var spawn_cell := Vector2i(40, 48)
var wing_door := Vector2i()
var breaker_door := Vector2i()
var exit_hall_door := Vector2i()
var exit_door_x := 10
var reach_dist := PackedInt32Array()

var panels: Array[Dictionary] = []  # {pos, cell, zone, kind: on/off/flicker/broken, node?}
var _panel_mm := {}  # group -> MultiMeshInstance3D
var _lights: Array[OmniLight3D] = []
var _light_timer := 0.0
var _flicker_panels: Array[Dictionary] = []
var _mat := {}
var _hum: AudioStreamPlayer
var _tone: AudioStreamPlayer
var _ambient_timer := 8.0

var breaker_panel: Node3D
var keypad: Node3D
var exit_door: Node3D


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.09
	puzzle = Puzzle.new(seed_value)
	_build_grid()
	_build_materials()
	_build_geometry()
	_build_panels()
	_build_light_pool()
	_build_astar()
	_place_dressing()
	_place_puzzle()
	_build_audio()
	Game.power_changed.connect(_on_power)
	Game.blackout_changed.connect(_on_power)


# ---------------------------------------------------------------- grid

func idx(c: Vector2i) -> int:
	return c.y * W + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func is_wall(c: Vector2i) -> bool:
	return not in_bounds(c) or grid[idx(c)] == 1


func is_open(c: Vector2i) -> bool:
	return not is_wall(c)


func zone_of(c: Vector2i) -> int:
	return zones[idx(c)] if in_bounds(c) else Zone.MAIN


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / CELL)), 0, W - 1), clampi(int(floor(p.z / CELL)), 0, H - 1))


## True when a cell has no working light: the maintenance wing, the exit hall
## before power, or anywhere during a blackout.
func is_dark(c: Vector2i) -> bool:
	if Game.blackout:
		return true
	var z := zone_of(c)
	return z == Zone.DARK or (z == Zone.EXIT and not Game.power_on)


func _set_wall(c: Vector2i, v: int) -> void:
	if in_bounds(c) and protected[idx(c)] == 0:
		grid[idx(c)] = v


func _line(a: Vector2i, b: Vector2i, v: int, protect := false) -> void:
	var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var c := a
	while true:
		if in_bounds(c):
			grid[idx(c)] = v
			if protect:
				protected[idx(c)] = 1
		if c == b:
			break
		c += d


func _rect_fill(r: Rect2i, v: int, force := false) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if force:
				grid[idx(c)] = v
				protected[idx(c)] = 0
			else:
				_set_wall(c, v)


func _build_grid() -> void:
	grid.resize(W * H)
	grid.fill(0)
	zones.resize(W * H)
	zones.fill(Zone.MAIN)
	protected.resize(W * H)
	protected.fill(0)

	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if WING.has_point(c):
				zones[idx(c)] = Zone.DARK
			elif EXIT_HALL.has_point(c):
				zones[idx(c)] = Zone.EXIT

	# Interior partitions everywhere first; region walls are stamped over them.
	_partitions(Rect2i(1, 1, W - 2, H - 2))

	# Border.
	_line(Vector2i(0, 0), Vector2i(W - 1, 0), 1, true)
	_line(Vector2i(0, H - 1), Vector2i(W - 1, H - 1), 1, true)
	_line(Vector2i(0, 0), Vector2i(0, H - 1), 1, true)
	_line(Vector2i(W - 1, 0), Vector2i(W - 1, H - 1), 1, true)

	# Maintenance wing boundary with a single doorway on its west side.
	_line(Vector2i(WING.position.x, 0), Vector2i(WING.position.x, WING.end.y - 1), 1, true)
	_line(Vector2i(WING.position.x, WING.end.y - 1), Vector2i(W - 1, WING.end.y - 1), 1, true)
	wing_door = Vector2i(WING.position.x, rng.randi_range(8, WING.end.y - 8))
	_carve_door(wing_door, Vector2i(0, 1), 3)

	# Breaker room: closed box in the wing's far corner, one 2-cell door.
	_rect_fill(Rect2i(BREAKER.position.x + 1, 1, BREAKER.size.x - 2, BREAKER.size.y - 2), 0, true)
	_line(Vector2i(BREAKER.position.x, 0), Vector2i(BREAKER.position.x, BREAKER.end.y - 1), 1, true)
	_line(Vector2i(BREAKER.position.x, BREAKER.end.y - 1), Vector2i(W - 1, BREAKER.end.y - 1), 1, true)
	breaker_door = Vector2i(rng.randi_range(BREAKER.position.x + 3, W - 4), BREAKER.end.y - 1)
	_carve_door(breaker_door, Vector2i(1, 0), 2)

	# Exit hall boundary, single doorway on its north side.
	_line(Vector2i(EXIT_HALL.end.x - 1, EXIT_HALL.position.y), Vector2i(EXIT_HALL.end.x - 1, H - 1), 1, true)
	_line(Vector2i(0, EXIT_HALL.position.y), Vector2i(EXIT_HALL.end.x - 1, EXIT_HALL.position.y), 1, true)
	exit_hall_door = Vector2i(rng.randi_range(4, EXIT_HALL.end.x - 6), EXIT_HALL.position.y)
	_carve_door(exit_hall_door, Vector2i(1, 0), 3)

	# Exit door is set into the south border; clear a vestibule in front of it.
	exit_door_x = rng.randi_range(5, EXIT_HALL.end.x - 8)
	_rect_fill(Rect2i(exit_door_x - 3, H - 6, 8, 5), 0, true)
	for dx in 2:
		grid[idx(Vector2i(exit_door_x + dx, H - 1))] = 0

	# Spawn room clear.
	spawn_cell = Vector2i(rng.randi_range(30, 50), rng.randi_range(36, 56))
	_rect_fill(Rect2i(spawn_cell.x - 2, spawn_cell.y - 2, 5, 5), 0, true)

	_connect_regions()


func _carve_door(c: Vector2i, along: Vector2i, width: int) -> void:
	var across := Vector2i(along.y, along.x)
	for i in width:
		var d := c + along * i
		grid[idx(d)] = 0
		# keep both sides of a doorway walkable so interiors can't plug it
		for s in [-1, 1]:
			var side: Vector2i = d + across * s
			if in_bounds(side) and protected[idx(side)] == 0:
				grid[idx(side)] = 0
				protected[idx(side)] = 1
		protected[idx(d)] = 1


func _partitions(area: Rect2i) -> void:
	var bx0 := area.position.x / BLOCK
	var by0 := area.position.y / BLOCK
	var bx1 := area.end.x / BLOCK
	var by1 := area.end.y / BLOCK
	for by in range(by0, by1 + 1):
		for bx in range(bx0, bx1 + 1):
			var x := bx * BLOCK
			var y := by * BLOCK
			# Density varies across the map: open halls next to cramped mazes.
			var density := remap(noise.get_noise_2d(bx, by), -0.6, 0.6, 0.18, 0.78)
			if zone_of(Vector2i(x, y)) == Zone.DARK:
				density += 0.15
			# vertical segment
			if rng.randf() < density:
				_wall_segment(Vector2i(x, y), Vector2i(0, 1))
			# horizontal segment
			if rng.randf() < density:
				_wall_segment(Vector2i(x, y), Vector2i(1, 0))
			# pillars at open corners of big halls
			if density < 0.35 and rng.randf() < 0.55:
				_set_wall(Vector2i(x, y), 1)
			# occasional stub wall inside a block for irregular rooms
			if rng.randf() < density * 0.35:
				var o := Vector2i(x + rng.randi_range(2, BLOCK - 2), y + rng.randi_range(2, BLOCK - 2))
				var dir := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
				for i in rng.randi_range(2, 4):
					_set_wall(o + dir * i, 1)


func _wall_segment(start: Vector2i, dir: Vector2i) -> void:
	for i in BLOCK + 1:
		_set_wall(start + dir * i, 1)
	if rng.randf() < 0.78:
		var gap := rng.randi_range(2, 3)
		var off := rng.randi_range(1, BLOCK - gap)
		for i in gap:
			_set_wall(start + dir * (off + i), 0)


func _flood(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(-1)
	var q: Array[Vector2i] = [from]
	dist[idx(from)] = 0
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if in_bounds(n) and grid[idx(n)] == 0 and dist[idx(n)] == -1:
				dist[idx(n)] = dist[idx(c)] + 1
				q.append(n)
	return dist


## Knock holes through unprotected walls until everything is reachable.
func _connect_regions() -> void:
	for iter in 400:
		var dist := _flood(spawn_cell)
		var carved := false
		var candidates: Array[Vector2i] = []
		for y in range(1, H - 1):
			for x in range(1, W - 1):
				var c := Vector2i(x, y)
				if grid[idx(c)] == 0 or protected[idx(c)] == 1:
					continue
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					var a: Vector2i = c - d
					var b: Vector2i = c + d
					if grid[idx(a)] == 0 and grid[idx(b)] == 0 and (dist[idx(a)] == -1) != (dist[idx(b)] == -1):
						candidates.append(c)
		if candidates.is_empty():
			break
		# carve a few random connections per pass (2-wide when possible)
		for k in mini(3, candidates.size()):
			var c: Vector2i = candidates[rng.randi() % candidates.size()]
			grid[idx(c)] = 0
			carved = true
		if not carved:
			break
	reach_dist = _flood(spawn_cell)
	for i in W * H:
		if grid[i] == 0 and reach_dist[i] == -1:
			grid[i] = 1


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in H:
		for x in W:
			if grid[y * W + x] == 1:
				astar.set_point_solid(Vector2i(x, y), true)


## World-space path between two points (cell centres), empty if unreachable.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := world_to_cell(from)
	var b := world_to_cell(to)
	if is_wall(a):
		a = nearest_open(a)
	if is_wall(b):
		b = nearest_open(b)
	var cells := astar.get_id_path(a, b, true)
	var out := PackedVector3Array()
	for c in cells:
		out.append(cell_center(c))
	return out


func nearest_open(c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if is_open(n):
					return n
	return spawn_cell


func random_open_cell(zone_filter: int = -1, avoid: Vector3 = Vector3.INF, min_dist := 0.0) -> Vector2i:
	for i in 2000:
		var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
		if not is_open(c):
			continue
		if zone_filter >= 0 and zone_of(c) != zone_filter:
			continue
		if avoid != Vector3.INF and cell_center(c).distance_to(avoid) < min_dist:
			continue
		return c
	return spawn_cell


## Open cell next to a wall; returns {cell, dir} where dir points into the wall.
func wall_spot(zone_filter: int, avoid: Array, min_sep: float) -> Dictionary:
	for i in 4000:
		var c := Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if not is_open(c) or (zone_filter >= 0 and zone_of(c) != zone_filter):
			continue
		var p := cell_center(c)
		var ok := true
		for a in avoid:
			if p.distance_to(a) < min_sep:
				ok = false
				break
		if not ok:
			continue
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		dirs.shuffle()
		for d in dirs:
			# need a straight wall at least 3 cells wide for a clean surface
			var side := Vector2i(d.y, d.x)
			if is_wall(c + d) and is_wall(c + d + side) and is_wall(c + d - side) and is_open(c - d):
				return {"cell": c, "dir": Vector3(d.x, 0, d.y)}
	return {}


# ---------------------------------------------------------------- materials

func _tex(base: String) -> Texture2D:
	for e in ["png", "jpg", "jpeg", "webp"]:
		var p := "res://textures/%s.%s" % [base, e]
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _pbr(base: String, fallback: Color, meters: float, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = fallback
	var alb := _tex(base + "_albedo")
	if alb:
		m.albedo_color = Color.WHITE
		m.albedo_texture = alb
	var nrm := _tex(base + "_normal")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 1.0
	var rgh := _tex(base + "_roughness")
	m.roughness = 1.0 if rgh else rough
	if rgh:
		m.roughness_texture = rgh
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / meters
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _build_materials() -> void:
	_mat.wall = _pbr("wallpaper", Color(0.78, 0.71, 0.42), 1.0, 0.8)
	_mat.carpet = _pbr("carpet", Color(0.62, 0.52, 0.30), 1.0, 0.95)
	_mat.ceiling = _pbr("ceiling", Color(0.82, 0.80, 0.70), 3.6, 0.9)
	_mat.ceiling.metallic_specular = 0.08  # acoustic tile: no glints along the T-bar grooves
	_mat.carpet.metallic_specular = 0.2
	_mat.concrete = _pbr("concrete", Color(0.45, 0.44, 0.42), 3.0, 0.9)
	_mat.metal = _pbr("metal", Color(0.35, 0.38, 0.36), 1.0, 0.55)
	var mtl := _tex("metal_metallic")
	if mtl:
		_mat.metal.metallic_texture = mtl
		_mat.metal.metallic = 1.0
	else:
		_mat.metal.metallic = 0.6
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.42, 0.34, 0.2)
	base.roughness = 0.6
	_mat.baseboard = base

	var on := StandardMaterial3D.new()
	on.albedo_color = Color(1, 0.97, 0.88)
	on.emission_enabled = true
	on.emission = Color(1.0, 0.95, 0.82)
	on.emission_energy_multiplier = 1.7
	on.roughness = 0.4
	_mat.panel_on = on
	var off := StandardMaterial3D.new()
	off.albedo_color = Color(0.55, 0.54, 0.5)
	off.roughness = 0.35
	off.metallic_specular = 0.7
	_mat.panel_off = off
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.42, 0.41, 0.38)
	frame.roughness = 0.85
	frame.metallic = 0.0
	frame.metallic_specular = 0.15
	_mat.panel_frame = frame


# ---------------------------------------------------------------- geometry

func _merged_rects() -> Array[Rect2i]:
	var used := PackedByteArray()
	used.resize(W * H)
	var rects: Array[Rect2i] = []
	for y in H:
		for x in W:
			var i := y * W + x
			if grid[i] == 0 or used[i] == 1:
				continue
			var w := 1
			while x + w < W and grid[i + w] == 1 and used[i + w] == 0:
				w += 1
			var h := 1
			var grow := true
			while grow and y + h < H:
				for k in w:
					var j := (y + h) * W + x + k
					if grid[j] == 0 or used[j] == 1:
						grow = false
						break
				if grow:
					h += 1
			for yy in h:
				for xx in w:
					used[(y + yy) * W + x + xx] = 1
			rects.append(Rect2i(x, y, w, h))
	return rects


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	# a-b-c-d counter-clockwise when viewed from the side n points to
	for v in [[a, Vector2(0, 1)], [c, Vector2(1, 0)], [b, Vector2(1, 1)], [a, Vector2(0, 1)], [d, Vector2(0, 0)], [c, Vector2(1, 0)]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _box_sides(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float) -> void:
	# +X, -X, +Z, -Z faces
	_quad(st, Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3.RIGHT)
	_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT)
	_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK)
	_quad(st, Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD)


func _build_geometry() -> void:
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "WorldBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for r in _merged_rects():
		var x0 := r.position.x * CELL
		var z0 := r.position.y * CELL
		var x1 := r.end.x * CELL
		var z1 := r.end.y * CELL
		_box_sides(walls, x0, z0, x1, z1, 0.0, WALL_H)
		var t := 0.012
		_box_sides(trim, x0 - t, z0 - t, x1 + t, z1 + t, 0.0, 0.09)
		# trim top lip
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(x1 - x0, WALL_H, z1 - z0)
		cs.shape = bs
		cs.position = Vector3((x0 + x1) * 0.5, WALL_H * 0.5, (z0 + z1) * 0.5)
		body.add_child(cs)
	walls.generate_tangents()
	trim.generate_tangents()
	var wall_mesh := walls.commit()
	wall_mesh.surface_set_material(0, _mat.wall)
	trim.commit(wall_mesh)
	wall_mesh.surface_set_material(1, _mat.baseboard)
	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = wall_mesh
	add_child(mi)

	var size_x := W * CELL
	var size_z := H * CELL
	_slab("Floor", _mat.carpet, Vector3(size_x * 0.5, -0.05, size_z * 0.5), Vector3(size_x + 6, 0.1, size_z + 6), body)
	_slab("Ceiling", _mat.ceiling, Vector3(size_x * 0.5, WALL_H + 0.05, size_z * 0.5), Vector3(size_x + 6, 0.1, size_z + 6), body)


func _slab(slab_name: String, mat: Material, center: Vector3, size: Vector3, body: StaticBody3D) -> void:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = slab_name
	mi.mesh = m
	mi.position = center
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	body.add_child(cs)


# ---------------------------------------------------------------- lights

func _build_panels() -> void:
	var groups := {"main": [], "exit": [], "off": []}
	for y in range(2, H - 2, PANEL_STEP):
		for x in range(2, W - 2, PANEL_STEP):
			var c := Vector2i(x, y)
			if not is_open(c) or not is_open(c + Vector2i(0, 1)):
				continue
			var z := zone_of(c)
			var p := Vector3((x + 0.5) * CELL, WALL_H - 0.02, (y + 1.0) * CELL)
			var kind := "on"
			if z == Zone.DARK:
				kind = "dead"
			elif rng.randf() < 0.06:
				kind = "dead"
			elif rng.randf() < 0.07:
				kind = "flicker"
			var pd := {"pos": p, "cell": c, "zone": z, "kind": kind, "level": 1.0, "timer": rng.randf_range(0.5, 6.0), "burst": 0.0}
			panels.append(pd)
			if kind == "flicker":
				var mi := MeshInstance3D.new()
				mi.mesh = _panel_mesh()
				mi.position = p
				var mat: StandardMaterial3D = _mat.panel_on.duplicate()
				mi.set_surface_override_material(0, mat)
				pd["node"] = mi
				pd["mat"] = mat
				add_child(mi)
				_flicker_panels.append(pd)
			elif kind == "dead":
				groups.off.append(p)
			elif z == Zone.EXIT:
				groups.exit.append(p)
			else:
				groups.main.append(p)
	for g in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _panel_mesh()
		mm.instance_count = groups[g].size()
		for i in groups[g].size():
			mm.set_instance_transform(i, Transform3D(Basis(), groups[g][i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Panels_" + g
		mmi.multimesh = mm
		add_child(mmi)
		_panel_mm[g] = mmi
	_refresh_panel_materials()


## Panel mesh with the diffuser lit or unlit; the frame keeps its matte material.
func _panel_mesh(lit := true) -> Mesh:
	var key := "panel_mesh_on" if lit else "panel_mesh_off"
	if _mat.has(key):
		return _mat[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := 0.3
	var hz := 0.6
	# diffuser (facing down)
	_quad(st, Vector3(-hx, -0.015, -hz), Vector3(hx, -0.015, -hz), Vector3(hx, -0.015, hz), Vector3(-hx, -0.015, hz), Vector3.DOWN)
	var diffuser := st.commit()
	var fr := SurfaceTool.new()
	fr.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_sides(fr, -hx - 0.03, -hz - 0.03, hx + 0.03, hz + 0.03, -0.02, 0.0)
	# frame lip below the diffuser
	_quad(fr, Vector3(-hx - 0.03, -0.02, hz), Vector3(hx + 0.03, -0.02, hz), Vector3(hx + 0.03, -0.02, hz + 0.03), Vector3(-hx - 0.03, -0.02, hz + 0.03), Vector3.DOWN)
	_quad(fr, Vector3(-hx - 0.03, -0.02, -hz - 0.03), Vector3(hx + 0.03, -0.02, -hz - 0.03), Vector3(hx + 0.03, -0.02, -hz), Vector3(-hx - 0.03, -0.02, -hz), Vector3.DOWN)
	fr.commit(diffuser)
	diffuser.surface_set_material(0, _mat.panel_on if lit else _mat.panel_off)
	diffuser.surface_set_material(1, _mat.panel_frame)
	_mat[key] = diffuser
	return diffuser


func _panel_lit(pd: Dictionary) -> bool:
	if Game.blackout or pd.kind == "dead":
		return false
	if pd.zone == Zone.EXIT and not Game.power_on:
		return false
	return true


func _refresh_panel_materials() -> void:
	var main_on := not Game.blackout
	var exit_on := main_on and Game.power_on
	_panel_mm.main.multimesh.mesh = _panel_mesh(main_on)
	_panel_mm.exit.multimesh.mesh = _panel_mesh(exit_on)
	_panel_mm.off.multimesh.mesh = _panel_mesh(false)
	for pd in _flicker_panels:
		if not _panel_lit(pd):
			(pd.mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	_light_timer = 0.0


func _build_light_pool() -> void:
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.93, 0.78)
		l.omni_range = 7.5
		l.omni_attenuation = 1.35
		l.light_energy = 0.0
		l.light_specular = 0.35
		l.shadow_enabled = i < SHADOW_LIGHTS
		l.shadow_bias = 0.05
		l.shadow_normal_bias = 1.5
		l.light_size = 0.35
		l.distance_fade_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)


func _process(delta: float) -> void:
	_update_flicker(delta)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.12
		_assign_lights()
	_update_light_levels()
	_update_ambience(delta)


func _update_flicker(delta: float) -> void:
	var listener := _listener_pos()
	for pd in _flicker_panels:
		if not _panel_lit(pd):
			pd.level = 0.0
			continue
		pd.timer -= delta
		if pd.burst > 0.0:
			pd.burst -= delta
			if pd.timer <= 0.0:
				pd.timer = rng.randf_range(0.03, 0.14)
				pd.level = 0.0 if pd.level > 0.5 else rng.randf_range(0.6, 1.0)
			if pd.burst <= 0.0:
				pd.level = 1.0
				pd.timer = rng.randf_range(1.5, 9.0)
		elif pd.timer <= 0.0:
			pd.burst = rng.randf_range(0.25, 1.6)
			pd.timer = 0.0
			if listener.distance_to(pd.pos) < 16.0:
				Audio.play_3d("light_flicker", pd.pos, -4.0, 18.0, 0.1)
		(pd.mat as StandardMaterial3D).emission_energy_multiplier = 1.7 * pd.level


func _listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _assign_lights() -> void:
	var cam := _listener_pos()
	var near: Array = []
	for pd in panels:
		if not _panel_lit(pd):
			continue
		var d: float = (pd.pos as Vector3).distance_to(cam)
		if d < LIGHT_RADIUS:
			near.append([d, pd])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in _lights.size():
		var l := _lights[i]
		if i < near.size():
			var pd: Dictionary = near[i][1]
			l.position = pd.pos + Vector3(0, -0.35, 0)
			l.set_meta("panel", pd)
			l.set_meta("dist", near[i][0])
			l.visible = true
		else:
			l.visible = false
			l.set_meta("panel", null)


func _update_light_levels() -> void:
	for l in _lights:
		if not l.visible:
			continue
		var pd: Variant = l.get_meta("panel", null)
		if pd == null:
			continue
		var d: float = l.get_meta("dist", 0.0)
		var fade := 1.0 - smoothstep(LIGHT_RADIUS - 4.0, LIGHT_RADIUS, d)
		l.light_energy = 0.8 * fade * float(pd.level)


func _on_power(_on: bool) -> void:
	_refresh_panel_materials()


# ---------------------------------------------------------------- ambience

func _build_audio() -> void:
	_hum = AudioStreamPlayer.new()
	_hum.stream = Audio.loop_stream("hum_fluorescent")
	_hum.bus = "Ambience"
	_hum.volume_db = -14.0
	add_child(_hum)
	_tone = AudioStreamPlayer.new()
	_tone.stream = Audio.loop_stream("room_tone")
	_tone.bus = "Ambience"
	_tone.volume_db = -20.0
	add_child(_tone)


func start_ambience() -> void:
	if _hum.stream:
		_hum.play(randf() * 3.0)
	if _tone.stream:
		_tone.play(randf() * 3.0)


func _update_ambience(delta: float) -> void:
	if _hum == null:
		return
	# Hum follows the lights: total silence of the hum in the dark is unnerving.
	var lit := 0.0
	for l in _lights:
		if l.visible:
			lit += l.light_energy
	var target := -40.0 if lit < 0.2 else lerpf(-24.0, -11.0, clampf(lit / 6.0, 0.0, 1.0))
	_hum.volume_db = lerpf(_hum.volume_db, target, delta * 2.5)
	if Game.is_playing():
		_ambient_timer -= delta
		if _ambient_timer <= 0.0:
			_ambient_timer = rng.randf_range(18.0, 50.0)
			var cam := _listener_pos()
			var ang := rng.randf() * TAU
			var p := cam + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(18.0, 35.0)
			p.y = 1.5
			var s: String = ["distant_thud", "distant_creak"][rng.randi() % 2]
			Audio.play_3d(s, p, 2.0, 60.0, 0.15)


# ---------------------------------------------------------------- dressing

func _decal(tex_name: String, pos: Vector3, size: Vector3, basis := Basis(), modulate := Color.WHITE) -> Decal:
	var d := Decal.new()
	d.texture_albedo = load("res://textures/decals/%s.png" % tex_name)
	d.size = size
	d.modulate = modulate
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 30.0
	d.distance_fade_length = 8.0
	d.basis = basis
	add_child(d)
	d.position = pos
	return d


## Basis for a decal projecting into a wall in direction `dir` with image-up = world up.
func wall_basis(dir: Vector3, roll := 0.0) -> Basis:
	var y := -dir
	var z := Vector3.DOWN
	var x := y.cross(z)
	var b := Basis(x, y, z)
	return b.rotated(dir, roll) if roll != 0.0 else b


func wall_point(spot: Dictionary, height: float) -> Vector3:
	var c: Vector2i = spot.cell
	var dir: Vector3 = spot.dir
	return cell_center(c) + dir * (CELL * 0.5) + Vector3(0, height, 0)


func _place_dressing() -> void:
	var used: Array = [cell_center(spawn_cell)]
	# Damp stains on carpet and ceiling-drip patches.
	for i in 45:
		var c := random_open_cell()
		var s := rng.randf_range(0.8, 2.4)
		_decal("stain_damp_%d" % (1 + i % 2), cell_center(c) + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)),
			Vector3(s, 0.4, s), Basis(Vector3.UP, rng.randf() * TAU), Color(1, 1, 1, rng.randf_range(0.45, 0.85)))
	# Blood: a few violent scenes in the main area, more in the wing.
	for i in 9:
		var c := random_open_cell(Zone.MAIN if i < 6 else Zone.DARK, cell_center(spawn_cell), 12.0)
		var p := cell_center(c)
		var s := rng.randf_range(0.9, 1.6)
		_decal("blood_splat_%d" % (1 + i % 4), p, Vector3(s, 0.4, s), Basis(Vector3.UP, rng.randf() * TAU))
		# a drag trail leaving the scene
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		for k in rng.randi_range(1, 3):
			var q := p + dir * (1.1 + k * 1.4)
			if is_wall(world_to_cell(q)):
				break
			_decal("blood_smear_%d" % (1 + k % 2), q, Vector3(1.6, 0.4, 0.8), Basis(Vector3.UP, -ang), Color(1, 1, 1, 0.9 - k * 0.2))
		used.append(p)
	# Hand prints and drips on walls.
	for i in 10:
		var spot := wall_spot(-1, used, 6.0)
		if spot.is_empty():
			continue
		var tex := "blood_hand" if i % 3 != 0 else "blood_drips"
		var sz := Vector3(0.32, 0.3, 0.34) if tex == "blood_hand" else Vector3(1.1, 0.3, 1.3)
		_decal(tex, wall_point(spot, rng.randf_range(0.9, 1.5)), sz, wall_basis(spot.dir, rng.randf_range(-0.4, 0.4)))
		used.append(cell_center(spot.cell))

	# Signage.
	_sign_over_door(wing_door, Vector3.LEFT, "MAINTENANCE\nAUTHORIZED PERSONNEL ONLY", Color(0.75, 0.1, 0.08))
	_sign_over_door(breaker_door, Vector3.BACK, "ELECTRICAL  -  B4", Color(0.85, 0.65, 0.05))
	_sign_over_door(exit_hall_door, Vector3.FORWARD, "EXIT", Color(0.1, 0.55, 0.2), true)
	# Liar signs: EXIT arrows in the main area pointing nowhere useful.
	for i in 5:
		var spot := wall_spot(Zone.MAIN, used, 10.0)
		if spot.is_empty():
			continue
		var arrows := ["EXIT  →", "←  EXIT", "EXIT  ↑"]
		_wall_sign(spot, 2.2, arrows[rng.randi() % arrows.size()], Color(0.1, 0.55, 0.2), true)
		used.append(cell_center(spot.cell))
	# Handwritten warnings taped to walls.
	var scrawls := ["DONT RUN", "IT CANT SEE YOU\nIT HEARS YOU", "KEEP THE LIGHT ON IT", "DON'T LOOK AWAY", "NO EXIT", "IT'S NOT A WAY OUT"]
	for i in scrawls.size():
		var spot := wall_spot(Zone.MAIN, used, 9.0)
		if spot.is_empty():
			continue
		_scrawl(spot, rng.randf_range(1.2, 1.7), scrawls[i], Color(0.33, 0.02, 0.015), 0.11)
		used.append(cell_center(spot.cell))


func _sign_plate(pos: Vector3, facing: Vector3, text: String, color: Color, size: Vector2, glow := false) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.look_at(pos - facing, Vector3.UP)  # +Z faces into the room
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.025)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = color
	pm.roughness = 0.45
	if glow:
		pm.emission_enabled = true
		pm.emission = color
		pm.emission_energy_multiplier = 1.8
	bm.material = pm
	plate.mesh = bm
	root.add_child(plate)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font = load("res://fonts/sign.ttf") if ResourceLoader.exists("res://fonts/sign.ttf") else null
	lbl.font_size = 64
	lbl.pixel_size = 0.0022
	lbl.modulate = Color(0.95, 0.95, 0.9)
	lbl.outline_size = 0
	lbl.shaded = not glow
	lbl.double_sided = false
	lbl.position = Vector3(0, 0, 0.014)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lbl)
	if glow:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 0.25
		l.omni_range = 1.6
		l.position = Vector3(0, 0, 0.25)
		root.add_child(l)
	return root


func _sign_over_door(door: Vector2i, into_room: Vector3, text: String, color: Color, glow := false) -> void:
	# door cell lies in a wall line; place sign on the face toward the approach side
	var p := cell_center(door) - into_room * (CELL * 0.5 + 0.02) + Vector3(0, WALL_H - 0.32, 0)
	# shift to the middle of the doorway width
	var along := Vector3(absf(into_room.z), 0, absf(into_room.x))
	p += along * CELL
	_sign_plate(p, into_room, text, color, Vector2(1.3, 0.3) if "\n" in text else Vector2(0.9, 0.24), glow)


func _wall_sign(spot: Dictionary, height: float, text: String, color: Color, glow := false) -> void:
	var p := wall_point(spot, height) - (spot.dir as Vector3) * 0.02
	_sign_plate(p, -(spot.dir as Vector3), text, color, Vector2(0.62, 0.2), glow)


func _scrawl(spot: Dictionary, height: float, text: String, color: Color, size: float) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	if ResourceLoader.exists("res://fonts/scrawl.ttf"):
		lbl.font = load("res://fonts/scrawl.ttf")
	lbl.font_size = 96
	lbl.pixel_size = size / 96.0
	lbl.modulate = color
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.double_sided = false
	lbl.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(lbl)
	var p := wall_point(spot, height) - (spot.dir as Vector3) * 0.006
	lbl.position = p
	lbl.look_at(p + (spot.dir as Vector3), Vector3.UP)
	lbl.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.08, 0.08))
	return lbl


# ---------------------------------------------------------------- puzzle props

func _place_puzzle() -> void:
	var used: Array = [cell_center(spawn_cell)]
	var Pickup := preload("res://scripts/pickup.gd")

	# Intro note close to spawn (dead end preferred so it's found but not handed over).
	var intro := _note_spot(cell_center(spawn_cell), 3.0, 9.0, used)
	_spawn_note(intro, "intro", Notes.intro())

	# Clue notes, far apart; one hidden inside the maintenance wing.
	for i in puzzle.note_clues.size():
		var z := Zone.DARK if i == 3 else Zone.MAIN
		var p := _far_spot(z, used, 22.0)
		_spawn_note(p, "clue_%d" % i, Notes.clue(i, puzzle.note_clues[i]))
		used.append(p)

	# Breaker panel on the breaker room's far (east) wall, note at its foot.
	var bp_cell := Vector2i(W - 2, rng.randi_range(3, BREAKER.end.y - 4))
	var BreakerPanel := preload("res://scripts/breaker_panel.gd")
	breaker_panel = BreakerPanel.new()
	breaker_panel.puzzle = puzzle
	add_child(breaker_panel)
	breaker_panel.position = cell_center(bp_cell) + Vector3(CELL * 0.5 - 0.06, 1.35, 0)
	breaker_panel.look_at(breaker_panel.position + Vector3.RIGHT, Vector3.UP)
	_spawn_note(cell_center(bp_cell + Vector2i(-1, 2)), "breaker", Notes.breaker())
	var bl := OmniLight3D.new()  # tiny emergency light: red, almost useless
	bl.light_color = Color(1, 0.12, 0.08)
	bl.light_energy = 0.35
	bl.omni_range = 3.0
	bl.position = cell_center(bp_cell + Vector2i(-2, 0)) + Vector3(0, WALL_H - 0.2, 0)
	add_child(bl)

	# Exit door and keypad.
	var ExitDoor := preload("res://scripts/exit_door.gd")
	exit_door = ExitDoor.new()
	exit_door.level = self
	add_child(exit_door)
	exit_door.position = Vector3((exit_door_x + 1) * CELL, 0, (H - 1) * CELL)
	var Keypad := preload("res://scripts/keypad.gd")
	keypad = Keypad.new()
	keypad.puzzle = puzzle
	keypad.door = exit_door
	add_child(keypad)
	keypad.position = Vector3((exit_door_x + 3.2) * CELL, 1.35, (H - 1) * CELL - 0.03)
	keypad.rotation.y = PI

	# Blood code: fresh red writings (true) and old brown ones (lies).
	var writings := []
	for s in Puzzle.SYMBOL_COUNT:
		writings.append({"symbol": s, "digit": puzzle.code[s], "fresh": true})
	for d in puzzle.decoys:
		writings.append({"symbol": d.symbol, "digit": d.digit, "fresh": false})
	writings.shuffle()
	for w in writings:
		var zf := Zone.MAIN
		var spot := wall_spot(zf, used, 14.0)
		if spot.is_empty():
			spot = wall_spot(zf, used, 6.0)
		_blood_code(spot, w.symbol, w.digit, w.fresh)
		used.append(cell_center(spot.cell))

	# Batteries and almond-water bottles.
	for i in 6:
		var c := random_open_cell(-1, cell_center(spawn_cell), 8.0)
		var b: Node3D = Pickup.new()
		b.kind = "battery"
		add_child(b)
		b.position = cell_center(c) + Vector3(rng.randf_range(-0.2, 0.2), 0.02, rng.randf_range(-0.2, 0.2))
	for i in 10:
		var c := random_open_cell(-1, Vector3.INF, 0.0)
		var b: Node3D = Pickup.new()
		b.kind = "bottle"
		add_child(b)
		b.position = cell_center(c) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))


func _spawn_note(p: Vector3, id: String, text: String) -> void:
	var Pickup := preload("res://scripts/pickup.gd")
	var n: Node3D = Pickup.new()
	n.kind = "note"
	n.note_id = id
	n.note_text = text
	add_child(n)
	n.position = p + Vector3(rng.randf_range(-0.15, 0.15), 0.004, rng.randf_range(-0.15, 0.15))
	n.rotation.y = rng.randf() * TAU


## Dead-end-ish cell in distance band from `from`.
func _note_spot(from: Vector3, dmin: float, dmax: float, used: Array) -> Vector3:
	var best := Vector3.INF
	var best_score := -1.0
	for i in 600:
		var c := random_open_cell(Zone.MAIN)
		var p := cell_center(c)
		var d := p.distance_to(from)
		if d < dmin or d > dmax:
			continue
		var score := float(_wall_neighbours(c)) + rng.randf()
		if score > best_score:
			best_score = score
			best = p
	return best if best != Vector3.INF else cell_center(nearest_open(spawn_cell + Vector2i(2, 0)))


func _far_spot(z: int, used: Array, min_sep: float) -> Vector3:
	var best := Vector3.ZERO
	var best_score := -1.0
	for i in 900:
		var c := random_open_cell(z)
		var p := cell_center(c)
		var sep := 1e9
		for u in used:
			sep = minf(sep, p.distance_to(u))
		if sep < min_sep * 0.5:
			continue
		var score := minf(sep, min_sep * 1.5) + _wall_neighbours(c) * 3.0
		if z == Zone.DARK and BREAKER.has_point(c):
			continue
		if score > best_score:
			best_score = score
			best = p
	return best


func _wall_neighbours(c: Vector2i) -> int:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if is_wall(c + d):
			n += 1
	return n


func _blood_code(spot: Dictionary, symbol: int, digit: int, fresh: bool) -> void:
	var h := rng.randf_range(1.15, 1.6)
	var wp := wall_point(spot, h)
	var dir: Vector3 = spot.dir
	var side := Vector3(-dir.z, 0, dir.x)
	# fresh blood: wet, bright, dripping; old: dry brown-black and matte
	var col := Color(0.42, 0.02, 0.015) if fresh else Color(0.2, 0.11, 0.06)
	var sym := Decal.new()
	sym.texture_albedo = load("res://textures/symbols/sym_%d.png" % symbol)
	sym.modulate = col
	sym.size = Vector3(0.36, 0.3, 0.36)
	sym.basis = wall_basis(dir, rng.randf_range(-0.12, 0.12))
	sym.cull_mask = 1
	add_child(sym)
	sym.position = wp - side * 0.22
	var lbl := _scrawl(spot, h - 0.07, str(digit), col, 0.34)
	lbl.position = wp + side * 0.2 - dir * 0.006 + Vector3(0, -0.05, 0)
	if fresh:
		_decal("blood_drips", wp + Vector3(0, -0.28, 0), Vector3(0.75, 0.3, 0.55), wall_basis(dir), Color(1, 1, 1, 0.85))
	else:
		_decal("stain_damp_1", wp, Vector3(1.0, 0.3, 0.9), wall_basis(dir, rng.randf() * TAU), Color(0.7, 0.6, 0.5, 0.5))
