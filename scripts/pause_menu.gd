# res://scripts/pause_menu.gd
# Kit Out — Pause Menu
#
# Add as a CanvasLayer to your level (or instance pause_menu.tscn). Toggles on
# the "ui_pause" action (already bound to Esc / P / gamepad Select). Builds its
# UI in code so there's nothing to wire in the editor.
#
# Two restart paths:
#   • Restart Level   → clears checkpoints, reloads from the very start.
#   • From Checkpoint  → keeps the last checkpoint, reloads (player respawns there).
#
# Requires the GameState autoload to be registered.

extends CanvasLayer


var _panel: Control
var _paused: bool = false
var _first_button: Button


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep running while the tree is paused
	_build_ui()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		_toggle()
	elif _paused and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_toggle()


func _toggle() -> void:
	_paused = not _paused
	_panel.visible = _paused
	get_tree().paused = _paused
	
	if _paused and _first_button:
		_first_button.grab_focus()


# ── Button actions ────────────────────────────────────────────────────────────

func _on_resume() -> void:
	_toggle()


func _on_restart_level() -> void:
	GameState.reset_level()             # Wipe checkpoints AND timer (keeps best_time)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_restart_checkpoint() -> void:
	# Keep checkpoints; reset only the timer so the run re-times from the start
	# line. The player reads last_checkpoint on _ready().
	get_tree().paused = false
	_toggle() 
	
	# 2. Buscamos al jugador en el mundo de forma segura
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.respawn_at(GameState.last_checkpoint)
		
		# 4. ¡CRÍTICO! Matamos la inercia. Si el jugador murió cayendo a 100km/h
		# al vacío, no queremos que reaparezca en el checkpoint con esa misma velocidad.
		player.velocity = Vector3.ZERO


func _on_quit_to_menu() -> void:
	GameState.reset_level()  # Leaving a level abandons its run
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	# Dim background
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_panel.add_child(dim)

	# CenterContainer fills the screen and centres its single child reliably,
	# at any viewport size — no manual offsets that can push it off-screen.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(300, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	_first_button = _make_button("Resume", _on_resume)
	box.add_child(_first_button)
	box.add_child(_make_button("Restart Level",     _on_restart_level))
	box.add_child(_make_button("From Checkpoint",   _on_restart_checkpoint))
	box.add_child(_make_button("Quit to Menu",      _on_quit_to_menu))


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	return b
