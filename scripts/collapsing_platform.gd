# res://scripts/collapsing_platform.gd
# Kit Out — Collapsing Platform (Phase 3, obstacle #2)
#
# SETUP: place the scene root where the TOP SURFACE of the platform should be.
# The Body node sits at local (0,0,0), so position the root so the top of the
# 0.5-tall Body is flush with the floor level you want.
#
# FLOW: IDLE → player steps on TriggerZone → SHAKING (visual warning) →
#       FALLING (collision off, platform drops) → RESPAWNING (invisible timer)
#       → IDLE (reset, ready again).
#
# DESIGN NOTES:
# • gap_before_shake (default 0 s) delays the shake after first contact.
#   Set to 0.2–0.4 s to give slower players a fighting chance on the first run.
# • respawn_time (default 3.5 s) controls how long the gap persists. Longer =
#   riskier to wait around; shorter = players can stall and take a safer gap.
# • Platforms are most interesting in sequences: a safe solid platform followed
#   immediately by two collapses forces the player to commit to momentum.

class_name CollapsingPlatform
extends Node3D


enum State { IDLE, SHAKING, FALLING, RESPAWNING }


@export_group("Timing")
## Extra wait after first contact before shaking begins.
## 0 s = shake starts the instant the player steps on. 0.3 s gives a brief
## false sense of security — harder reads, but can feel cheap; use sparingly.
@export var gap_before_shake: float = 0.0
## Duration of the shake before the platform drops.
@export var shake_duration: float   = 0.65
## Seconds the platform is absent before it reappears.
@export var respawn_time: float     = 3.5

@export_group("Feel")
## Lateral shake offset in metres.
@export var shake_amplitude: float  = 0.07
## Oscillations per second during the shake.
@export var shake_frequency: float  = 24.0
## How far the platform falls before the respawn timer starts.
@export var fall_distance: float    = 22.0

## Area3D slab on the top surface — assign in the Inspector.
@export var trigger_area: Area3D

@onready var _body:  Node3D            = $Body
@onready var _shape: CollisionShape3D  = $Body/PlatformShape

var _state:      State  = State.IDLE
var _timer:      float  = 0.0
var _fall_vel:   float  = 0.0
var _origin:     Vector3
var _gravity:    float  = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_origin = _body.position
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
			_body.position.x = _origin.x + sin(t * shake_frequency) * shake_amplitude
			_body.position.y = _origin.y + sin(t * shake_frequency * 1.3) * shake_amplitude * 0.4
			if t >= shake_duration:
				_begin_fall()

		State.FALLING:
			_fall_vel         += _gravity * delta
			_body.position.y  -= _fall_vel * delta
			if _body.position.y < _origin.y - fall_distance:
				_begin_respawn()

		State.RESPAWNING:
			if _timer >= respawn_time:
				_reset()


func _on_body_entered(body: Node3D) -> void:
	if _state != State.IDLE or not body is KitOutPlayer:
		return
	_state = State.SHAKING
	_timer = 0.0


func _begin_fall() -> void:
	_state            = State.FALLING
	_timer            = 0.0
	_fall_vel         = 0.0
	_body.position.x  = _origin.x   # Snap lateral shake to centre before drop
	_shape.disabled   = true         # Player falls through immediately


func _begin_respawn() -> void:
	_state         = State.RESPAWNING
	_timer         = 0.0
	_body.visible  = false


func _reset() -> void:
	_body.position    = _origin
	_shape.disabled   = false
	_body.visible     = true
	_state            = State.IDLE
	_timer            = 0.0
	_fall_vel         = 0.0
