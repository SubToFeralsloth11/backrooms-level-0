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
	v.add_child(_button("Restart (same level)", retry_pressed))
	v.add_child(_button("Main menu", menu_pressed))
	v.add_child(_spacer(20))
	v.add_child(_label("Mouse sensitivity", 18, Color(0.7, 0.66, 0.55)))
	var s := HSlider.new()
	s.min_value = 0.0006
	s.max_value = 0.006
	s.step = 0.0001
	s.value = Game.mouse_sensitivity
	s.custom_minimum_size = Vector2(320, 24)
	s.value_changed.connect(func(x): Game.mouse_sensitivity = x)
	v.add_child(s)
	var cb := CheckBox.new()
	cb.text = "Subtitles"
	cb.button_pressed = Game.subtitles_enabled
	if _font:
		cb.add_theme_font_override("font", _font)
	cb.toggled.connect(func(on): Game.subtitles_enabled = on)
	v.add_child(cb)
	return root


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
	Game.state = Game.State.PLAYING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func show_death() -> void:
	_set_hud(false)
	_post_mat.set_shader_parameter("fade_color", Vector3.ZERO)
	_fade_target = 1.0
	_fade_speed = 0.6
	await get_tree().create_timer(2.6).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var s: Control = _screens.death
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


## Nearby entities raise sensor noise/fringe a little: the camera "feels" them.
func _fear() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var f := 0.0
	for e in get_tree().get_nodes_in_group("entity"):
		var d: float = (e as Node3D).global_position.distance_to(_player.global_position)
		f = maxf(f, 1.0 - clampf((d - 3.0) / 12.0, 0.0, 1.0))
	return f
