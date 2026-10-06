extends Interactable
## World pickup: "note" (journal page), "battery" (AA pair), "bottle" (almond water, throwable).

var kind := "note"
var note_id := ""
var note_text := ""


func _ready() -> void:
	match kind:
		"note":
			prompt = "Pick up page"
			_build_note()
		"battery":
			prompt = "Take batteries"
			_build_battery()
		"bottle":
			prompt = "Take bottle"
			_build_bottle()
	action = _take


func _take(player: Node) -> void:
	match kind:
		"note":
			Audio.play_2d("paper_pickup", -4.0, 0.05)
			player.read_note(note_id, note_text)
		"battery":
			Audio.play_2d("item_pickup", -6.0, 0.05)
			player.spare_batteries += 1
		"bottle":
			if player.bottles >= player.MAX_BOTTLES:
				return
			Audio.play_2d("item_pickup", -6.0, 0.08)
			player.bottles += 1
	queue_free()


static func paper_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.83, 0.74)
	m.roughness = 0.92
	var n := NoiseTexture2D.new()
	n.width = 256
	n.height = 256
	n.as_normal_map = true
	n.bump_strength = 1.6
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	n.noise = fn
	m.normal_enabled = true
	m.normal_texture = n
	m.normal_scale = 0.6
	return m


func _build_note() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.21, 0.297)
	pm.subdivide_width = 4
	pm.subdivide_depth = 6
	pm.material = paper_material()
	mi.mesh = pm
	add_child(mi)
	# faint ink lines so the page reads as written-on from a distance
	var lbl := Label3D.new()
	lbl.text = note_text.substr(0, 220)
	if ResourceLoader.exists("res://fonts/journal.ttf"):
		lbl.font = load("res://fonts/journal.ttf")
	lbl.font_size = 32
	lbl.pixel_size = 0.0006
	lbl.width = 300
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.modulate = Color(0.12, 0.1, 0.2, 0.75)
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.rotation.x = -PI / 2
	lbl.position = Vector3(0, 0.002, 0)
	add_child(lbl)
	add_box(Vector3(0.3, 0.08, 0.36))


func _build_battery() -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.08, 0.08, 0.08)
	body.roughness = 0.35
	body.metallic = 0.3
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.72, 0.45, 0.12)
	cap.metallic = 0.9
	cap.roughness = 0.3
	for i in 2:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.007
		cyl.bottom_radius = 0.007
		cyl.height = 0.05
		cyl.radial_segments = 16
		cyl.material = body
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.rotation = Vector3(0, i * 0.3, PI / 2)
		mi.position = Vector3(0, 0.007, i * 0.016)
		add_child(mi)
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0068
		tip.bottom_radius = 0.0068
		tip.height = 0.012
		tip.material = cap
		var ti := MeshInstance3D.new()
		ti.mesh = tip
		ti.position = Vector3(0, -0.019, 0)
		mi.add_child(ti)
	add_box(Vector3(0.2, 0.1, 0.2), Vector3(0, 0.03, 0))


static func bottle_mesh() -> Node3D:
	var root := Node3D.new()
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.92, 0.9, 0.82, 0.35)
	plastic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plastic.roughness = 0.08
	plastic.metallic_specular = 0.9
	plastic.refraction_enabled = false
	var liquid := StandardMaterial3D.new()
	liquid.albedo_color = Color(0.93, 0.88, 0.74)
	liquid.roughness = 0.2
	var label := StandardMaterial3D.new()
	label.albedo_color = Color(0.85, 0.82, 0.7)
	label.roughness = 0.7
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.2, 0.35, 0.6)
	cap.roughness = 0.5
	var parts := [
		[0.032, 0.032, 0.17, 0.085, plastic],
		[0.03, 0.03, 0.12, 0.065, liquid],
		[0.0325, 0.0325, 0.07, 0.09, label],
		[0.012, 0.032, 0.045, 0.192, plastic],
		[0.0125, 0.0125, 0.018, 0.222, cap],
	]
	for p in parts:
		var c := CylinderMesh.new()
		c.top_radius = p[0]
		c.bottom_radius = p[1]
		c.height = p[2]
		c.radial_segments = 20
		c.material = p[4]
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.position.y = p[3]
		root.add_child(mi)
	return root


func _build_bottle() -> void:
	var b := bottle_mesh()
	add_child(b)
	add_box(Vector3(0.18, 0.28, 0.18), Vector3(0, 0.12, 0))
