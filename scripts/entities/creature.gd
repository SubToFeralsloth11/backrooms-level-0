class_name Creature
extends Node3D
## Sculpted creature body (meshes/<name>.crt from tools/sculpt_creatures.py):
## one continuous skinned mesh + teeth, driven by a Skeleton3D with
## procedural gait, breathing, jaw tremor and snapping head twitches.

static var _cache := {}  # name -> {mesh: ArrayMesh, bones: Array}
static var _noise_lo: NoiseTexture3D
static var _noise_hi: NoiseTexture3D

var cfg := {
	"mesh": "hollow",
	"skin": Color(0.55, 0.5, 0.47),
	"wet": 0.55,
	"quad": false,
	"stride": 1.1,
}

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var skin_mat: ShaderMaterial
var phase := 0.0
var speed := 0.0
var _b := {}  # bone name -> idx
var _rng := RandomNumberGenerator.new()
var _twitch_t := 0.0
var _head_target := Vector3.ZERO
var _head := Vector3.ZERO
var _t := 0.0


func build(config: Dictionary) -> void:
	cfg.merge(config, true)
	_rng.randomize()
	var data: Dictionary = _load(cfg.mesh)
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for bone in data.bones:
		var i := skeleton.add_bone(bone.name)
		_b[bone.name] = i
	for bone in data.bones:
		var i: int = _b[bone.name]
		if bone.parent >= 0:
			skeleton.set_bone_parent(i, bone.parent)
		skeleton.set_bone_rest(i, Transform3D(Basis(), bone.local))
	skeleton.reset_bone_poses()
	skin_mat = ShaderMaterial.new()
	skin_mat.shader = load("res://shaders/creature_skin.gdshader")
	var sc: Color = cfg.skin
	skin_mat.set_shader_parameter("base_color", Vector3(sc.r, sc.g, sc.b))
	skin_mat.set_shader_parameter("wetness", cfg.wet)
	skin_mat.set_shader_parameter("seed", _rng.randf() * 10.0)
	skin_mat.set_shader_parameter("noise_lo", noise_texture(false))
	skin_mat.set_shader_parameter("noise_hi", noise_texture(true))
	mesh_instance = _skinned(data.mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, 8.0)
	var lod: Dictionary = _load(cfg.mesh + "_lod")
	if not lod.is_empty():
		# coarse proxy casts the shadow and stands in beyond 8 m
		_skinned(lod.mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, 0.0, 0.0)
		_skinned(lod.mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 8.0, 0.0)


func _skinned(mesh: Mesh, shadows: int, range_begin: float, range_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = skin_mat
	mi.cast_shadow = shadows
	mi.visibility_range_begin = range_begin
	mi.visibility_range_end = range_end
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skeleton.create_skin_from_rest_transforms()
	return mi


static func noise_texture(hi: bool) -> NoiseTexture3D:
	if hi and _noise_hi:
		return _noise_hi
	if not hi and _noise_lo:
		return _noise_lo
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_PERLIN
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3 if hi else 5
	fn.frequency = 0.12 if hi else 0.05
	var t := NoiseTexture3D.new()
	t.width = 64
	t.height = 64
	t.depth = 64
	t.seamless = true
	t.normalize = true
	t.noise = fn
	if hi:
		_noise_hi = t
	else:
		_noise_lo = t
	return t


static func _load(mesh_name: String) -> Dictionary:
	if _cache.has(mesh_name):
		return _cache[mesh_name]
	var f := FileAccess.open("res://meshes/%s.crt" % mesh_name, FileAccess.READ)
	if f == null:
		push_error("missing creature mesh " + mesh_name)
		return {}
	assert(f.get_buffer(4).get_string_from_ascii() == "CRT2")
	var bones := []
	var nb := f.get_32()
	for i in nb:
		var ln := f.get_8()
		var bname := f.get_buffer(ln).get_string_from_utf8()
		var parent := f.get_32()
		if parent >= 0x80000000:
			parent -= 0x100000000
		var local := Vector3(f.get_float(), f.get_float(), f.get_float())
		bones.append({"name": bname, "parent": parent, "local": local})
	# Mesh positions are model-space; skinning needs rest globals, which
	# create_skin_from_rest_transforms derives from the local offsets above.
	var mesh := ArrayMesh.new()
	var ns := f.get_32()
	for s in ns:
		var nv := f.get_32()
		var ni := f.get_32()
		var pos := f.get_buffer(nv * 12).to_float32_array()
		var nrm := f.get_buffer(nv * 12).to_float32_array()
		var reg := f.get_buffer(nv * 4).to_float32_array()
		var bidx := f.get_buffer(nv * 16).to_int32_array()
		var bw := f.get_buffer(nv * 16).to_float32_array()
		var idx := f.get_buffer(ni * 4).to_int32_array()
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		verts.resize(nv)
		norms.resize(nv)
		uv.resize(nv)
		uv2.resize(nv)
		for v in nv:
			var k := v * 3
			verts[v] = Vector3(pos[k], pos[k + 1], pos[k + 2])
			norms[v] = Vector3(nrm[k], nrm[k + 1], nrm[k + 2])
			# rest-pose position (stable texturing under skinning) + material region
			uv[v] = Vector2(pos[k], pos[k + 1])
			uv2[v] = Vector2(pos[k + 2], reg[v])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_BONES] = bidx
		arr[Mesh.ARRAY_WEIGHTS] = bw
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var out := {"mesh": mesh, "bones": bones}
	_cache[mesh_name] = out
	return out


func _rot(bone: String, e: Vector3) -> void:
	if _b.has(bone):
		skeleton.set_bone_pose_rotation(_b[bone], Quaternion.from_euler(e))


## Advance procedural animation. spd in m/s; agitation 0..1 (hunting/excited).
func animate(delta: float, spd: float, agitation := 0.0) -> void:
	_t += delta
	speed = spd
	phase += delta * (spd / float(cfg.stride)) * PI
	var w := clampf(spd / 2.0, 0.0, 1.0)
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		# Unnatural: long stillness, then a sudden snap to a new angle.
		_twitch_t = _rng.randf_range(0.12, 2.4) * (1.0 - agitation * 0.75)
		_head_target = Vector3(_rng.randf_range(-0.3, 0.35), _rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.55, 0.55)) * (0.35 + agitation * 0.8)
	_head = _head.lerp(_head_target, 1.0 - exp(-(30.0 + agitation * 30.0) * delta))
	_rot("head", _head)
	# jaw: slow gape with a fine tremor
	_rot("jaw", Vector3(sin(_t * 0.7) * 0.06 + sin(_t * 31.0) * 0.012 * (0.3 + agitation), 0, 0))
	var breath := sin(_t * (1.1 + agitation * 1.5)) * 0.025
	if cfg.quad:
		_animate_quad(w, breath)
	else:
		_animate_biped(w, breath)


func _animate_biped(w: float, breath: float) -> void:
	var s := sin(phase)
	var c := cos(phase)
	for side in [1.0, -1.0]:
		var nm := "l" if side > 0.0 else "r"
		var ph: float = s * side
		var knee := maxf(0.0, -c * side) * 1.15 * w + 0.06
		_rot("hip_" + nm, Vector3(-ph * 0.5 * w - knee * 0.25, 0, 0))
		_rot("knee_" + nm, Vector3(knee, 0, 0))
		_rot("ankle_" + nm, Vector3(-knee * 0.35 + ph * 0.15 * w, 0, 0))
		# long arms hang dead and swing late, fingers twitch
		_rot("shoulder_" + nm, Vector3(ph * 0.3 * w + breath, 0, side * 0.04))
		_rot("elbow_" + nm, Vector3(-0.12 - absf(ph) * 0.25 * w, 0, 0))
		_rot("fingers_" + nm, Vector3(-0.1 + sin(_t * 3.0 + side) * 0.08, 0, 0))
	_rot("hips", Vector3(0, s * 0.1 * w, c * 0.03 * w))
	_rot("spine", Vector3(breath * 0.5, -s * 0.06 * w, 0))
	_rot("chest", Vector3(breath, -s * 0.06 * w, c * 0.04 * w))
	if _b.has("hips"):
		skeleton.set_bone_pose_position(_b.hips, skeleton.get_bone_rest(_b.hips).origin + Vector3(0, -absf(c) * 0.05 * w, 0))


func _animate_quad(w: float, breath: float) -> void:
	var s := sin(phase)
	var c := cos(phase)
	for side in [1.0, -1.0]:
		var nm := "l" if side > 0.0 else "r"
		# diagonal gait: front-left pairs with back-right
		var front: float = s * side
		var back: float = -s * side
		var lift_f := maxf(0.0, c * side) * w
		var lift_b := maxf(0.0, -c * side) * w
		_rot("shoulder_" + nm, Vector3(0, -front * 0.45 * w * side, lift_f * 0.35 * side))
		_rot("elbow_" + nm, Vector3(-lift_f * 0.4, 0, 0))
		_rot("hip_" + nm, Vector3(0, -back * 0.4 * w * side, lift_b * 0.3 * side))
		_rot("knee_" + nm, Vector3(lift_b * 0.4, 0, 0))
		_rot("fingers_" + nm, Vector3(sin(_t * 5.0 + side) * 0.1, 0, 0))
	_rot("spine", Vector3(breath, s * 0.08 * w, 0))
	_rot("chest", Vector3(breath, -s * 0.1 * w, c * 0.05 * w))


func head_global() -> Vector3:
	if _b.has("head"):
		return skeleton.global_transform * skeleton.get_bone_global_pose(_b.head).origin
	return global_position + Vector3(0, 1.5, 0)
