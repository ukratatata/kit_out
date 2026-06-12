# res://scenes/player/hazard_handler.gd
# Kit Out — Hazard Handler
# Manages hit reactions, stun timing, and invincibility frames (i-frames).
# Attached as a child Node of KitOutPlayer.
#
# Owns two separate timers:
#   stun_timer   — controls when the STUNNED state ends (player regains control)
#   iframe_timer — invincibility window; apply_hit is ignored while > 0
# They are intentionally separate: stun ends quickly, iframes last longer so
# the player can land, recover, and move before the next hit can connect.

extends Node


@onready var player: KitOutPlayer = get_parent()


@export_group("Stun")
## Duration of the controls-locked STUNNED state after a hit.
@export var stun_duration: float   = 0.8


@export_group("I-Frames")
## Invincibility window after a hit. Should be >= stun_duration so the player
## is never re-stunned before they've had a chance to react.
@export var iframe_duration: float = 1.2


## Time remaining in the STUNNED state. Read by _state_stunned in player.gd.
var stun_timer: float  = 0.0
## Time remaining in the i-frame window. Read by VisualController for blinking.
var iframe_timer: float = 0.0


func tick_timers(delta: float) -> void:
	stun_timer   = maxf(stun_timer   - delta, 0.0)
	iframe_timer = maxf(iframe_timer - delta, 0.0)


## True while the player is invincible. Checked at the top of apply_hit.
func is_invincible() -> bool:
	return iframe_timer > 0.0


## Starts (or refreshes) the stun window.
func start_stun() -> void:
	stun_timer = stun_duration


## Starts (or refreshes) the i-frame window.
func start_iframes() -> void:
	iframe_timer = iframe_duration
