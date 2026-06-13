# res://scripts/collapsing_platform.gd
# Kit Out — Collapsing Platform / Trapdoor (Phase 3, obstacle #2)
#
# Swings open like a trapdoor: the platform is hinged along its −Z edge and
# rotates downward around the X axis, dropping the player through.
#
# SETUP: place the scene root where the TOP SURFACE should be, centred on the
# track. The Hinge sits at the −Z edge; the platform extends toward +Z from it.
#
# FLOW: IDLE → player steps on TriggerZone → SHAKING (warning rattle) →
#       OPENING (hinge rotates down, player falls through) →
#       RESPAWNING (invisible) → IDLE (snaps shut, ready again).
#
# DESIGN NOTES:
# • open_angle controls how far the door swings. 90°+ guarantees the player
#   slides off; shallower angles can let a fast player scramble across.
# • A trapdoor reads more clearly than a vertical drop — the player SEES the
#   floor tilting away, which telegraphs the danger better than a sink.
# • gap_before_shake = 0 fires instantly; small positive values bait the player.

class_name CollapsingPlatform
extends Node3D


enum State { IDLE, SHAKING, OPENING, RESPAWNING }


@export_group("Timing")
## Extra wait after first contact before the warning rattle begins.
@export var gap_before_shake: float = 0.0
## Duration of the rattle before the door swings open.
@export var shake_duration: float   = 0.6
## Seconds the door stays open+absent before resetting.
@export var respawn_time: float     = 3.5

@export_group("Feel")
## How far the door swings down (degrees). 90+ guarantees a drop.
@export var open_angle: float       = 100.0
## How fast the door accelerates open (deg/sec²-ish feel).
@export var open_speed: float       = 540.0
## Rattle offset in metres during the warning shake.
@export var shake_amplitude: float  = 0.06
## Rattle oscillations per second.
@export var shake_frequency: float  = 26.0

## Area3D slab on the top surface — assign in the Inspector.
@export var trigger_area: Area3D

@onready var _hinge: Node3D = $Hinge

var _state: State = State.IDLE
var _timer: float = 0.0
var _open_deg: float = 0.0


func _ready() -> void:
	if trigger_area:
		trigger_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_timer += delta

	match _state:
		State.IDLE:
			pass

		State.SHAKING:
			if _timer < gap_before_shake:
				return
			var t := _timer - gap_before_shake
			# Rattle around the Z axis (visible tilt) without opening yet
			_hinge.rotation.z = sin(t * shake_frequency) * deg_to_rad(shake_amplitude * 10.0)
			if t >= shake_duration:
				_hinge.rotation.z = 0.0
				_state = State.OPENING
				_timer = 0.0

		State.OPENING:
			# Accelerate the swing for a satisfying "give way" feel
			_open_deg = min(_open_deg + open_speed * delta, open_angle)
			# Positive X rotation tips the +Z platform edge DOWNWARD (opens down,
			# not up). The hinge sits at the −Z edge so the far edge drops away.
			_hinge.rotation.x = deg_to_rad(_open_deg)
			if _open_deg >= open_angle:
				_state = State.RESPAWNING
				_timer = 0.0

		State.RESPAWNING:
			if _timer >= respawn_time:
				_reset()


func _on_body_entered(body: Node3D) -> void:
	if _state != State.IDLE or not body is KitOutPlayer:
		return
	_state = State.SHAKING
	_timer = 0.0


func _reset() -> void:
	# Snap shut and re-arm
	_open_deg          = 0.0
	_hinge.rotation    = Vector3.ZERO
	_state             = State.IDLE
	_timer             = 0.0
