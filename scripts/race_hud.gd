# res://scripts/race_hud.gd
# Kit Out — Race HUD
#
# Displays the live run timer, the best time, and a finish banner. Add as a
# CanvasLayer to a level (or instance race_hud.tscn). Builds its UI in code and
# listens to GameState's signals — nothing to wire in the editor.
#
# Requires the GameState autoload.

extends CanvasLayer


var _timer_label: Label
var _best_label: Label
var _finish_box: Control
var _finish_label: Label


func _ready() -> void:
	layer = 50
	_build_ui()
	GameState.run_finished.connect(_on_run_finished)
	GameState.run_started.connect(_on_run_started)
	GameState.timer_reset.connect(_on_timer_reset)
	_refresh_best()


func _process(_delta: float) -> void:
	# Live timer text. Dim while not timing so it reads as "ready" vs "running".
	_timer_label.text = _format_time(GameState.run_time)
	_timer_label.modulate.a = 1.0 if GameState.is_timing() else 0.5


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_run_started() -> void:
	_finish_box.visible = false


func _on_timer_reset() -> void:
	_finish_box.visible = false
	_refresh_best()


func _on_run_finished(time: float, is_best: bool) -> void:
	_refresh_best()
	_finish_label.text = "FINISH!\n%s%s" % [
		_format_time(time),
		"\nNew Best!" if is_best else ""
	]
	_finish_box.visible = true


# ── Helpers ───────────────────────────────────────────────────────────────────

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

	# Finish banner, centre screen (hidden until finish)
	_finish_box = CenterContainer.new()
	_finish_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finish_box.visible = false
	add_child(_finish_box)

	var panel := PanelContainer.new()
	_finish_box.add_child(panel)

	_finish_label = Label.new()
	_finish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finish_label.add_theme_font_size_override("font_size", 44)
	_finish_label.custom_minimum_size = Vector2(360, 180)
	_finish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_finish_label)
