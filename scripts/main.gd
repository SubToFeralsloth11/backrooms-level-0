extends Node
## Builds the world for a run (environment, level, player, entities, UI) and
## handles menu / pause / death / escape flow.
##
## Dev user args (after `--`): --auto (skip menu), --seed=N,
## --look=x,z,yaw,pitch (place camera), --shot=path.png (screenshot after
## --wait=s seconds, then quit), --flash (flashlight on), --power, --blackout,
## --entity=hollow|smiler|watcher (spawn 3 m ahead for inspection), --nomonsters,
## --nointro (skip the intro fall), --intro (play it even with --shot).
##
## Retry keeps the layout but reseeds the puzzle (new clues, new code, new
## spawns). Every generated level is validated; a bad one regenerates at seed+1.

var world: Node3D
var level: Level
var player: Player
var ui: UI
var entities: Array[Node3D] = []
var _watcher: Node3D
var _intro_played := false
var _args := {}
var _first_worst := 0.0
var _second_worst := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if _args.has("seed"):
		Game.seed_value = int(_args.seed)
	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)
	ui.start_pressed.connect(func(): _start(false))
	ui.retry_pressed.connect(func(): _start(false, true))
	ui.new_level_pressed.connect(func(): _start(true))
	ui.quit_pressed.connect(func(): get_tree().quit())
	ui.menu_pressed.connect(_to_menu)
	Game.player_died.connect(func(c): ui.show_death(c))
	Game.wrong_lever.connect(_wake_watcher)
	Game.escaped.connect(_on_escape)
	if _args.has("auto"):
		_start(false)
	else:
		ui.show_menu()


## retry: same layout, new puzzle seed and entity spawn spots.
func _start(new_seed: bool, retry := false) -> void:
	if new_seed:
		Game.new_seed()
	Game.puzzle_seed = randi() % 1000000 if retry else -1
	_clear_world()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	_build_environment()
	_generate_level()
	if retry:
		level.rng.seed = Game.puzzle_seed  # spawns differ from the last attempt
	Game.level = level
	# parse creature meshes now, not on the frame a monster first appears
	for m in ["hollow", "hollow_lod", "watcher", "watcher_lod"]:
		Creature._load(m)
	player = Player.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = level.cell_center(level.spawn_cell) + Vector3(0, 0.05, 0)
	player.rotation.y = randf() * TAU
	ui.bind_player(player)
	Game.apply_fov()
	Game.start_run()
	if not _args.has("nomonsters"):
		_spawn_entities()
	Game.power_changed.connect(_on_power, CONNECT_ONE_SHOT)
	level.start_ambience()
	ui.show_game()
	_opening()


## Generate, validate, and on failure regenerate at seed+1.
func _generate_level() -> void:
	for attempt in 25:
		level = Level.new()
		level.name = "Level"
		world.add_child(level)
		level.generate(Game.seed_value, Game.puzzle_seed)
		var why := _validate_level()
		if why == "":
			return
		push_warning("seed %d rejected (%s), regenerating" % [Game.seed_value, why])
		world.remove_child(level)
		level.free()
		Game.seed_value += 1
		if Game.puzzle_seed >= 0:
			Game.puzzle_seed += 1
	push_error("no valid level after 25 seeds")


## "" when the run is solvable: puzzle generated, every clue page non-empty,
## and every page, prop and painted code reachable from spawn.
func _validate_level() -> String:
	var p: Puzzle = level.puzzle
	if not p.ok or p.clues.is_empty():
		return "puzzle"
	for lines in p.note_clues:
		if (lines as Array).is_empty():
			return "empty clue page"
	if not level.generation_ok:
		return "placement"
	var spots: Array[Vector3] = []
	for n in level.get_children():
		if n.get("kind") == "note":
			spots.append((n as Node3D).position)
	if spots.size() < p.note_clues.size() + 1:
		return "missing pages"
	for node in [level.breaker_panel, level.keypad]:
		if node == null:
			return "missing prop"
		spots.append((node as Node3D).position + (node as Node3D).basis.z * 0.3)
	if level.blood_spots.size() < Puzzle.SYMBOL_COUNT:
		return "missing codes"
	for b in level.blood_spots:
		spots.append((b.pos as Vector3) - (b.dir as Vector3) * 0.3)
	for s in spots:
		if not s.is_finite():
			return "unplaced spot"
		var c: Vector2i = level.world_to_cell(s)
		if level.is_wall(c) or level.reach_dist[level.idx(c)] < 0:
			return "unreachable %s" % c
	return ""


func _clear_world() -> void:
	Audio.stop_all_world()
	for e in entities:
		if is_instance_valid(e):
			e.queue_free()
	entities.clear()
	if world:
		world.free()
		world = null
	Game.level = null
	Game.player = null
	if Game.power_changed.is_connected(_on_power):
		Game.power_changed.disconnect(_on_power)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.75, 0.5)
	env.ambient_light_energy = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.0
	env.ssao_power = 1.6
	env.ssil_enabled = false  # too costly; bounce faked by warm ambient
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.9, 0.85, 0.7)
	env.volumetric_fog_anisotropy = 0.3
	env.volumetric_fog_length = 24.0
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)


func _spawn_entities() -> void:
	var Hollow := load("res://scripts/entities/hollow.gd")
	var Smiler := load("res://scripts/entities/smiler.gd")
	var spawn := level.cell_center(level.spawn_cell)
	var h: Node3D = Hollow.new()
	world.add_child(h)
	h.global_position = level.cell_center(level.random_open_cell(Level.Zone.MAIN, spawn, 38.0))
	entities.append(h)
	for i in 2:
		var s: Node3D = Smiler.new()
		world.add_child(s)
		s.global_position = level.cell_center(level.random_open_cell(Level.Zone.DARK if i == 0 else Level.Zone.EXIT, spawn, 20.0))
		entities.append(s)


func _on_power(_on: bool) -> void:
	# Restoring power wakes the watcher somewhere in the lit halls.
	_wake_watcher()


## Spawns the Watcher once per run: on power-on, or early on a wrong lever.
func _wake_watcher() -> void:
	if _args.has("nomonsters") or world == null or not Game.is_playing():
		return
	if is_instance_valid(_watcher):
		return
	var Watcher := load("res://scripts/entities/watcher.gd")
	_watcher = Watcher.new()
	world.add_child(_watcher)
	_watcher.global_position = level.cell_center(level.random_open_cell(Level.Zone.MAIN, player.global_position, 25.0))
	entities.append(_watcher)


func _opening() -> void:
	ui.hold_black()
	await _warm_up_shaders()
	_apply_dev_args()
	var skip_intro := _intro_played or _args.has("nointro") or _args.has("autosolve") or _args.has("bench") \
		or _args.has("look") or _args.has("goto") or _args.has("entity") or (_args.has("shot") and not _args.has("intro"))
	if not skip_intro:
		_intro_played = true
		ui.pause_enabled = false
		var intro: Node = load("res://scripts/intro.gd").new()
		add_child(intro)
		await intro.play(player, ui)
		intro.queue_free()
		ui.pause_enabled = true
		if _args.has("shot") or not is_instance_valid(player):
			return
	elif _args.has("shot") or _args.has("bench"):
		return
	else:
		ui.fade_from_black(4.0)
		await get_tree().create_timer(3.0, false).timeout
	Game.say("wake")
	await get_tree().create_timer(7.0, false).timeout
	if Game.is_playing():
		Game.say("hello")


## Every material/pipeline gets drawn once behind a black screen so first
## sight of a monster or prop never stalls the frame.
func _warm_up_shaders() -> void:
	var holder := Node3D.new()
	player.camera.add_child(holder)
	holder.position = Vector3(0, -1.2, -2.6)
	for m in ["hollow", "watcher"]:
		var c := Creature.new()
		holder.add_child(c)
		c.build({"mesh": m})
		c.position.x = -0.8 if m == "hollow" else 0.8
	var smiler: Node3D = load("res://scripts/entities/smiler.gd").new()
	smiler.set("frozen", true)
	smiler.process_mode = Node.PROCESS_MODE_DISABLED
	holder.add_child(smiler)
	for n in smiler.get_children():
		if n is AudioStreamPlayer3D:
			n.stop()
	var Pickup := preload("res://scripts/pickup.gd")
	for k in ["note", "battery", "bottle"]:
		var p: Node3D = Pickup.new()
		p.kind = k
		holder.add_child(p)
		p.position = Vector3(randf_range(-0.5, 0.5), 1.0, 0.5)
	var yaw0 := player.rotation.y
	player.flashlight_on = true
	for i in 12:
		player.rotation.y = yaw0 + TAU * i / 12.0
		await get_tree().process_frame
		await get_tree().process_frame
	player.rotation.y = yaw0
	player.flashlight_on = false
	holder.queue_free()

func _on_escape() -> void:
	Audio.stop_all_world()
	ui.show_escape(Game.elapsed_text())


func _to_menu() -> void:
	_clear_world()
	Game.state = Game.State.MENU
	get_tree().paused = false
	ui.show_menu()


func _apply_dev_args() -> void:
	if _args.has("shot"):
		# automated capture: don't steal the user's cursor, ignore real input
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.set_process_unhandled_input(false)
		ui.pause_enabled = false
	if _args.has("bench"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.set_process_unhandled_input(false)
		ui.pause_enabled = false
		_bench(float(_args.bench))
	if _args.has("power"):
		Game.set_power(true)
	if _args.has("blackout"):
		Game.set_blackout(true)
	if _args.has("look"):
		var v: PackedStringArray = _args.look.split(",")
		player.global_position = Vector3(float(v[0]), 0.05, float(v[1]))
		player.rotation.y = deg_to_rad(float(v[2]))
		if v.size() > 3:
			player._pitch = deg_to_rad(float(v[3]))
	if _args.has("flash"):
		player.flashlight_on = true
	if _args.has("entity"):
		await get_tree().physics_frame
		await get_tree().physics_frame
		var dist := float(_args.get("dist", "3"))
		# face the most open direction so the specimen isn't inside a wall
		var space := player.get_world_3d().direct_space_state
		var best_yaw := 0.0
		var best_len := 0.0
		for i in 24:
			var yaw := TAU * i / 24.0
			var dir := Vector3(-sin(yaw), 0, -cos(yaw))
			var from := player.global_position + Vector3(0, 1.0, 0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 12.0, 1))
			var l := 12.0 if hit.is_empty() else from.distance_to(hit.position)
			if l > best_len:
				best_len = l
				best_yaw = yaw
		player.rotation.y = best_yaw
		player._pitch = deg_to_rad(float(_args.get("pitch", "0")))
		var e: Node3D = load("res://scripts/entities/%s.gd" % _args.entity).new()
		e.set("frozen", true)
		world.add_child(e)
		var fwd := Vector3(-sin(best_yaw), 0, -cos(best_yaw))
		e.global_position = player.global_position + fwd * minf(dist, best_len - 0.6)
		e.rotation.y = best_yaw  # creature faces +Z -> toward the player
		entities.append(e)
	if _args.has("goto"):
		await get_tree().physics_frame
		var target := Vector3.ZERO
		var normal := Vector3.ZERO
		match _args.goto:
			"breaker":
				target = level.breaker_panel.global_position
				normal = level.breaker_panel.global_basis.z
			"keypad":
				target = level.keypad.global_position
				normal = level.keypad.global_basis.z
			"blood", "oldblood":
				for b in level.blood_spots:
					if b.fresh == (_args.goto == "blood"):
						target = b.pos
						normal = -(b.dir as Vector3)
						break
			"note":
				player.read_note("intro", Notes.intro())
		if normal != Vector3.ZERO:
			var d := float(_args.get("dist", "0.9"))
			player.global_position = Vector3(target.x, 0.05, target.z) + normal * d
			var to := target - (player.global_position + Vector3(0, Player.EYE_STAND, 0))
			player.rotation.y = atan2(-to.x, -to.z)
			player._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	if _args.has("autosolve"):
		_autosolve()
	if _args.has("shot"):
		ui.skip_fade()
		await get_tree().create_timer(float(_args.get("wait", "4"))).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args.shot)
		print("SHOT_SAVED ", _args.shot)
		get_tree().quit()


## Spin the view for `secs` after a warm-up and print frame-time stats.
func _bench(secs: float) -> void:
	ui.skip_fade()
	await get_tree().create_timer(3.0).timeout  # shader compile / streaming warm-up
	var times: Array[float] = []
	var t := 0.0
	var draws := 0
	var prims := 0
	var cpu_proc := 0.0
	var cpu_phys := 0.0
	while t < secs:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		times.append(dt)
		if t < secs * 0.5:
			_first_worst = maxf(_first_worst, dt)
		else:
			_second_worst = maxf(_second_worst, dt)
		player.rotation.y += dt * 0.7
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		cpu_proc = maxf(cpu_proc, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		cpu_phys = maxf(cpu_phys, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	times.sort()
	var avg := 0.0
	for x in times:
		avg += x
	avg /= times.size()
	var worst := times[int(times.size() * 0.99)]
	print("BENCH_HALVES first_worst_fps=%.1f second_worst_fps=%.1f" % [1.0 / _first_worst, 1.0 / _second_worst])
	print("BENCH scale=%.2f " % Game.render_scale, "avg_fps=%.1f low1_fps=%.1f worst_fps=%.1f frames=%d max_draws=%d max_prims=%d max_cpu_proc_ms=%.1f max_cpu_phys_ms=%.1f" % [1.0 / avg, 1.0 / worst, 1.0 / times[-1], times.size(), draws, prims, cpu_proc, cpu_phys])
	get_tree().quit()


## Dev smoke test: solve the run through the real interaction handlers.
func _autosolve() -> void:
	var notes := 0
	for n in level.get_children():
		if n.get("kind") == "note":
			notes += 1
	print("AUTOSOLVE notes=%d clues=%d code=%s" % [notes, level.puzzle.clues.size(), level.puzzle.code_string()])
	var bp: Node = level.breaker_panel
	for i in Puzzle.N:
		if bp.switches[i] != level.puzzle.bit(level.puzzle.target_mask, i):
			bp._flip(player, i)
	bp._pull_main(player)
	await get_tree().create_timer(1.5).timeout
	print("AUTOSOLVE power_on=%s" % Game.power_on)
	var kp: Node = level.keypad
	for d in "000000":
		kp._press(player, d)
	kp._press(player, "OK")
	print("AUTOSOLVE wrong_code_tries=%d" % kp.tries)
	for d in level.puzzle.code_string():
		kp._press(player, d)
	kp._press(player, "OK")
	await get_tree().create_timer(5.0).timeout
	# walk out through the opened door into the stairwell trigger
	player.global_position = level.exit_door.global_position + Vector3(0, 0.1, -0.8)
	player.rotation.y = PI  # face +Z (out through the door)
	var t := 0.0
	while Game.state == Game.State.PLAYING and t < 6.0:
		Input.action_press("move_forward")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release("move_forward")
	print("AUTOSOLVE escaped=%s state=%d" % [Game.state == Game.State.ESCAPED, Game.state])
	get_tree().quit()
