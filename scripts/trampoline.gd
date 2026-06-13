# res://scripts/trampoline.gd
# Kit Out — Trampoline (Phase 3, obstacle #4)
#
# A bouncy pad that launches the player upward, proportional to how hard they
# fell AND how close to centre they hit. There is no solid surface — you cannot
# stand on it, only bounce. The signature "boing" of a Crash Course course.
#
# WHY POLL INSTEAD OF body_entered: reading velocity.y on the entered signal is
# unreliable — the signal fires on whatever physics frame the overlap registers,
# which may be after the player has already started decelerating, giving an
# inconsistent bounce. Instead we track the player's PEAK fall speed every frame
# while they're in the zone and launch from that. Consistent every time.
#
# DESIGN NOTES:
# • bounce_multiplier scales fall speed → launch speed. 1.0 = perfect rebound;
#   >1.0 gains energy each bounce (a 1.15 super-bounce ramps you higher).
# • centre_bonus adds extra launch for hitting the middle of the pad. A dead-
#   centre hit gets the full bonus; the pad edges get none. Encourages aiming.
# • No solid body — the player falls THROUGH if somehow moving up, and can never
#   rest on top. The bounce always fires while falling.

class_name Trampoline
extends Node3D


## Minimum upward launch, used for a gentle landing.
@export var min_bounce: float        = 18.0
## Incoming fall speed converted back into upward speed.
@export var bounce_multiplier: float = 1.1
## Extra launch velocity for a dead-centre hit, fading to 0 at the pad edges.
@export var centre_bonus: float      = 12.0
## Hard ceiling so a huge fall can't fling the player offscreen.
@export var max_bounce: float        = 75.0
## Fraction of horizontal speed kept through the bounce (0 = vertical, 1 = all).
@export_range(0.0, 1.0, 0.05) var horizontal_keep: float = 1.0
## Minimum seconds between launches — stops double-triggering on one contact.
@export var bounce_cooldown: float   = 0.2
## Half-width of the pad in X, for the centre-proximity calc. Match the pad mesh.
@export var pad_half_width: float    = 2.0
## The Area3D just above the pad surface. Assign in the Inspector.
@export var bounce_zone: Area3D

@onready var _pad: Node3D = $Pad

var _cooldown: float    = 0.0
var _squash_t: float    = 0.0
var _peak_fall: float   = 0.0   # Largest downward speed seen this overlap


func _ready() -> void:
	if bounce_zone:
		# Poll overlaps each frame; only need the signal to reset peak tracking
		bounce_zone.body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_animate_pad(delta)

	if bounce_zone == null:
		return
	for body in bounce_zone.get_overlapping_bodies():
		var player := body as KitOutPlayer
		if not player:
			continue
		# Track peak fall speed (downward = negative velocity.y)
		if player.velocity.y < 0.0:
			_peak_fall = maxf(_peak_fall, -player.velocity.y)
		# Launch once cooldown allows and the player is descending/resting
		if _cooldown <= 0.0 and player.velocity.y <= 1.0:
			_launch(player)
		break


func _launch(player: KitOutPlayer) -> void:
	_cooldown  = bounce_cooldown
	_squash_t  = 1.0

	# Fall-proportional base. _peak_fall captures the true impact speed even if
	# the player decelerated by the frame the launch fires.
	var impact := maxf(_peak_fall, absf(player.velocity.y))

	# Centre proximity: 1.0 dead-centre → 0.0 at the pad edge
	var dx       := absf(player.global_position.x - global_position.x)
	var centre_t := clampf(1.0 - dx / pad_half_width, 0.0, 1.0)

	var launch := impact * bounce_multiplier + centre_bonus * centre_t
	launch = clampf(launch, min_bounce, max_bounce)

	_peak_fall = 0.0
	player.bounce(launch, horizontal_keep)


func _on_body_exited(body: Node3D) -> void:
	if body is KitOutPlayer:
		_peak_fall = 0.0


func _animate_pad(delta: float) -> void:
	if _squash_t > 0.0:
		_squash_t = maxf(_squash_t - delta * 4.0, 0.0)
		var compress := sin(_squash_t * PI)
		_pad.scale.y    = 1.0 - compress * 0.6
		_pad.position.y = -compress * 0.15
	else:
		_pad.scale.y    = 1.0
		_pad.position.y = 0.0
