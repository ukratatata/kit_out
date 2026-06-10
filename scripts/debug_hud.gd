# res://scripts/debug_hud.gd
# Speed / state overlay for playtesting. Remove or hide before shipping.
#
# SETUP (takes 30 seconds):
#   1. In your test level, add a CanvasLayer node as a direct child of the scene root.
#   2. Attach this script to it.
#   3. In the Inspector, drag the Player node into the `player` export slot.
#   Done. The overlay appears in the top-left corner during play.
# ─────────────────────────────────────────────────────────────────────────────

extends CanvasLayer

## The player node to read from. Assign in the Inspector.
@export var player: KitOutPlayer

var _label: Label


func _ready() -> void:
	layer = 127  # Draw on top of everything

	_label = Label.new()
	_label.name                 = "DebugLabel"
	_label.position             = Vector2(12, 12)
	_label.custom_minimum_size  = Vector2(200, 0)

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.0, 0.0, 0.0, 0.62)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left        = 10
	style.content_margin_right       = 10
	style.content_margin_top         = 7
	style.content_margin_bottom      = 7

	_label.add_theme_stylebox_override("normal", style)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)

	add_child(_label)


func _process(_delta: float) -> void:
	if not player:
		_label.text = "⚠  player not assigned"
		return

	var h_spd       := absf(player.velocity.x)
	var v_spd       := player.velocity.y
	var state_name  := _state_str(player.current_state)
	var stamina_pct := int(player.sprint_stamina / maxf(player.sprint_stamina_max, 0.001) * 100.0)
	var stamina_bar := _bar(stamina_pct, 10)

	_label.text = (
		"h-spd   %.1f u/s\nv-spd  %+.1f u/s\nstate   %s\nstamina %s %d%%"
		% [h_spd, v_spd, state_name, stamina_bar, stamina_pct]
	)

	# White at normal speed → orange when carrying slide/sprint momentum
	var col := Color.WHITE if h_spd <= player.speed else Color(1.0, 0.55, 0.15)
	_label.add_theme_color_override("font_color", col)


# Returns the PlayerState enum value as a readable name string.
func _state_str(state: KitOutPlayer.PlayerState) -> String:
	var keys := KitOutPlayer.PlayerState.keys()
	var idx  := int(state)
	return keys[idx] if idx >= 0 and idx < keys.size() else str(idx)


# Renders a compact text progress bar: e.g. _bar(70, 10) → "[███████   ]"
func _bar(pct: int, width: int) -> String:
	var filled := int(pct / 100.0 * width)
	return "[" + "█".repeat(filled) + " ".repeat(width - filled) + "]"
