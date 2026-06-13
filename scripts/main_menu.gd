# res://scripts/main_menu.gd
# Kit Out — Main Menu
#
# The game's entry scene. Title + Play + (later) level select + Quit.
# Set this as the project's main scene (Project Settings → Application → Run).
#
# Builds its UI in code so there's nothing to wire. To add levels, append to
# the LEVELS array — each entry becomes a Play button.

extends Control


## Levels offered on the menu. Add entries as you build more courses.
const LEVELS := [
	{ "name": "Cat Course 1", "path": "res://scenes/levels/cat_course_1.tscn" },
]


func _ready() -> void:
	_build_ui()


func _start_level(path: String) -> void:
	# Fresh run: clear any checkpoint/timer state from a previous play session
	GameState.reset_level()
	get_tree().change_scene_to_file(path)


func _quit() -> void:
	get_tree().quit()


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.13, 0.17)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(340, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "KIT OUT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A cat's obstacle course"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	# One Play button per level
	for level in LEVELS:
		var path: String = level["path"]
		var b := _make_button("Play  ·  " + str(level["name"]))
		b.pressed.connect(_start_level.bind(path))
		box.add_child(b)

	box.add_child(_make_button_plain("Quit", _quit))


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _make_button_plain(text: String, handler: Callable) -> Button:
	var b := _make_button(text)
	b.pressed.connect(handler)
	return b
