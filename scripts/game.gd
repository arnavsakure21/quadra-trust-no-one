extends Node2D

const ActorScript = preload("res://scripts/player_actor.gd")
const MAP_W := 1800.0
const MAP_H := 1200.0
const DEFAULT_PORT := 27145
const ROLES := ["Hacker", "Engineer", "Scout", "Guardian"]
const ROLE_COLORS := {
	"Hacker": Color(0.20, 0.68, 1.0),
	"Engineer": Color(0.27, 0.92, 0.55),
	"Scout": Color(1.0, 0.78, 0.18),
	"Guardian": Color(1.0, 0.30, 0.28),
}
const CLUES := [Vector2(550, 650), Vector2(1320, 545), Vector2(1290, 965)]
const CLUE_DIGITS := [4, 2, 7]
const HAZARDS := [Rect2(1160, 490, 220, 72), Rect2(675, 885, 230, 72), Rect2(1170, 900, 210, 72)]
const HAZARD_CENTERS := [Vector2(1270, 526), Vector2(790, 921), Vector2(1275, 936)]
const GENERATOR_POS := Vector2(270, 180)
const HACK_PANEL_POS := Vector2(650, 545)
const CODE_PANEL_POS := Vector2(1500, 975)
const EXIT_POS := Vector2(1660, 995)
const PLAYER_SPAWNS := [Vector2(205, 815), Vector2(290, 815), Vector2(205, 900), Vector2(290, 900)]

var actors: Dictionary = {}
var doors: Array[StaticBody2D] = []
var game_started := false
var is_host := false
var lobby_peers: Array[int] = []
var match_state: Dictionary = {}
var ui_layer: CanvasLayer
var ui_root: Control
var ip_input: LineEdit
var port_input: LineEdit
var lobby_status: Label
var lobby_slots: Label
var start_button: Button
var hud_timer: Label
var hud_objectives: Label
var hud_role: Label
var hud_team: Label
var hud_message: Label
var hud_prompt: Label
var code_entry: LineEdit
var code_panel: PanelContainer
var snapshot_clock := 0.0
var action_clock := 0.0
var hazard_clocks: Dictionary = {}
var lobby_port := DEFAULT_PORT

func _ready() -> void:
	_build_collisions()
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(true)
	set_physics_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	if game_started and match_state.get("status", "playing") == "playing":
		_update_hud()
		if hud_message != null:
			hud_message.text = str(match_state.get("message", ""))
		if hud_prompt != null:
			hud_prompt.text = _get_prompt()

func _physics_process(delta: float) -> void:
	if not game_started or match_state.get("status", "playing") != "playing":
		return
	var local_actor = _local_actor()
	if local_actor != null and not local_actor.down and local_actor.connected:
		local_actor.input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	else:
		if local_actor != null:
			local_actor.input_vector = Vector2.ZERO
	if multiplayer.is_server():
		_server_tick(delta)
		snapshot_clock += delta
		if snapshot_clock >= 0.08:
			snapshot_clock = 0.0
			_broadcast_state()
	else:
		if local_actor != null and not local_actor.down:
			local_actor.velocity = local_actor.input_vector * 250.0
			local_actor.move_and_slide()
		action_clock += delta
		if action_clock >= 0.05 and local_actor != null:
			action_clock = 0.0
			rpc_id(1, "request_move", local_actor.input_vector.x, local_actor.input_vector.y)

func _unhandled_input(event: InputEvent) -> void:
	if not game_started or match_state.get("status", "playing") != "playing":
		return
	if code_panel != null and is_instance_valid(code_panel) and event.is_action_pressed("ui_cancel"):
		code_panel.queue_free()
		code_panel = null
		code_entry = null
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ability"):
		_request_action("ability", "")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and (code_panel == null or not is_instance_valid(code_panel)):
		_try_interact()
		get_viewport().set_input_as_handled()

func _build_collisions() -> void:
	_add_wall(Rect2(0, -30, MAP_W, 60))
	_add_wall(Rect2(0, MAP_H - 30, MAP_W, 60))
	_add_wall(Rect2(-30, 0, 60, MAP_H))
	_add_wall(Rect2(MAP_W - 30, 0, 60, MAP_H))
	_add_wall(Rect2(30, 408, 740, 24))
	_add_wall(Rect2(1030, 408, 740, 24))
	_add_wall(Rect2(1058, 432, 24, 278))
	_add_wall(Rect2(1058, 862, 24, 308))
	_add_door(Rect2(770, 390, 260, 60))
	_add_door(Rect2(1050, 710, 40, 152))

func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.position + rect.size / 2.0
	body.add_child(shape)
	add_child(body)

func _add_door(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.position + rect.size / 2.0
	body.add_child(shape)
	add_child(body)
	doors.append(body)

func _draw() -> void:
	if not game_started:
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.015, 0.035, 0.058))
		for i in range(24):
			var x := float((i * 193) % 1280)
			var y := float((i * 317) % 720)
			draw_circle(Vector2(x, y), 1.5 + float(i % 3), Color(0.20, 0.47, 0.60, 0.18))
		return
	draw_rect(Rect2(0, 0, MAP_W, MAP_H), Color(0.025, 0.055, 0.078))
	draw_rect(Rect2(30, 30, MAP_W - 60, MAP_H - 60), Color(0.055, 0.095, 0.12))
	for x in range(48, int(MAP_W), 64):
		draw_line(Vector2(x, 32), Vector2(x, MAP_H - 32), Color(0.20, 0.38, 0.44, 0.12), 1.0)
	for y in range(48, int(MAP_H), 64):
		draw_line(Vector2(32, y), Vector2(MAP_W - 32, y), Color(0.20, 0.38, 0.44, 0.12), 1.0)
	_draw_room_trim()
	var sec_open: bool = match_state.get("security", false)
	draw_rect(Rect2(30, 398, 740, 44), Color(0.16, 0.26, 0.30))
	draw_rect(Rect2(1030, 398, 740, 44), Color(0.16, 0.26, 0.30))
	draw_rect(Rect2(1048, 432, 44, 278), Color(0.16, 0.26, 0.30))
	draw_rect(Rect2(1048, 862, 44, 308), Color(0.16, 0.26, 0.30))
	if not sec_open:
		_draw_door(Rect2(770, 390, 260, 60))
		_draw_door(Rect2(1050, 710, 40, 152))
	_draw_hazards()
	_draw_generator()
	_draw_panel(HACK_PANEL_POS, Color(0.22, 0.68, 1.0), "SECURITY")
	_draw_panel(CODE_PANEL_POS, Color(1.0, 0.72, 0.18), "ACCESS CODE")
	_draw_exit(_is_exit_ready())
	var revealed: Array = match_state.get("clue_revealed", [false, false, false])
	var collected: Array = match_state.get("clues", [false, false, false])
	for i in range(CLUES.size()):
		if i < revealed.size() and revealed[i] and (i >= collected.size() or not collected[i]):
			_draw_clue(CLUES[i], int(CLUE_DIGITS[i]))
	_draw_room_labels()

func _draw_room_trim() -> void:
	var trim := Color(0.16, 0.42, 0.48, 0.42)
	draw_line(Vector2(56, 70), Vector2(360, 70), trim, 2.0)
	draw_line(Vector2(56, 70), Vector2(56, 115), trim, 2.0)
	draw_line(Vector2(1720, 1125), Vector2(1450, 1125), trim, 2.0)
	draw_line(Vector2(1720, 1125), Vector2(1720, 1080), trim, 2.0)
	for x in range(0, 1800, 120):
		draw_rect(Rect2(x + 14, 16, 32, 4), Color(0.12, 0.28, 0.34, 0.65))
		draw_rect(Rect2(x + 14, MAP_H - 20, 32, 4), Color(0.12, 0.28, 0.34, 0.65))

func _draw_room_labels() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	_draw_text(font, Vector2(90, 96), "REACTOR / A", Color(0.42, 0.70, 0.76, 0.75), 14)
	_draw_text(font, Vector2(1140, 96), "CONTROL BAY / B", Color(0.42, 0.70, 0.76, 0.75), 14)
	_draw_text(font, Vector2(90, 485), "CONTAINMENT / C", Color(0.42, 0.70, 0.76, 0.75), 14)
	_draw_text(font, Vector2(1160, 485), "TRANSFER / D", Color(0.42, 0.70, 0.76, 0.75), 14)
	_draw_text(font, Vector2(1160, 900), "EVACUATION / E", Color(0.42, 0.70, 0.76, 0.75), 14)

func _draw_text(font: Font, pos: Vector2, text: String, color: Color, size: int) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)

func _draw_door(rect: Rect2) -> void:
	draw_rect(rect, Color(0.12, 0.22, 0.28))
	var count := 7 if rect.size.x > rect.size.y else 4
	if rect.size.x > rect.size.y:
		for i in range(count):
			var x := rect.position.x + 9 + i * (rect.size.x - 18) / count
			draw_rect(Rect2(x, rect.position.y + 7, 12, rect.size.y - 14), Color(0.07, 0.14, 0.19))
		draw_line(rect.position + Vector2(0, 3), Vector2(rect.end.x, rect.position.y + 3), Color(0.20, 0.69, 1.0, 0.8), 3.0)
	else:
		for i in range(count):
			var y := rect.position.y + 9 + i * (rect.size.y - 18) / count
			draw_rect(Rect2(rect.position.x + 7, y, rect.size.x - 14, 12), Color(0.07, 0.14, 0.19))
		draw_line(rect.position + Vector2(3, 0), Vector2(rect.position.x + 3, rect.end.y), Color(0.20, 0.69, 1.0, 0.8), 3.0)

func _draw_hazards() -> void:
	var revealed: Array = match_state.get("trap_revealed", [false, false, false])
	var scanning := float(match_state.get("scout_scan", 0.0)) > 0.0
	for i in range(HAZARDS.size()):
		var rect: Rect2 = HAZARDS[i]
		var disabled := float(match_state.get("security_disabled", 0.0)) > 0.0
		var trap_seen: bool = i < revealed.size() and bool(revealed[i])
		var tint := Color(0.10, 0.17, 0.18, 0.52)
		if disabled:
			tint = Color(0.08, 0.34, 0.30, 0.55)
		elif trap_seen and scanning:
			tint = Color(0.88, 0.24, 0.09, 0.38)
		draw_rect(rect, tint)
		if disabled or (trap_seen and scanning):
			var stripes := 7
			var stripe_color := Color(0.35, 1.0, 0.63, 0.80) if disabled else Color(1.0, 0.56, 0.16, 0.76)
			for j in range(stripes):
				var sx := rect.position.x + 6 + float(j) * (rect.size.x - 12) / stripes
				draw_line(Vector2(sx, rect.position.y + 4), Vector2(sx + 18, rect.position.y + rect.size.y - 4), stripe_color, 4.0)
			draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 4), stripe_color)

func _draw_generator() -> void:
	_draw_glow(GENERATOR_POS, 70.0, Color(0.22, 0.92, 0.56, 0.14))
	draw_rect(Rect2(GENERATOR_POS + Vector2(-46, -34), Vector2(92, 68)), Color(0.07, 0.18, 0.19))
	draw_rect(Rect2(GENERATOR_POS + Vector2(-39, -28), Vector2(78, 56)), Color(0.10, 0.26, 0.24))
	draw_rect(Rect2(GENERATOR_POS + Vector2(-27, -18), Vector2(13, 36)), Color(0.24, 0.92, 0.54))
	draw_rect(Rect2(GENERATOR_POS + Vector2(-6, -18), Vector2(13, 36)), Color(0.24, 0.92, 0.54, 0.62))
	draw_rect(Rect2(GENERATOR_POS + Vector2(15, -18), Vector2(13, 36)), Color(0.24, 0.92, 0.54, 0.33))
	if match_state.get("power", false):
		draw_circle(GENERATOR_POS, 5, Color(0.42, 1.0, 0.63))

func _draw_panel(pos: Vector2, color: Color, title: String) -> void:
	_draw_glow(pos, 56.0, Color(color.r, color.g, color.b, 0.12))
	draw_rect(Rect2(pos + Vector2(-29, -22), Vector2(58, 44)), Color(0.07, 0.15, 0.21))
	draw_rect(Rect2(pos + Vector2(-22, -16), Vector2(44, 32)), Color(0.10, 0.25, 0.32))
	draw_rect(Rect2(pos + Vector2(-14, -8), Vector2(28, 16)), Color(color.r, color.g, color.b, 0.85))
	var font := ThemeDB.fallback_font
	if font != null:
		_draw_text(font, pos + Vector2(-48, 39), title, Color(0.70, 0.82, 0.86), 11)

func _draw_clue(pos: Vector2, digit: int) -> void:
	_draw_glow(pos, 28.0, Color(1.0, 0.78, 0.18, 0.2))
	draw_circle(pos, 12.0, Color(1.0, 0.77, 0.15))
	draw_circle(pos, 7.0, Color(0.12, 0.16, 0.17))
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, pos + Vector2(-4, 4), str(digit), HORIZONTAL_ALIGNMENT_CENTER, 9.0, 11, Color(1.0, 0.91, 0.48))

func _draw_exit(opened: bool) -> void:
	_draw_glow(EXIT_POS, 92.0, Color(0.17, 0.94, 0.77, 0.12 if opened else 0.04))
	draw_rect(Rect2(EXIT_POS + Vector2(-56, -70), Vector2(112, 140)), Color(0.07, 0.18, 0.21))
	draw_rect(Rect2(EXIT_POS + Vector2(-40, -58), Vector2(80, 116)), Color(0.10, 0.28, 0.30))
	if opened:
		draw_rect(Rect2(EXIT_POS + Vector2(-31, -48), Vector2(62, 96)), Color(0.12, 0.78, 0.65, 0.55))
		draw_line(EXIT_POS + Vector2(-35, -54), EXIT_POS + Vector2(35, -54), Color(0.34, 1.0, 0.80), 4.0)
	else:
		_draw_door(Rect2(EXIT_POS + Vector2(-34, -52), Vector2(68, 104)))

func _draw_glow(pos: Vector2, radius: float, color: Color) -> void:
	for i in range(5, 0, -1):
		draw_circle(pos, radius * float(i) / 5.0, Color(color.r, color.g, color.b, color.a / float(i) * 1.3))

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)
	_show_menu("")

func _clear_ui() -> void:
	for child in ui_root.get_children():
		child.queue_free()
	lobby_status = null
	lobby_slots = null
	start_button = null
	hud_timer = null
	hud_objectives = null
	hud_role = null
	hud_team = null
	hud_message = null
	hud_prompt = null
	code_panel = null
	code_entry = null

func _show_menu(status: String) -> void:
	_clear_ui()
	var panel := _make_panel(Vector2(480, 560))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -285
	panel.offset_bottom = 285
	ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := _label("QUADRA", 40, Color(0.42, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(title)
	box.add_child(_label("FOUR OPERATORS. ONE WAY OUT.", 13, Color(0.62, 0.78, 0.85), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("Co-op escape protocol  /  10:00", 15, Color(0.78, 0.88, 0.91), HORIZONTAL_ALIGNMENT_CENTER))
	var host_button := _button("HOST GAME", true)
	box.add_child(host_button)
	host_button.pressed.connect(_on_host_pressed)
	box.add_child(_label("JOIN A DIRECT-IP LOBBY", 12, Color(0.54, 0.74, 0.81)))
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Host IP (example: 192.168.1.10)"
	ip_input.text = "127.0.0.1"
	ip_input.custom_minimum_size.y = 42
	_style_input(ip_input)
	box.add_child(ip_input)
	port_input = LineEdit.new()
	port_input.placeholder_text = "UDP port"
	port_input.text = str(DEFAULT_PORT)
	port_input.custom_minimum_size.y = 42
	_style_input(port_input)
	box.add_child(port_input)
	var join_button := _button("JOIN GAME", false)
	box.add_child(join_button)
	join_button.pressed.connect(_on_join_pressed)
	var help := _label("WASD / arrows move   ·   E interact   ·   F role ability\nFind three clues, restore reactor power, breach security, enter code 427, then reach evacuation.", 13, Color(0.57, 0.71, 0.77), HORIZONTAL_ALIGNMENT_CENTER)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	lobby_status = _label(status, 13, Color(1.0, 0.72, 0.38), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(lobby_status)

func _show_lobby() -> void:
	_clear_ui()
	var panel := _make_panel(Vector2(520, 500))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -250
	panel.offset_bottom = 250
	ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_label("QUADRA // CREW LOBBY", 28, Color(0.42, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("Direct connection   ·   UDP %d" % lobby_port, 13, Color(0.65, 0.79, 0.84), HORIZONTAL_ALIGNMENT_CENTER))
	lobby_slots = _label("", 16, Color(0.86, 0.94, 0.96))
	lobby_slots.custom_minimum_size.y = 150
	box.add_child(lobby_slots)
	lobby_status = _label("Waiting for operators…", 14, Color(0.76, 0.84, 0.86), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(lobby_status)
	start_button = _button("START MATCH  /  4 REQUIRED", true)
	box.add_child(start_button)
	start_button.disabled = not is_host or lobby_peers.size() != 4
	start_button.visible = is_host
	start_button.pressed.connect(_on_start_pressed)
	var back := _button("LEAVE LOBBY", false)
	box.add_child(back)
	back.pressed.connect(_leave_lobby)
	_refresh_lobby()

func _show_hud() -> void:
	_clear_ui()
	var top := _make_panel(Vector2(420, 164))
	top.anchor_left = 0.02
	top.anchor_top = 0.025
	top.anchor_right = 0.02
	top.anchor_bottom = 0.025
	top.offset_left = 0
	top.offset_top = 0
	top.offset_right = 420
	top.offset_bottom = 164
	ui_root.add_child(top)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	top.add_child(box)
	hud_timer = _label("10:00  //  QUADRA", 24, Color(0.48, 0.89, 1.0))
	box.add_child(hud_timer)
	hud_objectives = _label("", 14, Color(0.85, 0.93, 0.94))
	box.add_child(hud_objectives)
	hud_role = _label("", 14, Color(0.93, 0.97, 0.97))
	box.add_child(hud_role)
	hud_team = _label("", 13, Color(0.64, 0.82, 0.86))
	box.add_child(hud_team)
	var message_panel := _make_panel(Vector2(520, 60))
	message_panel.anchor_left = 0.5
	message_panel.anchor_right = 0.5
	message_panel.anchor_top = 0.02
	message_panel.anchor_bottom = 0.02
	message_panel.offset_left = -260
	message_panel.offset_right = 260
	message_panel.offset_top = 0
	message_panel.offset_bottom = 60
	ui_root.add_child(message_panel)
	hud_message = _label("", 14, Color(1.0, 0.82, 0.38), HORIZONTAL_ALIGNMENT_CENTER)
	message_panel.add_child(hud_message)
	var prompt_panel := _make_panel(Vector2(600, 42))
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 0.90
	prompt_panel.anchor_bottom = 0.90
	prompt_panel.offset_left = -300
	prompt_panel.offset_right = 300
	prompt_panel.offset_top = 0
	prompt_panel.offset_bottom = 42
	ui_root.add_child(prompt_panel)
	hud_prompt = _label("WASD move  ·  E interact  ·  F ability", 14, Color(0.80, 0.90, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	prompt_panel.add_child(hud_prompt)
	_update_hud()

func _make_panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.075, 0.10, 0.94)
	style.border_color = Color(0.14, 0.46, 0.54, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.91, 0.97, 0.98))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.31, 0.38) if primary else Color(0.055, 0.16, 0.20)
	normal.border_color = Color(0.19, 0.67, 0.75)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.10, 0.42, 0.48) if primary else Color(0.08, 0.25, 0.30)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.04, 0.23, 0.29)
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _style_input(input: LineEdit) -> void:
	input.add_theme_color_override("font_color", Color(0.90, 0.96, 0.98))
	input.add_theme_color_override("font_placeholder_color", Color(0.42, 0.60, 0.66))
	input.add_theme_stylebox_override("normal", _input_style())
	input.add_theme_stylebox_override("focus", _input_style())
	input.add_theme_stylebox_override("read_only", _input_style())

func _input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.12, 0.15)
	style.border_color = Color(0.14, 0.39, 0.46)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _on_host_pressed() -> void:
	var raw_port := port_input.text.strip_edges() if port_input != null else str(DEFAULT_PORT)
	lobby_port = int(raw_port) if raw_port.is_valid_int() else DEFAULT_PORT
	if lobby_port < 1 or lobby_port > 65535:
		_show_menu("Port must be between 1 and 65535.")
		return
	var enet := ENetMultiplayerPeer.new()
	var error := enet.create_server(lobby_port, 3)
	if error != OK:
		_show_menu("Host failed (%s). Check whether UDP port %d is available." % [error_string(error), lobby_port])
		return
	multiplayer.multiplayer_peer = enet
	is_host = true
	lobby_peers = [1]
	_show_lobby()
	_refresh_lobby()

func _on_join_pressed() -> void:
	var address := ip_input.text.strip_edges() if ip_input != null else "127.0.0.1"
	var raw_port := port_input.text.strip_edges() if port_input != null else str(DEFAULT_PORT)
	lobby_port = int(raw_port) if raw_port.is_valid_int() else DEFAULT_PORT
	if address.is_empty() or lobby_port < 1 or lobby_port > 65535:
		_show_menu("Enter a host IP and valid UDP port.")
		return
	var enet := ENetMultiplayerPeer.new()
	var error := enet.create_client(address, lobby_port)
	if error != OK:
		_show_menu("Join failed (%s). Check the IP and port." % error_string(error))
		return
	multiplayer.multiplayer_peer = enet
	is_host = false
	lobby_peers.clear()
	_show_lobby()
	if lobby_status != null:
		lobby_status.text = "Connecting to %s:%d…" % [address, lobby_port]

func _on_connected_to_server() -> void:
	if not game_started:
		_show_lobby()
		lobby_status.text = "Connected. Waiting for host to fill the crew…"

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	is_host = false
	_show_menu("Connection failed. Confirm the host IP, UDP port and firewall settings.")

func _on_server_disconnected() -> void:
	game_started = false
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()
	multiplayer.multiplayer_peer = null
	is_host = false
	_show_menu("Host connection lost. Your match ended.")
	queue_redraw()

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if game_started:
		match_state["message"] = "Match is in progress. New operators must wait for the next lobby."
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if not lobby_peers.has(id):
		lobby_peers.append(id)
		lobby_peers.sort()
	if not game_started:
		_sync_lobby()
		_refresh_lobby()

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		lobby_peers.erase(id)
		if game_started and actors.has(id):
			actors[id].connected = false
			actors[id].input_vector = Vector2.ZERO
			actors[id].collision_layer = 0
			actors[id].collision_mask = 0
			_set_message("Operator %d disconnected. Their role is now available to the crew." % id)
			match_state["message"] = "Operator %d disconnected. Their role is now available to the crew." % id
			if _role_missing("Hacker") or _role_missing("Engineer") or _role_missing("Scout") or _role_missing("Guardian"):
				pass
			_broadcast_state()
		else:
			_sync_lobby()
			_refresh_lobby()
	if not multiplayer.is_server() and not game_started:
		_show_lobby()
		lobby_status.text = "An operator left the lobby."

func _sync_lobby() -> void:
	lobby_peers = [1]
	for id in multiplayer.get_peers():
		lobby_peers.append(int(id))
	lobby_peers.sort()
	var ids := lobby_peers.duplicate()
	for id in multiplayer.get_peers():
		rpc_id(int(id), "client_lobby_update", ids)
	_refresh_lobby()

@rpc("authority", "call_remote", "reliable")
func client_lobby_update(ids: Array) -> void:
	lobby_peers.clear()
	for id in ids:
		lobby_peers.append(int(id))
	lobby_peers.sort()
	is_host = false
	_refresh_lobby()
	if lobby_status != null:
		lobby_status.text = "Connected. Waiting for host to start…"

func _refresh_lobby() -> void:
	if lobby_slots == null or not is_instance_valid(lobby_slots):
		return
	var lines := PackedStringArray()
	var sorted := lobby_peers.duplicate()
	sorted.sort()
	for i in range(4):
		if i < sorted.size():
			var id: int = sorted[i]
			var local_mark := "  (YOU)" if id == multiplayer.get_unique_id() else ""
			lines.append("SLOT %d   %s%s" % [i + 1, ROLES[i].to_upper(), local_mark])
		else:
			lines.append("SLOT %d   WAITING FOR OPERATOR…" % (i + 1))
	lobby_slots.text = "\n".join(lines)
	if lobby_status != null and is_host:
		lobby_status.text = "%d / 4 operators connected" % sorted.size()
	if start_button != null:
		start_button.disabled = not is_host or sorted.size() != 4

func _on_start_pressed() -> void:
	if not multiplayer.is_server() or lobby_peers.size() != 4:
		return
	var ids := lobby_peers.duplicate()
	ids.sort()
	var records: Array = []
	for i in range(4):
		records.append({"id": ids[i], "role": ROLES[i], "x": PLAYER_SPAWNS[i].x, "y": PLAYER_SPAWNS[i].y})
	_begin_match(records)
	rpc("client_start_game", records)

@rpc("authority", "call_remote", "reliable")
func client_start_game(records: Array) -> void:
	_begin_match(records)

func _begin_match(records: Array) -> void:
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()
	game_started = true
	match_state = {
		"status": "playing", "time": 600.0, "power": false, "security": false,
		"code_solved": false, "clues": [false, false, false], "clue_revealed": [false, false, false],
		"trap_revealed": [false, false, false],
		"repair_progress": 0.0, "hack_progress": 0.0, "security_disabled": 0.0,
		"scout_scan": 0.0, "message": "Three protocols are locked. Find the way out.", "winner": ""
	}
	for record in records:
		var actor = ActorScript.new()
		actor.peer_id = int(record["id"])
		actor.set_multiplayer_authority(actor.peer_id)
		actor.role = str(record["role"])
		actor.position = Vector2(float(record["x"]), float(record["y"]))
		actor.spawn_position = actor.position
		actor.target_position = actor.position
		actor.nickname = "OP-%02d" % actor.peer_id
		add_child(actor)
		actors[actor.peer_id] = actor
		if actor.peer_id == multiplayer.get_unique_id():
			var camera := Camera2D.new()
			camera.zoom = Vector2(0.85, 0.85)
			camera.position_smoothing_enabled = true
			camera.position_smoothing_speed = 6.0
			actor.add_child(camera)
			camera.make_current()
	_set_doors_open(false)
	_show_hud()
	queue_redraw()
	if multiplayer.is_server():
		_broadcast_state()

func _server_tick(delta: float) -> void:
	if match_state.get("status", "playing") != "playing":
		return
	match_state["time"] = maxf(0.0, float(match_state.get("time", 600.0)) - delta)
	match_state["security_disabled"] = maxf(0.0, float(match_state.get("security_disabled", 0.0)) - delta)
	match_state["scout_scan"] = maxf(0.0, float(match_state.get("scout_scan", 0.0)) - delta)
	for actor in actors.values():
		if not actor.connected:
			continue
		actor.ability_cooldown = maxf(0.0, actor.ability_cooldown - delta)
		actor.shield_time = maxf(0.0, actor.shield_time - delta)
		if actor.down:
			actor.down_timer = maxf(0.0, actor.down_timer - delta)
			if actor.down_timer == 0.0:
				actor.down = false
				actor.health = 1
				actor.position = actor.spawn_position
				actor.input_vector = Vector2.ZERO
				match_state["message"] = "%s is back on their feet." % actor.role
		else:
			actor.velocity = actor.input_vector * 250.0
			actor.move_and_slide()
			actor.in_exit = _is_exit_ready() and actor.position.distance_to(EXIT_POS) < 95.0
	_update_puzzle_progress(delta)
	_update_hazards(delta)
	_check_match_end()
	if float(match_state.get("time", 0.0)) <= 0.0:
		_finish_match(false, "The containment clock reached zero.")

func _update_puzzle_progress(delta: float) -> void:
	if not match_state.get("power", false) and float(match_state.get("repair_progress", 0.0)) > 0.0:
		var left := maxf(0.0, float(match_state["repair_progress"]) - delta)
		match_state["repair_progress"] = left
		if left == 0.0:
			match_state["power"] = true
			match_state["message"] = "Reactor stable. Laboratory systems are online."
	if not match_state.get("security", false) and float(match_state.get("hack_progress", 0.0)) > 0.0:
		var left := maxf(0.0, float(match_state["hack_progress"]) - delta)
		match_state["hack_progress"] = left
		if left == 0.0:
			match_state["security"] = true
			_set_doors_open(true)
			match_state["message"] = "Security breach complete. Both pressure doors unlocked."
	if match_state.get("power", false) and match_state.get("security", false) and _all_clues_found() and not match_state.get("code_solved", false):
		match_state["message"] = "All clues recovered. Enter code 427 at the evacuation console."

func _update_hazards(delta: float) -> void:
	for actor in actors.values():
		if not actor.connected or actor.down:
			continue
		var in_hazard := false
		for hazard in HAZARDS:
			if hazard.has_point(actor.position):
				in_hazard = true
				break
		if not in_hazard:
			hazard_clocks[actor.peer_id] = 0.0
			continue
		if float(match_state.get("security_disabled", 0.0)) > 0.0 or _is_guarded(actor):
			continue
		var clock := float(hazard_clocks.get(actor.peer_id, 0.0)) + delta
		if clock >= 1.2:
			clock = 0.0
			actor.health -= 1
			match_state["message"] = "%s took hazard damage. Guardian shield or a security shutdown can protect the crew." % actor.role
			if actor.health <= 0:
				actor.down = true
				actor.down_timer = 12.0
				actor.input_vector = Vector2.ZERO
		hazard_clocks[actor.peer_id] = clock

func _is_guarded(actor) -> bool:
	for guardian in actors.values():
		if guardian.connected and guardian.role == "Guardian" and guardian.shield_time > 0.0 and guardian.position.distance_to(actor.position) <= 230.0:
			return true
	return false

func _check_match_end() -> void:
	var connected_count := 0
	var all_inside := true
	var all_down := true
	for actor in actors.values():
		if not actor.connected:
			continue
		connected_count += 1
		if not actor.in_exit:
			all_inside = false
		if not actor.down:
			all_down = false
	if connected_count > 0 and all_inside and _is_exit_ready():
		_finish_match(true, "All connected operators reached evacuation.")
	elif connected_count > 0 and all_down:
		_finish_match(false, "The whole crew is incapacitated.")

func _is_exit_ready() -> bool:
	return bool(match_state.get("power", false)) and bool(match_state.get("security", false)) and bool(match_state.get("code_solved", false))

func _finish_match(won: bool, reason: String) -> void:
	if match_state.get("status", "playing") != "playing":
		return
	match_state["status"] = "results"
	match_state["winner"] = "VICTORY" if won else "CONTAINMENT"
	match_state["message"] = reason
	_broadcast_state()
	_show_results(won, reason)

func _show_results(won: bool, reason: String) -> void:
	_clear_ui()
	var panel := _make_panel(Vector2(500, 280))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -140
	panel.offset_bottom = 140
	ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("EVACUATION CONFIRMED" if won else "CONTAINMENT FAILURE", 28, Color(0.40, 0.98, 0.79) if won else Color(1.0, 0.40, 0.32), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label(reason, 15, Color(0.82, 0.91, 0.93), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("Crew protocol complete.\nTime remaining: %s" % _format_time(float(match_state.get("time", 0.0))), 14, Color(0.64, 0.80, 0.84), HORIZONTAL_ALIGNMENT_CENTER))
	var restart := _button("RESTART MATCH  /  RETURN TO LOBBY", true)
	box.add_child(restart)
	restart.pressed.connect(_on_return_lobby_pressed)
func _on_return_lobby_pressed() -> void:
	if multiplayer.is_server():
		_return_to_lobby()
		rpc("client_return_lobby", lobby_peers)
	else:
		rpc_id(1, "request_return_lobby")

@rpc("any_peer", "call_remote", "reliable")
func request_return_lobby() -> void:
	if not multiplayer.is_server() or not game_started or match_state.get("status", "playing") != "results":
		return
	_return_to_lobby()
	rpc("client_return_lobby", lobby_peers)

@rpc("authority", "call_remote", "reliable")
func client_return_lobby(ids: Array) -> void:
	lobby_peers.clear()
	for id in ids:
		lobby_peers.append(int(id))
	is_host = false
	_return_to_lobby()

func _return_to_lobby() -> void:
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()
	game_started = false
	is_host = multiplayer.is_server()
	if is_host:
		_sync_lobby()
	_show_lobby()
	queue_redraw()

func _request_action(action: String, value: String) -> void:
	if multiplayer.is_server():
		_server_action(1, action, value)
	else:
		rpc_id(1, "request_action", action, value)

@rpc("any_peer", "call_remote", "reliable")
func request_action(action: String, value: String) -> void:
	if multiplayer.is_server():
		_server_action(multiplayer.get_remote_sender_id(), action, value)

func _server_action(sender: int, action: String, value: String) -> void:
	if not multiplayer.is_server() or not game_started or match_state.get("status", "playing") != "playing":
		return
	if action == "ability":
		_apply_ability(sender)
	elif action == "clue":
		_collect_clue(sender, int(value))
	elif action == "code":
		_submit_code(sender, value)
	elif action == "revive":
		_revive(sender, int(value))
	_broadcast_state()

func _apply_ability(sender: int) -> void:
	if not actors.has(sender):
		return
	var actor = actors[sender]
	if actor.down or not actor.connected:
		return
	if actor.ability_cooldown > 0.0:
		_set_message("Ability cooling down: %.1fs." % actor.ability_cooldown)
		return
	var role: String = str(actor.role)
	var near_panel: bool = actor.position.distance_to(HACK_PANEL_POS) <= 115.0
	var near_generator: bool = actor.position.distance_to(GENERATOR_POS) <= 125.0
	var ability := ""
	if role == "Hacker" and near_panel:
		ability = "hack"
	elif role == "Engineer" and near_generator:
		ability = "repair"
	elif role == "Scout":
		ability = "scan"
	elif role == "Guardian":
		ability = "shield"
	elif near_panel and _role_missing("Hacker"):
		ability = "hack"
	elif near_generator and _role_missing("Engineer"):
		ability = "repair"
	elif _role_missing("Scout"):
		ability = "scan"
	elif _role_missing("Guardian"):
		ability = "shield"
	if ability == "hack":
		if match_state.get("security", false):
			match_state["security_disabled"] = 8.0
			actor.ability_cooldown = 16.0
			_set_message("Security field suppressed for 8 seconds.")
		else:
			match_state["hack_progress"] = maxf(float(match_state.get("hack_progress", 0.0)), 4.0)
			actor.ability_cooldown = 8.0
			_set_message("Hacking both security doors…")
	elif ability == "repair":
		if match_state.get("power", false):
			_set_message("Reactor is already stable.")
			return
		match_state["repair_progress"] = maxf(float(match_state.get("repair_progress", 0.0)), 5.0)
		actor.ability_cooldown = 9.0
		_set_message("Repairing reactor relays…")
	elif ability == "scan":
		match_state["scout_scan"] = 7.0
		var revealed: Array = match_state.get("clue_revealed", [false, false, false])
		var traps: Array = match_state.get("trap_revealed", [false, false, false])
		var count := 0
		for i in range(CLUES.size()):
			if actor.position.distance_to(CLUES[i]) <= 350.0 and not revealed[i]:
				revealed[i] = true
				count += 1
		for i in range(HAZARD_CENTERS.size()):
			if actor.position.distance_to(HAZARD_CENTERS[i]) <= 350.0:
				traps[i] = true
		match_state["clue_revealed"] = revealed
		match_state["trap_revealed"] = traps
		actor.ability_cooldown = 11.0
		_set_message("Scout pulse: %d hidden clue(s) exposed. Nearby traps are highlighted for 7 seconds." % count)
	elif ability == "shield":
		actor.shield_time = 7.0
		actor.ability_cooldown = 19.0
		_set_message("Guardian shield active. Stay close to protect the crew.")
	elif role == "Hacker":
		_set_message("Reach the SECURITY panel to use the Hacker ability.")
	elif role == "Engineer":
		_set_message("Reach the reactor to use the Engineer ability.")
	else:
		_set_message("No role ability assigned.")

func _role_missing(role: String) -> bool:
	for actor in actors.values():
		if actor.connected and actor.role == role:
			return false
	return true

func _collect_clue(sender: int, index: int) -> void:
	if not actors.has(sender) or index < 0 or index >= CLUES.size():
		return
	var actor = actors[sender]
	if actor.down or not actor.connected:
		return
	var revealed: Array = match_state.get("clue_revealed", [false, false, false])
	var found: Array = match_state.get("clues", [false, false, false])
	if actor.position.distance_to(CLUES[index]) > 62.0 or not revealed[index] or found[index]:
		return
	found[index] = true
	match_state["clues"] = found
	_set_message("Clue recovered: digit %d." % CLUE_DIGITS[index])

func _submit_code(sender: int, value: String) -> void:
	if not actors.has(sender) or actors[sender].position.distance_to(CODE_PANEL_POS) > 125.0:
		return
	if actors[sender].down or not actors[sender].connected:
		return
	if not _all_clues_found():
		_set_message("The console needs all three recovered clue fragments.")
		return
	if value.strip_edges() == "427":
		match_state["code_solved"] = true
		_set_message("Code accepted. Evacuation airlock unlocked.")
	else:
		_set_message("Access denied. Recheck the recovered digits.")

func _revive(sender: int, target_id: int) -> void:
	if not actors.has(sender) or not actors.has(target_id):
		return
	var reviver = actors[sender]
	var target = actors[target_id]
	if target.down and reviver.connected and not reviver.down and reviver.position.distance_to(target.position) <= 65.0:
		target.down = false
		target.health = 1
		target.down_timer = 0.0
		_set_message("Operator %d revived." % target_id)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_move(x: float, y: float) -> void:
	if not multiplayer.is_server() or not game_started:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not actors.has(sender):
		return
	var actor = actors[sender]
	if actor.down or not actor.connected:
		actor.input_vector = Vector2.ZERO
		return
	actor.input_vector = Vector2(x, y).limit_length(1.0)

func _broadcast_state() -> void:
	var snapshot := _make_snapshot()
	rpc("client_apply_state", snapshot)
	_apply_snapshot(snapshot)

func _make_snapshot() -> Dictionary:
	var records: Array = []
	for id in actors.keys():
		var actor = actors[id]
		records.append({
			"id": actor.peer_id, "role": actor.role, "x": actor.position.x, "y": actor.position.y,
			"health": actor.health, "down": actor.down, "down_timer": actor.down_timer,
			"cooldown": actor.ability_cooldown, "shield": actor.shield_time,
			"exit": actor.in_exit, "connected": actor.connected
		})
	return {"players": records, "time": match_state.get("time", 600.0), "power": match_state.get("power", false),
		"security": match_state.get("security", false), "code_solved": match_state.get("code_solved", false),
		"clues": match_state.get("clues", [false, false, false]), "clue_revealed": match_state.get("clue_revealed", [false, false, false]),
		"repair_progress": match_state.get("repair_progress", 0.0), "hack_progress": match_state.get("hack_progress", 0.0),
	"security_disabled": match_state.get("security_disabled", 0.0), "scout_scan": match_state.get("scout_scan", 0.0),
	"trap_revealed": match_state.get("trap_revealed", [false, false, false]),
		"status": match_state.get("status", "playing"), "winner": match_state.get("winner", ""), "message": match_state.get("message", "")}

@rpc("authority", "call_remote", "unreliable_ordered")
func client_apply_state(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)

func _apply_snapshot(snapshot: Dictionary) -> void:
	if not game_started:
		return
	for key in ["time", "power", "security", "code_solved", "clues", "clue_revealed", "trap_revealed", "repair_progress", "hack_progress", "security_disabled", "scout_scan", "status", "winner", "message"]:
		if snapshot.has(key):
			match_state[key] = snapshot[key]
	for record in snapshot.get("players", []):
		var id := int(record.get("id", 0))
		if not actors.has(id):
			continue
		var actor = actors[id]
		actor.health = int(record.get("health", 3))
		actor.down = bool(record.get("down", false))
		actor.down_timer = float(record.get("down_timer", 0.0))
		actor.ability_cooldown = float(record.get("cooldown", 0.0))
		actor.shield_time = float(record.get("shield", 0.0))
		actor.in_exit = bool(record.get("exit", false))
		actor.connected = bool(record.get("connected", true))
		var pos := Vector2(float(record.get("x", actor.position.x)), float(record.get("y", actor.position.y)))
		if id == multiplayer.get_unique_id():
			if actor.position.distance_to(pos) > 90.0:
				actor.position = actor.position.lerp(pos, 0.5)
		else:
			actor.target_position = pos
		actor.queue_redraw()
	_set_doors_open(bool(match_state.get("security", false)))
	if match_state.get("status", "playing") == "results" and hud_timer != null:
		_show_results(str(match_state.get("winner", "")) == "VICTORY", str(match_state.get("message", "Match complete.")))
	queue_redraw()

func _set_doors_open(open: bool) -> void:
	for door in doors:
		if not is_instance_valid(door):
			continue
		if open:
			door.collision_layer = 0
			door.collision_mask = 0
		else:
			door.collision_layer = 1
			door.collision_mask = 0

func _local_actor():
	return actors.get(multiplayer.get_unique_id(), null)

func _try_interact() -> void:
	var actor = _local_actor()
	if actor == null or actor.down:
		return
	var closest := -1
	var closest_distance := INF
	var clues_found: Array = match_state.get("clues", [false, false, false])
	var revealed: Array = match_state.get("clue_revealed", [false, false, false])
	for i in range(CLUES.size()):
		if not clues_found[i] and revealed[i]:
			var distance: float = actor.position.distance_to(CLUES[i])
			if distance < closest_distance:
				closest_distance = distance
				closest = i
	if closest >= 0 and closest_distance <= 62.0:
		_request_action("clue", str(closest))
		return
	for id in actors.keys():
		if int(id) == actor.peer_id:
			continue
		var target = actors[id]
		if target.down and actor.position.distance_to(target.position) <= 65.0:
			_request_action("revive", str(id))
			return
	if actor.position.distance_to(CODE_PANEL_POS) <= 125.0:
		if _all_clues_found():
			_show_code_entry()
		else:
			_set_message("The code terminal needs three hidden clues. Ask the Scout to scan.")
		return
	if actor.position.distance_to(EXIT_POS) <= 125.0 and not _is_exit_ready():
		_set_message("Evacuation locked: restore power, hack security, and enter the clue code.")

func _show_code_entry() -> void:
	if code_panel != null and is_instance_valid(code_panel):
		return
	code_panel = _make_panel(Vector2(360, 138))
	code_panel.anchor_left = 0.5
	code_panel.anchor_right = 0.5
	code_panel.anchor_top = 0.70
	code_panel.anchor_bottom = 0.70
	code_panel.offset_left = -180
	code_panel.offset_right = 180
	code_panel.offset_top = 0
	code_panel.offset_bottom = 138
	ui_root.add_child(code_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	code_panel.add_child(box)
	box.add_child(_label("EVACUATION CODE", 16, Color(1.0, 0.78, 0.23), HORIZONTAL_ALIGNMENT_CENTER))
	code_entry = LineEdit.new()
	code_entry.placeholder_text = "3-digit code"
	code_entry.max_length = 3
	code_entry.custom_minimum_size.y = 38
	code_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(code_entry)
	box.add_child(code_entry)
	var submit := _button("SUBMIT   ·   ENTER", true)
	submit.custom_minimum_size.y = 36
	box.add_child(submit)
	submit.pressed.connect(_submit_code_ui)
	code_entry.text_submitted.connect(func(_text: String): _submit_code_ui())
	code_entry.grab_focus()

func _submit_code_ui() -> void:
	if code_entry == null:
		return
	_request_action("code", code_entry.text)
	if code_panel != null and is_instance_valid(code_panel):
		code_panel.queue_free()
	code_panel = null
	code_entry = null

func _get_prompt() -> String:
	var actor = _local_actor()
	if actor == null:
		return "Connecting crew…"
	if actor.down:
		return "INCAPACITATED  ·  teammates can revive you with E"
	if actor.position.distance_to(GENERATOR_POS) <= 125.0 and not match_state.get("power", false):
		return "F  ·  Engineer repairs reactor relays"
	if actor.position.distance_to(HACK_PANEL_POS) <= 115.0 and not match_state.get("security", false):
		return "F  ·  Hacker breaches the security doors"
	if actor.position.distance_to(CODE_PANEL_POS) <= 125.0:
		return "E  ·  Enter recovered code 427" if _all_clues_found() else "Scout scans for hidden clues  ·  E to collect"
	var revealed: Array = match_state.get("clue_revealed", [false, false, false])
	var found: Array = match_state.get("clues", [false, false, false])
	for i in range(CLUES.size()):
		if revealed[i] and not found[i] and actor.position.distance_to(CLUES[i]) <= 62.0:
			return "E  ·  Collect clue fragment"
	for id in actors.keys():
		if int(id) != actor.peer_id and actors[id].down and actor.position.distance_to(actors[id].position) <= 65.0:
			return "E  ·  Revive operator %d" % int(id)
	if _is_exit_ready() and actor.position.distance_to(EXIT_POS) <= 170.0:
		return "Evacuation open  ·  reach the airlock"
	return "WASD / arrows move   ·   E interact   ·   F role ability"

func _update_hud() -> void:
	if hud_timer == null or not is_instance_valid(hud_timer):
		return
	var seconds := float(match_state.get("time", 600.0))
	hud_timer.text = "%s  //  LAB CONTAINMENT" % _format_time(seconds)
	var power_text := "ONLINE" if match_state.get("power", false) else "Engineer: restore reactor"
	if not match_state.get("power", false) and float(match_state.get("repair_progress", 0.0)) > 0.0:
		power_text = "repairing… %d%%" % int((1.0 - float(match_state["repair_progress"]) / 5.0) * 100.0)
	var security_text := "BREACHED" if match_state.get("security", false) else "Hacker: breach doors"
	if not match_state.get("security", false) and float(match_state.get("hack_progress", 0.0)) > 0.0:
		security_text = "breaching… %d%%" % int((1.0 - float(match_state["hack_progress"]) / 4.0) * 100.0)
	var clue_count := 0
	for found in match_state.get("clues", [false, false, false]):
		if found:
			clue_count += 1
	var code_text := "OPEN" if match_state.get("code_solved", false) else "%d / 3 clues" % clue_count
	hud_objectives.text = "REACTOR  %s\nSECURITY  %s\nARCHIVE  %s\nEVACUATION  %s" % [power_text, security_text, code_text, "READY" if _is_exit_ready() else "LOCKED"]
	var actor = _local_actor()
	if actor != null:
		var role_color: Color = ROLE_COLORS.get(actor.role, Color.WHITE)
		hud_role.add_theme_color_override("font_color", role_color)
		var cooldown := "READY" if actor.ability_cooldown <= 0.0 else "%.1fs" % actor.ability_cooldown
		var hearts := "♥".repeat(maxi(0, actor.health)) + "♡".repeat(maxi(0, 3 - actor.health))
		hud_role.text = "%s  ·  %s   [F %s]   %s" % [actor.role.to_upper(), hearts, cooldown, "DOWN" if actor.down else ""]
	var count := 0
	var inside := 0
	for peer_actor in actors.values():
		if peer_actor.connected:
			count += 1
			if peer_actor.in_exit:
				inside += 1
	hud_team.text = "CREW   %d / 4   ·   EVAC %d / %d   ·   %s" % [count, inside, count, "HOST" if multiplayer.is_server() else "CONNECTED"]

func _format_time(seconds: float) -> String:
	var whole := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [floori(float(whole) / 60.0), whole % 60]

func _all_clues_found() -> bool:
	for found in match_state.get("clues", [false, false, false]):
		if not found:
			return false
	return true

func _set_message(text: String) -> void:
	match_state["message"] = text

func _leave_lobby() -> void:
	multiplayer.multiplayer_peer = null
	for actor in actors.values():
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()
	lobby_peers.clear()
	game_started = false
	is_host = false
	_show_menu("")

