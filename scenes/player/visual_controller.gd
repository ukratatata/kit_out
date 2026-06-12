extends Node

# ── Visual Feel ───────────────────────────────────────────────────────────────
@export_group("Visual Feel")
## Turning speed for the visual container rotation.
@export var visual_rotation_speed: float  = 15.0
@export var squash_on_jump: Vector3       = Vector3(0.75, 1.30, 0.75)
@export var squash_on_land: Vector3       = Vector3(1.35, 0.70, 1.35)
@export var squash_recovery_speed: float  = 12.0
## Lean angle (radians) at the start of a sprint when stamina is full.
@export var sprint_lean_base: float   = 0.05
## Extra lean added as stamina drains. At 0 stamina: total lean = base + max ≈ 14°.
@export var sprint_lean_max: float    = 0.20
## How quickly the lean settles to its target angle.
@export var sprint_lean_speed: float  = 6.0
## Seconds of standing idle before the cat turns to look at the camera.
@export var idle_look_delay: float    = 2.0

# Grab a reference to the main player script to read its state!
@onready var player: KitOutPlayer = get_parent()
@onready var visual_container: Node3D = player.visual_container
# ─────────────────────────────────────────────────────────────────────────────
# ── Visuals ───────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

func update_visuals(delta: float, input_dir: float, iframe_timer: float) -> void:
	if absf(input_dir) > 0.1:
		player._last_input_dir = input_dir

	# ── Facing rotation ───────────────────────────────────────────────────────
	if player.current_state != KitOutPlayer.PlayerState.OFF_BALANCE and player.current_state != KitOutPlayer.PlayerState.STUNNED:
		# Travel facing: Right = 270° (3π/2) | Left = 90° (π/2)
		var target_rot := 3.0 * PI / 2.0 if player._last_input_dir > 0.0 else PI / 2.0
		
		# Idle glance: after a short pause standing still, look at the camera (180°)
		if player.current_state == KitOutPlayer.PlayerState.IDLE and player._idle_timer >= idle_look_delay:
			target_rot = PI

		var current_yaw := visual_container.rotation.y
		if current_yaw < 0.0:
			current_yaw += TAU
		visual_container.rotation.y = lerp(
			current_yaw, target_rot,
			clampf(visual_rotation_speed * delta, 0.0, 1.0)
		)

	# ── Off-balance wobble / sprint lean ──────────────────────────────────────
	if player.current_state == KitOutPlayer.PlayerState.OFF_BALANCE:
		visual_container.rotation.x = sin(Time.get_ticks_msec() * 0.012) * 0.18
	elif player.current_state == KitOutPlayer.PlayerState.STUNNED:
		visual_container.rotation.x = sin(Time.get_ticks_msec() * 0.02) * 0.35
	elif player.current_state == KitOutPlayer.PlayerState.SPRINT:
		var stamina_t := player.sprint_stamina / maxf(player.sprint_stamina_max, 0.001)
		var lean_amt  := sprint_lean_base + sprint_lean_max * (1.0 - stamina_t)
		visual_container.rotation.x = lerp_angle(
			visual_container.rotation.x, -lean_amt, sprint_lean_speed * delta
		)
	else:
		visual_container.rotation.x = lerp_angle(
			visual_container.rotation.x, 0.0, 8.0 * delta
		)

	# ── Squash & stretch ──────────────────────────────────────────────────────
	visual_container.scale = visual_container.scale.lerp(
		player._visual_scale_target, squash_recovery_speed * delta
	)
	
	# Recover toward _visual_base_scale
	player._visual_scale_target = player._visual_scale_target.lerp(player._visual_base_scale, squash_recovery_speed * delta)

	# ── Foot anchoring ────────────────────────────────────────────────────────
	visual_container.position.y = (visual_container.scale.y - 1.0) * player.stand_half_height

	# ── I-Frame Blinking ──────────────────────────────────────────────────────
	if iframe_timer > 0.0:
		visual_container.visible = int(iframe_timer * 10) % 2 == 0
	else:
		visual_container.visible = true
