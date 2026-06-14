# res://scripts/race_hud.gd
# Kit Out — Race HUD
#
# Live run timer + best time during play, and a full finish screen on
# completion (time, new-best flag, and Retry / Next / Menu buttons). Add as a
# CanvasLayer to a level. Builds its UI in code and listens to GameState's
# signals — nothing to wire in the editor.
#
# Requires the GameState autoload.

extends CanvasLayer


var _timer_label: Label
var _best_label: Label
var _finish_box: Control
var _finish_title: Label
var _finish_time: Label
var _next_button: Button


func _ready() -> void:
	layer = 50
	# Keep working while the tree is paused — the finish screen pauses the game
	# so the cursor can click the buttons without the cat still running around.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	GameState.run_finished.connect(_on_run_finished)
	GameState.run_started.connect(_on_run_started)
	GameState.timer_reset.connect(_on_timer_reset)
	_refresh_best()


func _process(_delta: float) -> void:
	_timer_label.text = _format_time(GameState.run_time)
	_timer_label.modulate.a = 1.0 if GameState.is_timing() else 0.5


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_run_started() -> void:
	_hide_finish()


func _on_timer_reset() -> void:
	_hide_finish()
	_refresh_best()


func _on_run_finished(time: float, is_best: bool) -> void:
	_refresh_best()
	_finish_title.text = "NEW BEST!" if is_best else "FINISH!"
	_finish_time.text = _format_time(time)
	# Grey out "Next level" when this is the last course
	_next_button.disabled = GameState.next_level_path() == ""
	_finish_box.visible = true
	get_tree().paused = true  # Freeze the game behind the finish screen


# ── Button actions ────────────────────────────────────────────────────────────

func _on_retry() -> void:
	get_tree().paused = false
	GameState.reset_timer()  # Keep checkpoints? No — a fresh timed run starts clean
	GameState.clear_checkpoints()
	get_tree().reload_current_scene()


func _on_next() -> void:
	var next := GameState.next_level_path()
	if next == "":
		return
	get_tree().paused = false
	GameState.start_level(next)


func _on_menu() -> void:
	get_tree().paused = false
	GameState.reset_level()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _hide_finish() -> void:
	_finish_box.visible = false


func _refresh_best() -> void:
	if GameState.best_time == INF:
		_best_label.text = "Best  --:--.--"
	else:
		_best_label.text = "Best  " + _format_time(GameState.best_time)


## mm:ss.cc
func _format_time(t: float) -> String:
	var minutes := int(t) / 60
	var seconds := int(t) % 60
	var cents   := int((t - int(t)) * 100.0)
	return "%02d:%02d.%02d" % [minutes, seconds, cents]


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Timer cluster, top-centre
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-100, 16)
	top.custom_minimum_size = Vector2(200, 0)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 40)
	top.add_child(_timer_label)

	_best_label = Label.new()
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.add_theme_font_size_override("font_size", 18)
	_best_label.modulate = Color(1, 1, 1, 0.7)
	top.add_child(_best_label)

	# ── Finish screen (hidden until finish) ──
	_finish_box = Control.new()
	_finish_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finish_box.visible = false
	add_child(_finish_box)

	# Dim backdrop
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	_finish_box.add_child(dim)

	# Centred card
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finish_box.add_child(center)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 14)
	card.custom_minimum_size = Vector2(340, 0)
	center.add_child(card)

	_finish_title = Label.new()
	_finish_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finish_title.add_theme_font_size_override("font_size", 52)
	card.add_child(_finish_title)

	_finish_time = Label.new()
	_finish_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finish_time.add_theme_font_size_override("font_size", 36)
	_finish_time.modulate = Color(1, 1, 1, 0.85)
	card.add_child(_finish_time)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	card.add_child(spacer)

	card.add_child(_make_button("Retry", _on_retry))
	_next_button = _make_button("Next Level", _on_next)
	card.add_child(_next_button)
	card.add_child(_make_button("Main Menu", _on_menu))


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(handler)
	return b
