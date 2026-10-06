extends RefCounted
## Runtime shading pass applied once the level exists: tunes the run's
## WorldEnvironment for deep-but-readable darkness and softens the lit/dark
## boundary by dimming fluorescent panels as they approach unpowered zones.

const GRADIENT_CELLS := 14  # panels within this many cells of a dark zone dim progressively


static func apply(level: Level) -> void:
	var env := _find_environment(level.get_parent())
	if env:
		tune(env)
	_soften_zone_edges(level)


static func _find_environment(root: Node) -> Environment:
	if root == null:
		return null
	for n in root.get_children():
		if n is WorldEnvironment:
			return (n as WorldEnvironment).environment
	return null


static func tune(env: Environment) -> void:
	# Faint warm ambient keeps silhouettes readable in a flashlight beam's
	# spill without lifting the dark zones out of black.
	env.ambient_light_color = Color(0.78, 0.68, 0.46)
	env.ambient_light_energy = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 5.0
	# Tight, strong occlusion = grime in corners, under props and along baseboards.
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 2.6
	env.ssao_power = 1.8
	env.ssao_detail = 0.8
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.15  # occlusion still reads under direct panel light
	env.ssao_ao_channel_affect = 0.3
	# Haze: lights bloom a halo in the air and fall off into murk.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.92, 0.86, 0.68)
	env.volumetric_fog_emission = Color(0, 0, 0)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 28.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.1
	env.adjustment_brightness = 0.98


## Panels near the maintenance wing / exit hall run progressively dimmer so the
## light thins out over several metres instead of stopping at a zone line.
static func _soften_zone_edges(level: Level) -> void:
	var dark_cells: Array[Vector2i] = []
	for y in range(0, Level.H, 2):
		for x in range(0, Level.W, 2):
			var c := Vector2i(x, y)
			if level.is_open(c) and level.zone_of(c) != Level.Zone.MAIN:
				dark_cells.append(c)
	for pd in level.panels:
		if pd.zone != Level.Zone.MAIN or pd.kind != "on":
			continue
		var best := 1e9
		var pc: Vector2i = pd.cell
		for c in dark_cells:
			var d := float((c - pc).length_squared())
			if d < best:
				best = d
		var t := clampf(sqrt(best) / GRADIENT_CELLS, 0.0, 1.0)
		if t < 1.0:
			pd.level = lerpf(0.3, 1.0, t * t)
