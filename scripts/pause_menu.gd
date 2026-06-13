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


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep running while the tree is paused
	_build_ui()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		_toggle()


func _toggle() -> void:
	_paused = not _paused
	_panel.visible = _paused
	get_tree().paused = _paused


# ── Button actions ────────────────────────────────────────────────────────────

func _on_resume() -> void:
	_toggle()


func _on_restart_level() -> void:
	GameState.clear_checkpoints()       # Wipe progress — start from the top
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_restart_checkpoint() -> void:
	# Keep GameState.last_checkpoint as-is; the player reads it on _ready()
	get_tree().paused = false
	get_tree().reload_current_scene()


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

	# Centered button column
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(300, 0)
	_panel.add_child(box)
	# Offset so the box is truly centered (anchors set the pivot, not the size)
	box.position = Vector2(-150, -90)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)

	box.add_child(_make_button("Resume",            _on_resume))
	box.add_child(_make_button("Restart Level",     _on_restart_level))
	box.add_child(_make_button("From Checkpoint",   _on_restart_checkpoint))


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	return b
