extends Node3D
## ИИ-Музей: процедурный 3D-музей, управление ПК/телефон, ИИ-гид, создание залов и стеллажей.
const ImagesT := preload("res://scripts/images.gd")
const WikiT := preload("res://scripts/wiki.gd")
const AiT := preload("res://scripts/ai.gd")

const D := 14.0      # глубина зала
const H := 5.0       # высота
const SHELF_W := 4.2
const SPEED := 3.6
var state: Dictionary
var settings := {"provider": "offline", "image_mode": "embed", "api_url": "https://api.x.ai/v1", "api_key": "", "api_model": "grok-3-mini", "sens": 0.25, "lights": true, "joy_size": 1.0}

var images: Node; var wiki: Node; var ai: Node
var world: Node3D
var player: CharacterBody3D; var cam: Camera3D; var ray: RayCast3D
var yaw := 0.0; var pitch := 0.0
var hall_x: Array = []   # [x0, w] по залам
var tex_targets := {}    # url -> [MeshInstance3D]
var focus := {}          # {"ex":Dictionary,"hall":String,"shelf":String}
var cur_hall := ""
var mats := {}
# сенсор
var joy_id := -1; var joy_c := Vector2.ZERO; var joy_v := Vector2.ZERO
var look_id := -1; var look_start := Vector2.ZERO; var look_t := 0
var is_touch := false
# UI
var ui: CanvasLayer; var hint: Label; var cross: Label; var card: PanelContainer; var chat: PanelContainer
var chat_log: RichTextLabel; var chat_in: LineEdit; var chat_imgs: HFlowContainer; var chat_ctx: Label
var card_img: TextureRect; var card_text: RichTextLabel; var card_ex := {}
var halls_dlg: AcceptDialog; var set_dlg: AcceptDialog; var joy_ui: Control; var toast_l: Label
var busy_ai := false
var urgent_halls: Array = []

func _ready() -> void:
	is_touch = DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	images = ImagesT.new(); add_child(images); images.loaded.connect(_on_tex)
	wiki = WikiT.new(); add_child(wiki)
	ai = AiT.new(); ai.wiki = wiki; add_child(ai)
	ai.reply.connect(_on_ai_reply); ai.status.connect(func(t): toast(t))
	_load_settings()
	state = MuseumData.load_state()
	_env(); _make_player(); _build_ui()
	rebuild()
	_teleport(0)
	var web_test: bool = OS.has_feature("web") and str(JavaScriptBridge.eval("location.search")).contains("selftest")
	if "--selftest-walk" in OS.get_cmdline_user_args() or web_test: _selftest_walk()

# ---------- мир ----------
func _env() -> void:
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.05, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.85, 0.8, 0.75); e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.glow_enabled = true; e.glow_intensity = 0.4
	we.environment = e; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-60, 30, 0); sun.light_energy = 0.35; add_child(sun)
	mats["floor"] = _mat(Color(0.33, 0.22, 0.15), 0.35, true)
	mats["ceil"] = _mat(Color(0.93, 0.92, 0.9), 0.9)
	mats["wood"] = _mat(Color(0.25, 0.16, 0.1), 0.5)
	mats["board"] = _mat(Color(0.16, 0.17, 0.2), 0.8)
	mats["gold"] = _mat(Color(0.8, 0.62, 0.25), 0.3); mats["gold"].metallic = 0.8
	mats["ph"] = _mat(Color(0.35, 0.35, 0.38), 0.9)

func _mat(c: Color, r: float, noise := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = r
	if noise:
		var n := NoiseTexture2D.new(); n.width = 256; n.height = 256; n.seamless = true
		var fn := FastNoiseLite.new(); fn.frequency = 0.02; fn.fractal_octaves = 3; n.noise = fn
		var gr := Gradient.new(); gr.set_color(0, Color(0.55, 0.38, 0.25)); gr.set_color(1, Color(0.85, 0.65, 0.45)); n.color_ramp = gr
		m.albedo_texture = n; m.uv1_scale = Vector3(6, 6, 6)
	return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; mi.material_override = m; mi.position = pos
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
		sb.add_child(cs); mi.add_child(sb)
	return mi

func hall_width(h: Dictionary) -> float:
	var per_side := ceili(h["shelves"].size() / 2.0)
	return max(14.0, per_side * (SHELF_W + 0.5) + 3.0)

func rebuild() -> void:
	if world: world.queue_free()
	world = Node3D.new(); add_child(world)
	tex_targets.clear(); hall_x.clear()
	var x := 0.0
	var halls: Array = state["halls"]
	for i in halls.size():
		var h: Dictionary = halls[i]
		var w := hall_width(h)
		hall_x.append([x, w])
		_build_hall(h, i, x, w, i == 0, i == halls.size() - 1)
		x += w
	if halls.is_empty():
		hall_x.append([0.0, 14.0]); _build_hall({"name": "Пустой музей — попросите ИИ создать зал", "shelves": []}, 0, 0, 14, true, true)

func _build_hall(h: Dictionary, idx: int, x0: float, w: float, first: bool, last: bool) -> void:
	var n := Node3D.new(); n.name = "Hall%d" % idx; world.add_child(n)
	var hue := fmod(idx * 0.13, 1.0)
	var wall := _mat(Color.from_hsv(hue, 0.18, 0.78), 0.85)
	var cx := x0 + w / 2.0
	_box(n, Vector3(cx, -0.1, 0), Vector3(w, 0.2, D), mats["floor"])
	_box(n, Vector3(cx, H + 0.1, 0), Vector3(w, 0.2, D), mats["ceil"], false)
	_box(n, Vector3(cx, H / 2, -D / 2), Vector3(w, H, 0.2), wall)
	_box(n, Vector3(cx, H / 2, D / 2), Vector3(w, H, 0.2), wall)
	# торцевые стены с проёмом 3 м
	for side in [0, 1]:
		var xx := x0 if side == 0 else x0 + w
		var closed: bool = (side == 0 and first) or (side == 1 and last)
		if closed: _box(n, Vector3(xx, H / 2, 0), Vector3(0.2, H, D), wall)
		elif side == 0:
			_box(n, Vector3(xx, H / 2, -(D / 2 + 1.5) / 2 - 0.0), Vector3(0.3, H, D / 2 - 1.5), wall)
			_box(n, Vector3(xx, H / 2, (D / 2 + 1.5) / 2), Vector3(0.3, H, D / 2 - 1.5), wall)
			_box(n, Vector3(xx, H - 0.6, 0), Vector3(0.3, 1.2, 3.0), wall, false)
	# плинтус-подсветка
	var lbl := Label3D.new(); lbl.text = h["name"]; lbl.font_size = 96; lbl.pixel_size = 0.006; lbl.outline_size = 12
	lbl.position = Vector3(cx, H - 0.7, 0); lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y; lbl.modulate = Color(1, 0.95, 0.85); n.add_child(lbl)
	for k in 2:
		var ol := OmniLight3D.new(); ol.position = Vector3(x0 + w * (0.3 + 0.4 * k), H - 0.5, 0); ol.omni_range = max(w, D); ol.light_energy = 0.9; ol.light_color = Color(1, 0.94, 0.85); n.add_child(ol)
	var shelves: Array = h["shelves"]
	var per_side := ceili(shelves.size() / 2.0)
	var span := per_side * (SHELF_W + 0.5)
	for si in shelves.size():
		var row: int = si % 2; var col: int = si / 2
		var sx := cx - span / 2 + (SHELF_W + 0.5) * (col + 0.5)
		var sz := -D / 2 + 1.2 if row == 0 else D / 2 - 1.2
		_build_shelf(n, shelves[si], h["name"], Vector3(sx, 0, sz), 0.0 if row == 0 else PI)

func _build_shelf(parent: Node3D, s: Dictionary, hall: String, pos: Vector3, rot: float) -> void:
	var n := Node3D.new(); n.position = pos; n.rotation.y = rot; parent.add_child(n)
	_box(n, Vector3(0, 0.15, 0), Vector3(SHELF_W, 0.3, 0.7), mats["wood"])
	_box(n, Vector3(0, 1.6, -0.25), Vector3(SHELF_W, 2.6, 0.1), mats["board"])
	_box(n, Vector3(0, 2.95, -0.2), Vector3(SHELF_W + 0.1, 0.12, 0.25), mats["wood"], false)
	var t := Label3D.new(); t.text = s["name"]; t.font_size = 56; t.pixel_size = 0.005; t.outline_size = 8; t.position = Vector3(0, 3.2, -0.2); n.add_child(t)
	if settings.get("lights", true):
		var sp := OmniLight3D.new(); sp.position = Vector3(0, 2.7, 0.9); sp.omni_range = 3.2; sp.light_energy = 1.1; sp.light_color = Color(1, 0.92, 0.8); n.add_child(sp)
	var ex: Array = s["exhibits"]
	for i in min(ex.size(), MuseumData.MAX_PER_SHELF):
		var c: int = i % 3; var r: int = i / 3
		_build_exhibit(n, ex[i], Vector3(-1.4 + 1.4 * c, 2.25 - 1.25 * r, -0.18), hall, s["name"])

func _build_exhibit(parent: Node3D, e: Dictionary, pos: Vector3, hall: String, shelf: String) -> void:
	var fr := _box(parent, pos + Vector3(0, 0, -0.01), Vector3(1.22, 0.92, 0.04), mats["gold"], false)
	var mi := MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(1.1, 0.82); mi.mesh = q
	mi.position = pos + Vector3(0, 0, 0.02); mi.material_override = mats["ph"]; parent.add_child(mi)
	mi.set_meta("frame", fr)
	var sb := StaticBody3D.new(); sb.collision_layer = 2; sb.collision_mask = 0
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(1.2, 1.0, 0.1); cs.shape = sh; sb.add_child(cs); mi.add_child(sb)
	sb.set_meta("ex", e); sb.set_meta("hall", hall); sb.set_meta("shelf", shelf)
	var lb := Label3D.new(); lb.text = String(e.get("title", "")).left(40); lb.font_size = 28; lb.pixel_size = 0.0045; lb.outline_size = 6
	lb.position = pos + Vector3(0, -0.53, 0.03); lb.width = 260; lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parent.add_child(lb)
	var url: String = e.get("img", "")
	if url != "":
		if not tex_targets.has(url): tex_targets[url] = []
		tex_targets[url].append(mi)
		images.request(url, hall in urgent_halls)

func _on_tex(url: String, tex: Texture2D) -> void:
	for mi in tex_targets.get(url, []):
		if not is_instance_valid(mi): continue
		var m := StandardMaterial3D.new(); m.albedo_texture = tex; m.roughness = 0.6
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mi.material_override = m
		var a: float = float(tex.get_width()) / max(1, tex.get_height())
		var sz := Vector2(1.1, 1.1 / a) if a >= 1.34 else Vector2(0.82 * a, 0.82)
		(mi.mesh as QuadMesh).size = sz
		var fr: MeshInstance3D = mi.get_meta("frame")
		(fr.mesh as BoxMesh).size = Vector3(sz.x + 0.08, sz.y + 0.08, 0.04)
	if card.visible and card_ex.get("img", "") == url: card_img.texture = tex

# ---------- игрок ----------
func _make_player() -> void:
	player = CharacterBody3D.new(); add_child(player)
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.7; cs.shape = cap; cs.position.y = 0.85; player.add_child(cs)
	cam = Camera3D.new(); cam.position.y = 1.62; cam.fov = 72; cam.current = true; player.add_child(cam)
	ray = RayCast3D.new(); ray.target_position = Vector3(0, 0, -5.5); ray.collision_mask = 2; ray.collide_with_bodies = true; cam.add_child(ray)

func _teleport(i: int) -> void:
	if i < 0 or i >= hall_x.size(): return
	player.global_position = Vector3(hall_x[i][0] + 2.0, 0.1, 0); yaw = -PI / 2; pitch = 0
	player.velocity = Vector3.ZERO

func _physics_process(dt: float) -> void:
	var inp := Vector2.ZERO
	if not (chat_in and chat_in.has_focus()):
		inp = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
		if Input.is_physical_key_pressed(KEY_A): inp.x -= 1
		if Input.is_physical_key_pressed(KEY_D): inp.x += 1
		if Input.is_physical_key_pressed(KEY_W): inp.y -= 1
		if Input.is_physical_key_pressed(KEY_S): inp.y += 1
	if joy_id >= 0: inp = joy_v
	inp = inp.limit_length(1.0)
	var run := 1.7 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	player.rotation.y = yaw; cam.rotation.x = pitch
	var dir := (player.transform.basis * Vector3(inp.x, 0, inp.y))
	player.velocity.x = dir.x * SPEED * run; player.velocity.z = dir.z * SPEED * run
	player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 9.8 * dt
	player.move_and_slide()
	if player.global_position.y < -5: _teleport(0)
	_update_focus()

func _update_focus() -> void:
	var px := player.global_position.x
	for i in hall_x.size():
		if px >= hall_x[i][0] and px < hall_x[i][0] + hall_x[i][1] and i < state["halls"].size(): cur_hall = state["halls"][i]["name"]
	var nf := {}
	if ray.is_colliding():
		var c = ray.get_collider()
		if c and c.has_meta("ex"): nf = {"ex": c.get_meta("ex"), "hall": c.get_meta("hall"), "shelf": c.get_meta("shelf")}
	if not nf.is_empty(): focus = nf
	elif not focus.is_empty() and player.global_position.distance_to(cam.global_position) > 0 and ray.is_colliding() == false and Engine.get_physics_frames() % 60 == 0:
		pass
	hint.visible = not nf.is_empty()
	if not nf.is_empty():
		hint.text = "«%s» — %s" % [nf["ex"].get("title", ""), "коснитесь, чтобы открыть карточку" if is_touch else "клик / E — карточка, T — спросить ИИ"]
	cross.modulate = Color(1, 0.85, 0.3) if not nf.is_empty() else Color(1, 1, 1, 0.6)
	if chat.visible: chat_ctx.text = "Зал: «%s»%s" % [cur_hall, ("   Экспонат: «%s»" % focus["ex"].get("title", "")) if not focus.is_empty() else ""]

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag: is_touch = true
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(ev.relative * settings["sens"] * 0.01)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not is_touch:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not focus.is_empty() and hint.visible: open_card(focus["ex"])
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE; card.hide()
			KEY_E: if hint.visible: open_card(focus["ex"])
			KEY_T, KEY_ENTER: toggle_chat(true)
			KEY_TAB: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif ev is InputEventScreenTouch:
		var vs := get_viewport().get_visible_rect().size
		if ev.pressed:
			if ev.position.x < vs.x * 0.4 and ev.position.y > vs.y * 0.35 and joy_id < 0:
				joy_id = ev.index; joy_c = ev.position; joy_v = Vector2.ZERO
			elif look_id < 0:
				look_id = ev.index; look_start = ev.position; look_t = Time.get_ticks_msec()
		else:
			if ev.index == joy_id: joy_id = -1; joy_v = Vector2.ZERO
			elif ev.index == look_id:
				look_id = -1
				if ev.position.distance_to(look_start) < 18 and Time.get_ticks_msec() - look_t < 350: _tap(ev.position)
		joy_ui.queue_redraw()
	elif ev is InputEventScreenDrag:
		if ev.index == joy_id:
			joy_v = ((ev.position - joy_c) / (70.0 * settings["joy_size"])).limit_length(1.0); joy_ui.queue_redraw()
		elif ev.index == look_id:
			_look(ev.relative * settings["sens"] * 0.018)

func _look(d: Vector2) -> void:
	yaw -= d.x; pitch = clamp(pitch - d.y, -1.3, 1.3)

func _tap(p: Vector2) -> void:
	var from := cam.project_ray_origin(p); var to := from + cam.project_ray_normal(p) * 7.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r and r["collider"].has_meta("ex"):
		var c = r["collider"]; focus = {"ex": c.get_meta("ex"), "hall": c.get_meta("hall"), "shelf": c.get_meta("shelf")}
		open_card(focus["ex"])

# ---------- UI ----------
func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = text; b.pressed.connect(cb); b.custom_minimum_size = Vector2(0, 44); parent.add_child(b); return b

func _panel(bg := Color(0.07, 0.07, 0.09, 0.92)) -> PanelContainer:
	var p := PanelContainer.new(); var sb := StyleBoxFlat.new(); sb.bg_color = bg; sb.set_corner_radius_all(12); sb.set_content_margin_all(12); p.add_theme_stylebox_override("panel", sb); return p

func _build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	var th := Theme.new(); th.default_font_size = 20
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.theme = th; ui.add_child(root)
	var top := HBoxContainer.new(); top.position = Vector2(12, 10); top.add_theme_constant_override("separation", 8); root.add_child(top)
	_btn(top, "Залы", _show_halls); _btn(top, "ИИ-гид", func(): toggle_chat(not chat.visible)); _btn(top, "Настройки", _show_settings)
	cross = Label.new(); cross.text = "+"; cross.add_theme_font_size_override("font_size", 34); cross.set_anchors_preset(Control.PRESET_CENTER); cross.position -= Vector2(8, 22); cross.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(cross)
	hint = Label.new(); hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); hint.position.y -= 120; hint.grow_horizontal = Control.GROW_DIRECTION_BOTH; hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color.BLACK); hint.add_theme_constant_override("outline_size", 8); hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(hint)
	toast_l = Label.new(); toast_l.set_anchors_preset(Control.PRESET_CENTER_TOP); toast_l.position.y += 70; toast_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_l.add_theme_color_override("font_outline_color", Color.BLACK); toast_l.add_theme_constant_override("outline_size", 8); toast_l.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(toast_l)
	# джойстик
	joy_ui = Control.new(); joy_ui.set_anchors_preset(Control.PRESET_FULL_RECT); joy_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(joy_ui)
	joy_ui.draw.connect(func():
		if not is_touch: return
		var vs := joy_ui.size; var c := joy_c if joy_id >= 0 else Vector2(150, vs.y - 150); var r: float = 70.0 * settings["joy_size"]
		joy_ui.draw_circle(c, r, Color(1, 1, 1, 0.12)); joy_ui.draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.4), 3)
		joy_ui.draw_circle(c + joy_v * r, r * 0.42, Color(1, 1, 1, 0.45)))
	# карточка
	card = _panel(); card.set_anchors_preset(Control.PRESET_RIGHT_WIDE); card.offset_left = -480; card.offset_top = 64; card.offset_bottom = -12; card.offset_right = -12; card.hide(); root.add_child(card)
	var cv := VBoxContainer.new(); card.add_child(cv)
	card_img = TextureRect.new(); card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; card_img.custom_minimum_size = Vector2(0, 260); cv.add_child(card_img)
	card_text = RichTextLabel.new(); card_text.bbcode_enabled = true; card_text.size_flags_vertical = Control.SIZE_EXPAND_FILL; card_text.meta_clicked.connect(func(m): OS.shell_open(str(m))); cv.add_child(card_text)
	var cb := HFlowContainer.new(); cv.add_child(cb)
	_btn(cb, "Спросить ИИ", func(): card.hide(); toggle_chat(true); send_chat("Расскажи историю этого экспоната и покажи похожие изображения"))
	_btn(cb, "Убрать", func():
		MuseumData.remove_exhibit(state, card_ex.get("title", "")); _save(); rebuild(); card.hide())
	_btn(cb, "Закрыть", func(): card.hide())
	# чат
	chat = _panel(); chat.set_anchors_preset(Control.PRESET_LEFT_WIDE); chat.offset_left = 12; chat.offset_top = 64; chat.offset_bottom = -12; chat.offset_right = 560; chat.hide(); root.add_child(chat)
	var v := VBoxContainer.new(); chat.add_child(v)
	chat_ctx = Label.new(); chat_ctx.add_theme_color_override("font_color", Color(1, 0.85, 0.5)); chat_ctx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(chat_ctx)
	chat_log = RichTextLabel.new(); chat_log.bbcode_enabled = true; chat_log.scroll_following = true; chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; chat_log.selection_enabled = true
	chat_log.meta_clicked.connect(func(m): OS.shell_open(str(m))); v.add_child(chat_log)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 130); sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	chat_imgs = HFlowContainer.new(); chat_imgs.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(chat_imgs)
	var hb := HBoxContainer.new(); v.add_child(hb)
	chat_in = LineEdit.new(); chat_in.placeholder_text = "Спросите или скомандуйте: «Сделай зал с импрессионистами»"; chat_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_in.text_submitted.connect(func(t): send_chat(t)); hb.add_child(chat_in)
	_btn(hb, ">", func(): send_chat(chat_in.text)); _btn(hb, "X", func(): toggle_chat(false))
	chat_log.append_text("[color=#aaa]Я ИИ-гид. Спросите про экспонат перед вами («что это за картина?»), про любой экспонат мира, или попросите: «создай стеллаж про древний Египет», «сделай зал с импрессионистами», «найди картинки Моны Лизы».[/color]\n")
	halls_dlg = AcceptDialog.new(); halls_dlg.title = "Залы музея"; halls_dlg.ok_button_text = "Закрыть"; root.add_child(halls_dlg)
	set_dlg = AcceptDialog.new(); set_dlg.title = "Настройки"; set_dlg.ok_button_text = "Готово"; root.add_child(set_dlg)
	set_dlg.confirmed.connect(func(): _save_settings(); rebuild())

func toast(t: String) -> void:
	toast_l.text = t; toast_l.modulate.a = 1.0
	var tw := create_tween(); tw.tween_interval(3.0); tw.tween_property(toast_l, "modulate:a", 0.0, 0.8)

func toggle_chat(on: bool) -> void:
	chat.visible = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not is_touch: chat_in.grab_focus()
	else: chat_in.release_focus()

func open_card(e: Dictionary) -> void:
	card_ex = e; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	card_img.texture = images.mem.get(e.get("img", ""), null)
	var t := "[font_size=26][b]%s[/b][/font_size]\n" % e.get("title", "")
	for kv in [["Автор", "author"], ["Дата", "date"], ["Собрание", "collection"]]:
		if String(e.get(kv[1], "")) != "": t += "[color=#e9c46a]%s:[/color] %s\n" % [kv[0], e[kv[1]]]
	t += "\n" + String(e.get("desc", "")) + "\n\n"
	if e.get("src", "") != "": t += "[url=%s]Источник[/url]   " % e["src"]
	if e.get("img", "") != "": t += "[url=%s]Изображение[/url]" % e["img"]
	t += "\n[color=#888][font_size=14]%s[/font_size][/color]" % e.get("lic", "")
	card_text.text = ""; card_text.append_text(t); card.show()

func _show_halls() -> void:
	for c in halls_dlg.get_children(): if c is ScrollContainer: c.queue_free()
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(420, 420); var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(v)
	for i in state["halls"].size():
		var h: Dictionary = state["halls"][i]; var n := 0
		for s in h["shelves"]: n += s["exhibits"].size()
		var ii: int = i
		_btn(v, "%s  (%d)" % [h["name"], n], func(): _teleport(ii); halls_dlg.hide())
	var l := Label.new(); l.text = "Всего экспонатов: %d" % MuseumData.count_exhibits(state); v.add_child(l)
	halls_dlg.add_child(sc); halls_dlg.popup_centered()

func _show_settings() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in set_dlg.get_children(): if c is ScrollContainer: c.queue_free()
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(520, 480); var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(v)
	var lab := func(t): var l := Label.new(); l.text = t; v.add_child(l)
	lab.call("ИИ-гид:")
	var ob := OptionButton.new(); for nm in AiT.PROVIDER_NAMES: ob.add_item(nm)
	ob.selected = max(0, AiT.PROVIDERS.find(settings["provider"])); ob.item_selected.connect(func(i): settings["provider"] = AiT.PROVIDERS[i]); v.add_child(ob)
	_btn(v, "Войти в веб-чат выбранного ИИ (как в «Наставнике»)", func():
		if not ai.web_supported(): toast("Вход в веб-чат работает в Android-версии. На ПК — API-ключ или офлайн.")
		elif settings["provider"].begins_with("web:"): ai.login(settings["provider"])
		else: toast("Сначала выберите Grok/DeepSeek/GigaChat/Qwen"))
	lab.call("API (запасной вариант): адрес, ключ, модель")
	for k in ["api_url", "api_key", "api_model"]:
		var le := LineEdit.new(); le.text = settings[k]; le.secret = k == "api_key"; le.placeholder_text = k; var kk: String = k
		le.text_changed.connect(func(t): settings[kk] = t); v.add_child(le)
	lab.call("Картинки в ответах ИИ:")
	var im := OptionButton.new(); for nm in ["Встраивать картинки", "Только ссылки", "Авто (до 4 картинок + ссылки)"]: im.add_item(nm)
	var modes := ["embed", "links", "auto"]; im.selected = max(0, modes.find(settings["image_mode"])); im.item_selected.connect(func(i): settings["image_mode"] = modes[i]); v.add_child(im)
	lab.call("Чувствительность обзора:")
	var sl := HSlider.new(); sl.min_value = 0.05; sl.max_value = 1.0; sl.step = 0.01; sl.value = settings["sens"]; sl.value_changed.connect(func(x): settings["sens"] = x); v.add_child(sl)
	lab.call("Размер джойстика:")
	var js := HSlider.new(); js.min_value = 0.6; js.max_value = 1.8; js.step = 0.05; js.value = settings["joy_size"]; js.value_changed.connect(func(x): settings["joy_size"] = x); v.add_child(js)
	var cb := CheckBox.new(); cb.text = "Подсветка стеллажей (выключите на слабом телефоне)"; cb.button_pressed = settings["lights"]; cb.toggled.connect(func(b): settings["lights"] = b); v.add_child(cb)
	_btn(v, "Экспорт музея (в буфер обмена и файл)", _export)
	_btn(v, "Импорт музея (из буфера обмена или файла)", _import)
	_btn(v, "Сбросить музей к исходному", func(): state = MuseumData.load_base(); _save(); rebuild(); _teleport(0); toast("Музей сброшен"))
	var info := Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Управление: ПК — WASD/стрелки, мышь (клик — захват, Esc — отпустить), E — карточка, T — чат, Shift — бег. Телефон — джойстик слева, свайп справа — обзор, касание экспоната — карточка.\nДанные: Wikidata, Wikimedia Commons, Википедия (CC BY-SA). Без политики."
	v.add_child(info)
	set_dlg.add_child(sc); set_dlg.popup_centered()

func _export_path() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return (d + "/IIMuzej-export.json") if d != "" and OS.get_name() in ["Windows", "Linux", "macOS"] else "user://IIMuzej-export.json"

func _export() -> void:
	var s := JSON.stringify(state, "\t")
	DisplayServer.clipboard_set(s)
	var p := _export_path(); var f := FileAccess.open(p, FileAccess.WRITE)
	if f: f.store_string(s); f.close()
	toast("Экспортировано: буфер обмена и %s" % ProjectSettings.globalize_path(p))

func _import() -> void:
	var j = JSON.parse_string(DisplayServer.clipboard_get())
	if not MuseumData.valid(j) and FileAccess.file_exists(_export_path()): j = JSON.parse_string(FileAccess.get_file_as_string(_export_path()))
	if MuseumData.valid(j):
		state = j; _save(); rebuild(); _teleport(0); toast("Импортировано залов: %d" % state["halls"].size())
	else: toast("Нет корректного JSON музея в буфере обмена / файле")

func _save() -> void: MuseumData.save_state(state)

func _key() -> String: return "iimuzej-" + ("web" if OS.has_feature("web") else OS.get_unique_id())
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load_encrypted_pass("user://settings.cfg", _key()) == OK:
		for k in settings.keys(): settings[k] = cf.get_value("s", k, settings[k])
func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys(): cf.set_value("s", k, settings[k])
	cf.save_encrypted_pass("user://settings.cfg", _key())

# ---------- ИИ ----------
func ai_context() -> Dictionary:
	var c := {"hall": cur_hall, "halls": state["halls"].map(func(h): return h["name"])}
	if not focus.is_empty(): c["exhibit"] = focus["ex"]; c["shelf"] = focus["shelf"]
	return c

func send_chat(t: String) -> void:
	t = t.strip_edges()
	if t == "" or busy_ai: return
	chat_in.text = ""; busy_ai = true
	chat_log.append_text("\n[color=#8ecae6][b]Вы:[/b] %s[/color]\n" % t.replace("[", "(")); toast("ИИ думает…")
	ai.ask(settings["provider"], t, ai_context(), settings)

func _on_ai_reply(text: String, data: Dictionary) -> void:
	busy_ai = false
	chat_log.append_text("[b]Гид:[/b] %s\n" % text)
	for l in data.get("links", []):
		if l is Dictionary and String(l.get("url", "")).begins_with("http"): chat_log.append_text("» [url=%s]%s[/url]\n" % [l["url"], l.get("title", l["url"])])
	var imgs: Array = []
	for i in data.get("images", []):
		if i is Dictionary and String(i.get("url", "")).begins_with("http"): imgs.append(i)
	for q in data.get("image_queries", []).slice(0, 2):
		imgs.append_array(await wiki.images(str(q), 4))
	_show_images(imgs)
	var acts: Array = data.get("actions", [])
	if not acts.is_empty(): await apply_actions(acts)

func _show_images(imgs: Array) -> void:
	for c in chat_imgs.get_children(): c.queue_free()
	var mode: String = settings["image_mode"]
	var n := 0
	for i in imgs:
		var url: String = i.get("url", ""); var page: String = i.get("page", url)
		var embed := mode == "embed" or (mode == "auto" and n < 4)
		if embed:
			var tb := TextureButton.new(); tb.custom_minimum_size = Vector2(150, 110); tb.ignore_texture_size = true; tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			tb.tooltip_text = i.get("caption", ""); tb.pressed.connect(func(): OS.shell_open(page)); chat_imgs.add_child(tb)
			var cbk := func(u, tex): if u == url and is_instance_valid(tb): tb.texture_normal = tex
			images.loaded.connect(cbk); images.request(url, true); tb.tree_exiting.connect(func(): if images.loaded.is_connected(cbk): images.loaded.disconnect(cbk))
		else:
			chat_log.append_text("» [url=%s]%s[/url] [color=#888]%s[/color]\n" % [page, String(i.get("caption", "изображение")).left(60), i.get("lic", "")])
		n += 1

func apply_actions(acts: Array) -> void:
	var added := 0; var goto := ""
	for a in acts:
		if not (a is Dictionary): continue
		var ty: String = a.get("type", "")
		var hall: String = a.get("hall", cur_hall)
		if WikiT.is_political(JSON.stringify(a)): continue
		match ty:
			"create_hall": MuseumData.add_hall(state, a.get("name", "Новый зал"))
			"create_shelf":
				var nm: String = a.get("name", "Стеллаж")
				MuseumData.add_shelf(state, hall, nm)
				var q: String = a.get("query", "")
				if q != "":
					toast("Наполняю стеллаж «%s»…" % nm)
					var skip: int = a.get("skip", 0)
					var res: Array = await wiki.search_exhibits(q, 6 + skip)
					for r in res.slice(skip, skip + 6):
						MuseumData.add_exhibit(state, hall, nm, r); added += 1
			"add_exhibit":
				var e: Dictionary = a.duplicate()
				if String(e.get("image_url", "")) == "" or String(e.get("description", "")) == "":
					var s: Dictionary = await wiki.summary(String(e.get("wiki", e.get("title", ""))))
					if not s.is_empty():
						if String(e.get("image_url", "")) == "": e["image_url"] = s.get("img", "")
						if String(e.get("description", "")) == "": e["description"] = s.get("desc", "")
						e["src"] = s.get("src", ""); e["lic"] = "Википедия / Wikimedia Commons"
				MuseumData.add_exhibit(state, hall, a.get("shelf", "Новые экспонаты"), e); added += 1
			"remove_exhibit": MuseumData.remove_exhibit(state, a.get("title", ""))
			"remove_shelf": MuseumData.remove_shelf(state, hall, a.get("name", ""))
			"rename_hall":
				var h := MuseumData.find_hall(state, a.get("name", ""))
				if not h.is_empty(): h["name"] = a.get("new_name", h["name"])
			"goto_hall": goto = a.get("name", "")
	urgent_halls = acts.map(func(a): return a.get("hall", a.get("name", "")) if a is Dictionary else "")
	_save(); rebuild(); urgent_halls = []
	if goto != "": _teleport(MuseumData.hall_index(state, goto))
	chat_log.append_text("[color=#90be6d]Музей обновлён: добавлено экспонатов — %d. Всего: %d.[/color]\n" % [added, MuseumData.count_exhibits(state)])

# ---------- самопроверка ----------
func _selftest_walk() -> void:
	DirAccess.make_dir_recursive_absolute("/workspace/museum/test-shots")
	await get_tree().create_timer(12.0).timeout
	get_viewport().get_texture().get_image().save_png("/workspace/museum/test-shots/pc-1-start.png")
	joy_id = 99; joy_v = Vector2(0.3, -1)
	await get_tree().create_timer(2.0).timeout
	yaw += 1.2; joy_v = Vector2.ZERO; joy_id = -1
	await get_tree().create_timer(6.0).timeout
	get_viewport().get_texture().get_image().save_png("/workspace/museum/test-shots/pc-2-walk.png")
	open_card(state["halls"][0]["shelves"][0]["exhibits"][0])
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png("/workspace/museum/test-shots/pc-3-card.png")
	card.hide(); toggle_chat(true)
	focus = {"ex": state["halls"][0]["shelves"][0]["exhibits"][1], "hall": state["halls"][0]["name"], "shelf": "x"}
	send_chat("А что это?")
	await get_tree().create_timer(10.0).timeout
	busy_ai = false
	send_chat("Сделай мне зал с импрессионистами")
	await get_tree().create_timer(25.0).timeout
	get_viewport().get_texture().get_image().save_png("/workspace/museum/test-shots/pc-4-ai-hall.png")
	toggle_chat(false)
	await get_tree().create_timer(8.0).timeout
	get_viewport().get_texture().get_image().save_png("/workspace/museum/test-shots/pc-5-new-hall.png")
	print("SELFTEST pos=", player.global_position, " hall=", cur_hall, " ex=", MuseumData.count_exhibits(state), " halls=", state["halls"].size())
	if not OS.has_feature("web"): get_tree().quit()
