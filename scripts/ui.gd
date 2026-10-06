class_name UI
extends CanvasLayer
## Diegetic-first UI: no bars. Subtitles, a faint focus dot + interact hint,
## post-process overlay, and the menu / pause / death / escape screens.

signal start_pressed
signal retry_pressed
signal new_level_pressed
signal quit_pressed
signal menu_pressed

var _post: ColorRect
var _post_mat: ShaderMaterial
var _subtitle: Label
var _subtitle_bg: PanelContainer
var _sub_timer := 0.0
var _prompt: Label
var _dot: ColorRect
var _hint: Label
var _screens := {}
var _font: Font
var _fade := 0.0
var _fade_target := 0.0
var _fade_speed := 1.0
var _player: Player
## Esc/P toggles the pause menu (handled here: UI keeps processing while paused).
var pause_enabled := true
var _fear_val := 0.0
var _blood_t := 0.0
var _seen_blood := {}  # blood_spots index -> true
var _codes: Array = []  # {symbol, digit, fresh} in the order seen
var _fresh_seen := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	if ResourceLoader.exists("res://fonts/ui.ttf"):
		_font = load("res://fonts/ui.ttf")
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/camcorder.gdshader")
	_post.material = _post_mat
	add_child(_post)

	_dot = ColorRect.new()
	_dot.color = Color(1, 1, 1, 0.22)
	_dot.size = Vector2(3, 3)
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.position = Vector2(-1.5, -1.5)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dot)

	_prompt = _label("", 17, Color(1, 1, 1, 0.55))
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-200, 26)
	_prompt.size = Vector2(400, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

	_hint = _label("", 15, Color(1, 1, 1, 0.45))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-300, -44)
	_hint.size = Vector2(600, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	_subtitle_bg = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	_subtitle_bg.add_theme_stylebox_override("panel", sb)
	_subtitle_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle_bg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_subtitle_bg.position.y = -110
	_subtitle_bg.visible = false
	_subtitle = _label("", 24, Color(1, 1, 0.92))
	_subtitle_bg.add_child(_subtitle)
	add_child(_subtitle_bg)
	Game.subtitle.connect(_on_subtitle)

	_screens.menu = _build_menu()
	_screens.pause = _build_pause()
	_screens.death = _build_end("You were found.", [["Try again", retry_pressed], ["New level", new_level_pressed], ["Main menu", menu_pressed]])
	_screens.escape = _build_end("You escaped Level 0.", [["Go deeper (new level)", new_level_pressed], ["Main menu", menu_pressed]])


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.6))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		Audio.play_2d("ui_click", -6.0, 0.0, "UI")
		sig.emit())
	return b


func _screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	add_child(root)
	return root


func _column(root: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(120, 180)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)
	return v


func _build_menu() -> Control:
	var root := _screen()
	(root.get_child(0) as ColorRect).color = Color(0.02, 0.018, 0.01, 1)
	var v := _column(root)
	v.add_child(_label("LEVEL 0", 72, Color(0.86, 0.78, 0.45)))
	v.add_child(_label("You noclipped out of reality.", 22, Color(0.7, 0.66, 0.55)))
	v.add_child(_spacer(40))
	v.add_child(_button("Enter", start_pressed))
	v.add_child(_button("Quit", quit_pressed))
	v.add_child(_spacer(60))
	v.add_child(_label(
		"WASD move   Shift run   Ctrl/C crouch   E / LMB interact\n" +
		"F flashlight   R swap batteries   G / RMB throw bottle\n" +
		"Tab / J journal   Esc pause", 16, Color(0.6, 0.58, 0.5)))
	return root


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _build_pause() -> Control:
	var root := _screen()
	var v := _column(root)
	v.add_child(_label("Paused", 48, Color(0.86, 0.78, 0.45)))
	v.add_child(_spacer(20))
	v.add_child(_plain_button("Resume", resume))
	v.add_child(_button("Restart (same level, new clues)", retry_pressed))
	v.add_child(_button("Main menu", menu_pressed))
	v.add_child(_spacer(20))
	v.add_child(_label("Mouse sensitivity", 18, Color(0.7, 0.66, 0.55)))
	v.add_child(_slider(0.0006, 0.006, 0.0001, Game.mouse_sensitivity, func(x): Game.mouse_sensitivity = x))
	v.add_child(_label("Master volume", 18, Color(0.7, 0.66, 0.55)))
	v.add_child(_slider(0.0, 1.0, 0.01, Game.master_volume, func(x):
		Game.master_volume = x
		Game.apply_volume()))
	v.add_child(_label("Field of view", 18, Color(0.7, 0.66, 0.55)))
	v.add_child(_slider(60.0, 100.0, 1.0, Game.fov, func(x):
		Game.fov = x
		Game.apply_fov()))
	var cb := CheckBox.new()
	cb.text = "Subtitles"
	cb.button_pressed = Game.subtitles_enabled
	if _font:
		cb.add_theme_font_override("font", _font)
	cb.toggled.connect(func(on):
		Game.subtitles_enabled = on
		Game.save_settings())
	v.add_child(cb)
	return root


## Settings slider; saved to user://settings.cfg when the drag ends.
func _slider(lo: float, hi: float, step: float, value: float, apply: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(320, 24)
	s.value_changed.connect(apply)
	s.drag_ended.connect(func(_changed): Game.save_settings())
	return s


func _plain_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	if _font:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.6))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


func _build_end(title: String, buttons: Array) -> Control:
	var root := _screen()
	(root.get_child(0) as ColorRect).color = Color(0, 0, 0, 0)
	var v := _column(root)
	var t := _label(title, 52, Color(0.86, 0.78, 0.45))
	t.name = "Title"
	v.add_child(t)
	var info := _label("", 20, Color(0.7, 0.66, 0.55))
	info.name = "Info"
	v.add_child(info)
	v.add_child(_spacer(30))
	for b in buttons:
		v.add_child(_button(b[0], b[1]))
	return root


func _hide_screens() -> void:
	for s in _screens.values():
		s.visible = false


func show_menu() -> void:
	_hide_screens()
	_screens.menu.visible = true
	_set_hud(false)
	_fade = 0.0
	_fade_target = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_game() -> void:
	_hide_screens()
	_set_hud(true)


func show_pause() -> void:
	_screens.pause.visible = true


func resume() -> void:
	_screens.pause.visible = false
	Game.save_settings()
	Game.state = Game.State.PLAYING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not pause_enabled or not event.is_action_pressed("pause"):
		return
	if Game.state == Game.State.PLAYING:
		Game.state = Game.State.PAUSED
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		show_pause()
		get_viewport().set_input_as_handled()
	elif Game.state == Game.State.PAUSED:
		resume()
		get_viewport().set_input_as_handled()


func show_death(cause := "") -> void:
	_set_hud(false)
	_post_mat.set_shader_parameter("fade_color", Vector3.ZERO)
	_fade_target = 1.0
	_fade_speed = 0.6
	await get_tree().create_timer(2.6).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var s: Control = _screens.death
	s.find_child("Title", true, false).text = Game.death_line(cause)
	s.find_child("Info", true, false).text = "Time survived  " + Game.elapsed_text()
	s.visible = true


func show_escape(time: String) -> void:
	_set_hud(false)
	_post_mat.set_shader_parameter("fade_color", Vector3(1, 0.97, 0.9))
	_fade_target = 1.0
	_fade_speed = 0.35
	await get_tree().create_timer(3.5).timeout
	_post_mat.set_shader_parameter("fade_color", Vector3.ZERO)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var s: Control = _screens.escape
	s.find_child("Info", true, false).text = "Time  " + time + "\n\nThe stairwell goes up. And up. And up."
	s.visible = true


func fade_from_black(t: float) -> void:
	_post_mat.set_shader_parameter("fade_color", Vector3.ZERO)
	_fade = 1.0
	_fade_target = 0.0
	_fade_speed = 1.0 / t


func hold_black() -> void:
	_post_mat.set_shader_parameter("fade_color", Vector3.ZERO)
	_fade = 1.0
	_fade_target = 1.0
	_fade_speed = 1.0


func skip_fade() -> void:
	_fade = 0.0
	_fade_target = 0.0


func _set_hud(on: bool) -> void:
	_dot.visible = on
	_prompt.visible = on
	_hint.visible = on
	if not on:
		_subtitle_bg.visible = false


func bind_player(p: Player) -> void:
	_player = p
	_seen_blood.clear()
	_codes.clear()
	_fresh_seen = 0
	_fear_val = 0.0
	p.prompt_changed.connect(func(t): _prompt.text = ("[E]  " + t) if t != "" else "")
	p.reading_changed.connect(func(on): _hint.text = "E  put away      Tab  next page" if on else "")


func _on_subtitle(text: String, dur: float) -> void:
	_subtitle.text = text
	_subtitle_bg.visible = true
	_sub_timer = dur


func _process(delta: float) -> void:
	if _sub_timer > 0.0:
		_sub_timer -= delta
		if _sub_timer <= 0.0:
			_subtitle_bg.visible = false
	_fade = move_toward(_fade, _fade_target, delta * _fade_speed)
	_post_mat.set_shader_parameter("fade", _fade)
	_post_mat.set_shader_parameter("fear", _fear())
	_subtitle_bg.position.x = (get_viewport().get_visible_rect().size.x - _subtitle_bg.size.x) * 0.5
	if Game.is_playing() and _player != null and is_instance_valid(_player):
		_blood_t -= delta
		if _blood_t <= 0.0:
			_blood_t = 0.25
			_check_blood()


## Entities the player can actually see (line of sight, not hidden) raise
## sensor noise/fringe: the camera "feels" them. No radar through walls.
func _fear() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	if not Game.is_playing():
		return _fear_val
	var f := 0.0
	var eye := _player.camera.global_position
	var space := _player.get_world_3d().direct_space_state
	var lv: Level = Game.level
	for node in get_tree().get_nodes_in_group("entity"):
		var e := node as Node3D
		if not e.is_visible_in_tree() or e.get("_hidden") == true:
			continue
		var target := e.global_position + Vector3(0, 1.2, 0)
		var d := eye.distance_to(target)
		if d > 15.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, target, 1)
		var ex: Array[RID] = [_player.get_rid()]
		if e is CollisionObject3D:
			ex.append((e as CollisionObject3D).get_rid())
		q.exclude = ex
		if not space.intersect_ray(q).is_empty():
			continue
		f = maxf(f, 1.0 - clampf((d - 3.0) / 12.0, 0.0, 1.0))
		if d < 8.0 and lv and lv.is_dark(lv.world_to_cell(_player.global_position)) \
				and e.get_script().resource_path.ends_with("smiler.gd"):
			Game.smiler_near_dark()
	_fear_val = f
	return f


## Logs every painted symbol/number the player has clearly looked at (close,
## near the centre of view, lit, unobstructed) to a journal page.
func _check_blood() -> void:
	var lv: Level = Game.level
	if lv == null:
		return
	var cam := _player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	for i in lv.blood_spots.size():
		if _seen_blood.has(i):
			continue
		var b: Dictionary = lv.blood_spots[i]
		var p: Vector3 = b.pos
		var to := p - eye
		var d := to.length()
		if d > 5.0 or d < 0.01:
			continue
		var facing := fwd.dot(to / d)
		if facing < 0.85:
			continue
		var lit := not lv.is_dark(lv.world_to_cell(p - (b.dir as Vector3) * 0.3)) \
				or (_player.flashlight_on and facing > 0.93)
		if not lit:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, p - (b.dir as Vector3) * 0.05, 1)
		q.exclude = [_player.get_rid()]
		if not _player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		_seen_blood[i] = true
		_codes.append({"symbol": b.symbol, "digit": b.digit, "fresh": b.fresh})
		_update_codes_page()
		if b.fresh:
			_fresh_seen += 1
			Game.say("blood" if _fresh_seen == 1 else "blood_wet")


func _update_codes_page() -> void:
	var text := Notes.codes(_codes)
	Audio.play_2d("paper_rustle", -16.0, 0.08)
	for e in _player.journal:
		if e.id == "codes":
			e.text = text
			return
	_player.journal.append({"id": "codes", "text": text})
