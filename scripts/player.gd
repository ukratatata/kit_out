# res://scripts/player.gd
# Kit Out — Player Controller
# State machine: IDLE · RUN · SPRINT · OFF_BALANCE · JUMP · FALL · CROUCH · SLIDE · STUNNED
#
# Wall jumping : tag surfaces with the group "wall_jumpable"
# Special surfaces: create SurfaceData .tres resources, add to SurfaceDetector.custom_surfaces
# ────────────────────────────────────────────────────────────────────────────

class_name KitOutPlayer
extends CharacterBody3D


# ── Signals ──────────────────────────────────────────────────────────────────
signal state_changed(new_state: PlayerState)
signal landed        ## Connect to particle emitters, audio, etc.
signal took_damage   ## Camera auto-connects here for screen shake


# ── States ───────────────────────────────────────────────────────────────────
enum PlayerState {
	IDLE,
	RUN,
	SPRINT,
	OFF_BALANCE,
	JUMP,
	FALL,
	CROUCH,
	SLIDE,
	STUNNED,  ## Hit reaction — all controls locked until the stun timer ends
	# WALL_JUMP reserved — implemented as a direct velocity kick in JUMP/FALL
}


# ── Node References ───────────────────────────────────────────────────────────
@onready var visual_container: Node3D          = $VisualContainer
@onready var stand_collision: CollisionShape3D = $CollisionShape3D
@onready var visuals  = $VisualsController
@onready var surface  = $SurfaceDetector
@onready var hazards  = $HazardHandler
@onready var _wall_ray_left:  RayCast3D = $WallRayLeft
@onready var _wall_ray_right: RayCast3D = $WallRayRight

## Second collision shape used while crouching/sliding. Assign in the Inspector.
@export var crouch_collision: CollisionShape3D


# ── Horizontal Movement ───────────────────────────────────────────────────────
@export_group("Horizontal Movement")
@export var speed: float        = 12.0
@export var acceleration: float = 100.0

@export_group("Surface Interactions")
## Friction on plain ground that belongs to no special surface group.
@export var default_friction: float = 80.0


# ── Vertical Movement ─────────────────────────────────────────────────────────
@export_group("Vertical Movement")
@export var jump_velocity: float      = 20.0
@export var gravity_multiplier: float = 4.0
## Extra gravity bonus while falling — makes the arc snappier.
@export var fall_gravity_bonus: float = 1.3


# ── Jump Feel ─────────────────────────────────────────────────────────────────
@export_group("Jump Feel")
## Time window (seconds) after leaving a ledge where the player can still jump.
@export var coyote_time: float       = 0.13
## Time window (seconds) before landing where a jump press is remembered.
@export var jump_buffer_time: float  = 0.12
@export_group("Wall Jump")
## Wall-jump push: x = horizontal force away from wall, y = vertical force.
@export var wall_jump_force: Vector2 = Vector2(14.0, 18.0)
## Grace window (seconds) after leaving a jumpable wall where a wall jump still fires.
@export var wall_coyote_time: float = 0.15
## Maximum fall speed while pressing into a jumpable wall — the sticky wall slide.
@export var wall_slide_speed: float = 4.0
## Proximity detection range. 0.8 = 0.3 units past the capsule edge.
@export var wall_check_distance: float = 0.8
## Window after a wall jump during which jumping the same wall is penalised.
@export var same_wall_cooldown: float  = 0.8
## Vertical force multiplier for the penalised same-wall jump.
@export_range(0.0, 1.0, 0.05) var same_wall_penalty: float = 0.5


# ── Sprint & Balance ──────────────────────────────────────────────────────────
@export_group("Sprint & Balance")
@export var sprint_multiplier: float     = 1.6
## Maximum sprint stamina in seconds before the player loses balance.
@export var sprint_stamina_max: float    = 3.0
## Stamina recovered per second while not sprinting.
@export var stamina_regen_rate: float    = 1.5
## Duration of the off-balance stumble (seconds).
@export var off_balance_duration: float  = 1.2
## Fraction of normal horizontal control during the stumble (0.0 – 1.0).
@export var off_balance_control: float   = 0.3

# ── Crouch & Slide ────────────────────────────────────────────────────────────
@export_group("Crouch & Slide")
## Fraction of normal walk speed while crouched and moving (not sliding).
@export_range(0.1, 1.0, 0.05) var crouch_speed_mult: float = 0.4
## Speed burst added to velocity.x at the start of a slide.
@export var slide_boost: float         = 4.0
## Friction applied while sliding (lower = longer slide).
@export var slide_friction: float      = 18.0
## Slide ends (or becomes a crouch) when horizontal speed drops below this.
@export var slide_end_speed: float     = 3.0
## Hard cap on how long a slide can last on flat/uphill ground.
## On active downhill slopes this timer is ignored — gravity drives the slide.
@export var slide_max_duration: float  = 1.5
## Minimum time the player is locked into a slide after initiating it.
## Prevents accidental cancels when tapping crouch quickly.
@export var slide_lock_duration: float = 0.5
## Absolute speed limit during a slide. Raise to allow faster downhill runs.
## At the default of 60 you'll rarely hit it — gravity is the real limiter.
@export var slide_max_speed: float     = 60.0
## Multiplier on the physics-based slope gravity during a slide.
## 1.0 = realistic. 1.5 = arcade-boosted (default).
@export var downhill_force: float      = 1.5

@export_group("Physics Tuning")
## Half the standing capsule height (default 2.0 capsule → 1.0 here).
## Used to anchor the visual to the feet during squash. Update if you resize the capsule.
@export var stand_half_height: float  = 1.0


# ── Air Control ───────────────────────────────────────────────────────────────
@export_group("Air Control")
## Passive horizontal drag while airborne, as a fraction of ground friction.
## Low values let slide-jump momentum survive the full arc.
@export_range(0.0, 0.5, 0.01) var air_drag: float       = 0.04
## Fraction of ground acceleration available for steering mid-air.
@export_range(0.0, 1.0, 0.05) var air_control: float    = 0.45
## Friction multiplier when running while above normal run speed (post-slide bleed).
## Lower = momentum fades more slowly back to run speed.
@export_range(0.0, 1.0, 0.05) var momentum_bleed: float = 0.35


# ── Runtime ───────────────────────────────────────────────────────────────────
var current_state: PlayerState = PlayerState.FALL

var _coyote_timer: float      = 0.0
var _jump_buffer_timer: float = 0.0
var _off_balance_timer: float = 0.0
var _slide_timer: float       = 0.0
var _slide_lock_timer: float  = 0.0  # Crouch-release locked for this long after slide entry
var _idle_timer: float        = 0.0  # Time spent standing in IDLE — drives the camera glance
var _wall_coyote_timer: float    = 0.0
var _wall_coyote_normal_x: float = 0.0  # Wall normal sign captured for the coyote window
var _last_wall_jump_dir: float   = 0.0  # Normal sign of the last wall jumped — blocks same-wall re-jumps
var _same_wall_cooldown_timer: float = 0.0

var sprint_stamina: float     = 0.0

var _was_on_floor: bool       = false
var _last_input_dir: float    = 1.0  # Last non-zero input — used for idle facing
var _air_crouch: bool         = false  # True while crouching mid-air (tight-space pass)
var _visual_scale_target: Vector3 = Vector3.ONE
## The resting scale for the current state. ONE when upright, shorter when crouching/sliding.
## Squash events set _visual_scale_target temporarily; it lerps back to this.
var _visual_base_scale: Vector3   = Vector3.ONE

## Read by camera_follow.gd every frame. Written only from _update_camera_velocity().
## Per-state filtering means the camera never sees raw physics chaos.
var camera_velocity: Vector2 = Vector2.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	sprint_stamina = sprint_stamina_max
	floor_snap_length = surface.slope_snap_length  # Prevents stepping/bouncing on ramps
	# Velocity travels ALONG the slope surface instead of horizontally + snap.
	# Without this, fast movement on steep ramps separates the body from the
	# floor faster than the snap can reattach it — periodic contact-loss lurches.
	floor_constant_speed = true
	if crouch_collision:
		crouch_collision.disabled = true
	# Spawn looking at the camera (yaw 180°). First input turns the cat toward
	# travel direction with a clean quarter-turn instead of a 3/4 spin from yaw 0.
	visual_container.rotation.y = PI
	# Proximity wall rays — target_position driven by the export so Inspector
	# tuning of wall_check_distance updates the detection range at startup.
	_wall_ray_left.target_position  = Vector3(-wall_check_distance, 0.0, 0.0)
	_wall_ray_right.target_position = Vector3( wall_check_distance, 0.0, 0.0)
	_wall_ray_left.collision_mask   = 1  # World layer
	_wall_ray_right.collision_mask  = 1
	# If a checkpoint is active (set before a reload), spawn there instead of the
	# scene's default position. GameState is an autoload, so it survives reloads.
	if GameState.has_checkpoint():
		global_position = GameState.last_checkpoint


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	hazards.tick_timers(delta) # Let hazard handler do its own math
	_apply_gravity(delta)

	var input_dir := Input.get_axis("move_left", "move_right")
	_run_state(delta, input_dir)

	# ── DYNAMIC SNAP LENGTH ──
	# Stretch the snap raycast based on horizontal speed so high-velocity 
	# movement doesn't outrun the floor detection on steep drops.
	if is_on_floor():
		# Base snap + the exact horizontal distance traveled this frame
		floor_snap_length = surface.slope_snap_length + (absf(velocity.x) * delta)
	else:
		# Reset to base so we don't accidentally snap to ceilings/high walls while falling
		floor_snap_length = surface.slope_snap_length 
	# ─────────────────────────────

	# Belt-and-suspenders 2.5D lock (axis_lock_linear_z is also set in the scene).
	# EXCEPTION: while an off-track knock is active, Z is freed so the player can
	# be ejected from the lane; afterwards they're eased back to the play plane.
	if hazards.off_track_timer > 0.0:
		axis_lock_linear_z = false
	else:
		axis_lock_linear_z = true
		if absf(global_position.z) > 0.05:
			# Pull back toward the play plane, then kill residual Z velocity
			velocity.z = -global_position.z * 6.0
		else:
			global_position.z = 0.0
			velocity.z = 0.0
	move_and_slide()

	_update_camera_velocity(delta)
	visuals.update_visuals(delta, input_dir, hazards.iframe_timer)


# ── Timers ────────────────────────────────────────────────────────────────────

func _tick_timers(delta: float) -> void:
	# Coyote window opens the moment the player leaves the floor without jumping
	if _was_on_floor and not is_on_floor() and current_state != PlayerState.JUMP:
		_coyote_timer = coyote_time
	_was_on_floor = is_on_floor()

	_coyote_timer             = maxf(_coyote_timer             - delta, 0.0)
	_jump_buffer_timer        = maxf(_jump_buffer_timer        - delta, 0.0)
	_off_balance_timer        = maxf(_off_balance_timer        - delta, 0.0)
	_wall_coyote_timer        = maxf(_wall_coyote_timer        - delta, 0.0)
	_same_wall_cooldown_timer = maxf(_same_wall_cooldown_timer - delta, 0.0)

	if current_state == PlayerState.SLIDE:
		_slide_timer      = maxf(_slide_timer      - delta, 0.0)
		_slide_lock_timer = maxf(_slide_lock_timer - delta, 0.0)

	# Idle glance timer — counts up only while standing idle
	_idle_timer = _idle_timer + delta if current_state == PlayerState.IDLE else 0.0

	if current_state != PlayerState.SPRINT:
		sprint_stamina = minf(sprint_stamina + stamina_regen_rate * delta, sprint_stamina_max)


# ── Gravity ───────────────────────────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
	# Guard restored: without it, move_and_slide projects the leftover downward
	# velocity onto the floor plane, turning EVERY slope into a hidden downhill
	# push in all grounded states — and SLIDE double-applies its slope force
	# (explicit slope_accel + leaked gravity). If you want "ice ramps drag you
	# down while standing", the right knob is a SurfaceData property, not this.
	if is_on_floor():
		return
	var scale := gravity_multiplier * (fall_gravity_bonus if velocity.y < 0.0 else 1.0)
	velocity.y -= _gravity * scale * delta


# ── State Dispatcher ──────────────────────────────────────────────────────────

func _run_state(delta: float, input_dir: float) -> void:
	match current_state:
		PlayerState.IDLE:        _state_idle(delta, input_dir)
		PlayerState.RUN:         _state_run(delta, input_dir)
		PlayerState.SPRINT:      _state_sprint(delta, input_dir)
		PlayerState.OFF_BALANCE: _state_off_balance(delta, input_dir)
		PlayerState.JUMP:        _state_jump(delta, input_dir)
		PlayerState.FALL:        _state_fall(delta, input_dir)
		PlayerState.CROUCH:      _state_crouch(delta, input_dir)
		PlayerState.SLIDE:       _state_slide(delta, input_dir)
		PlayerState.STUNNED:     _state_stunned(delta, input_dir)


# ── Transition ────────────────────────────────────────────────────────────────

func _to(new_state: PlayerState) -> void:
	if new_state == current_state:
		return

	# ── Exit cleanup ──
	match current_state:
		PlayerState.CROUCH, PlayerState.SLIDE:
			_set_crouch(false)
			_visual_base_scale   = Vector3.ONE
			_visual_scale_target = Vector3.ONE
		PlayerState.JUMP, PlayerState.FALL:
			if _air_crouch:
				_air_crouch          = false
				_set_crouch(false)
				_visual_base_scale   = Vector3.ONE
				_visual_scale_target = Vector3.ONE

	# ── Entry setup ──
	match new_state:
		PlayerState.JUMP:
			velocity.y           = jump_velocity
			_coyote_timer        = 0.0
			_jump_buffer_timer   = 0.0
			_visual_base_scale   = Vector3.ONE  # No longer crouching once airborne
			_visual_scale_target = visuals.squash_on_jump
			# Momentum reward: slide-jumping above run speed gets a 15% horizontal boost
			if current_state == PlayerState.SLIDE and absf(velocity.x) > speed:
				velocity.x *= 1.15

		PlayerState.OFF_BALANCE:
			_off_balance_timer = off_balance_duration

		PlayerState.SLIDE:
			_set_crouch(true)
			_slide_timer      = slide_max_duration
			_slide_lock_timer = slide_lock_duration
			# Only boost when starting a slide from the ground.
			# Landing into a slide from a jump already has momentum — don't add more.
			if current_state not in [PlayerState.JUMP, PlayerState.FALL]:
				# Boost direction: travel direction when moving; from a standstill
				# on a slope, kick DOWNHILL (sign of floor_n.x) — crouching on a
				# ramp should slide down it, not toward the last input direction.
				var dir: float
				if absf(velocity.x) > 0.1:
					dir = sign(velocity.x)
				else:
					var fn := get_floor_normal()
					dir = signf(fn.x) if (is_on_floor() and absf(fn.x) > 0.05) else _last_input_dir
				velocity.x += dir * slide_boost
			_visual_base_scale   = Vector3(1.15, 0.45, 1.15)  # Low and wide
			_visual_scale_target = Vector3(1.15, 0.45, 1.15)

		PlayerState.CROUCH:
			_set_crouch(true)
			_visual_base_scale   = Vector3(1.0, 0.55, 1.0)
			_visual_scale_target = Vector3(1.0, 0.55, 1.0)

	current_state = new_state
	state_changed.emit(new_state)


# ─────────────────────────────────────────────────────────────────────────────
# ── States ───────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

func _state_idle(delta: float, input_dir: float) -> void:
	var current_surface: SurfaceData = surface.get_surface()
	var cur_fric := current_surface.friction if current_surface else default_friction
	velocity.x = move_toward(velocity.x, 0.0, cur_fric * delta)
	surface.apply_surface_slip(delta, current_surface)

	if not is_on_floor():        _to(PlayerState.FALL);   return
	if _jump_pressed():          _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("crouch"): _to(PlayerState.CROUCH); return
	if absf(input_dir) > 0.1:   _to(PlayerState.RUN)


func _state_run(delta: float, input_dir: float) -> void:
	# Read the surface underfoot once, derive everything from its data packet.
	# null = plain ground → default values. Adding new surfaces needs no code.
	var current_surface: SurfaceData = surface.get_surface()
	var cur_fric  := current_surface.friction if current_surface else default_friction
	var cur_accel := acceleration * (current_surface.acceleration_mult if current_surface else 1.0)
	var cur_speed := speed * (current_surface.max_speed_mult if current_surface else 1.0)

	if absf(input_dir) > 0.1:
		var target      := input_dir * cur_speed
		var same_dir    = sign(velocity.x) == sign(input_dir)
		var above_speed = same_dir and absf(velocity.x) > cur_speed
		if above_speed:
			# Carrying slide momentum — bleed gently with friction, don't snap to run speed
			velocity.x = move_toward(velocity.x, target, cur_fric * momentum_bleed * delta)
		else:
			velocity.x = move_toward(velocity.x, target, cur_accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, cur_fric * delta)
	surface.apply_surface_slip(delta, current_surface)

	if not is_on_floor():               _to(PlayerState.FALL);   return
	if _jump_pressed():                 _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("sprint") and absf(input_dir) > 0.1 and sprint_stamina > 0.0:
		_to(PlayerState.SPRINT);        return
	if Input.is_action_pressed("crouch"):
		if absf(velocity.x) > slide_end_speed: _to(PlayerState.SLIDE)
		else:                                   _to(PlayerState.CROUCH)
		return
	if absf(input_dir) < 0.1 and absf(velocity.x) < 0.5:
		_to(PlayerState.IDLE)


func _state_sprint(delta: float, input_dir: float) -> void:
	sprint_stamina -= delta
	if sprint_stamina <= 0.0:
		sprint_stamina = 0.0
		_to(PlayerState.OFF_BALANCE)
		return
	# Above-speed check confirmed correct (your BUG CHECK comment): entering
	# sprint with slide/trampoline momentum bleeds gently instead of snapping.
	var current_surface: SurfaceData = surface.get_surface()
	var cur_fric     := current_surface.friction if current_surface else default_friction
	var cur_accel    := acceleration * (current_surface.acceleration_mult if current_surface else 1.0)
	var sprint_speed := speed * sprint_multiplier * (current_surface.max_speed_mult if current_surface else 1.0)
	var target_speed := input_dir * sprint_speed
	var same_dir       = sign(velocity.x) == sign(input_dir)
	var is_above_speed = same_dir and absf(velocity.x) > sprint_speed
	if is_above_speed:
		# Carrying momentum from a slide or trampoline — brake softly
		velocity.x = move_toward(velocity.x, target_speed, cur_fric * momentum_bleed * delta)
	else:
		# Normal sprint acceleration (with the surface penalty if any)
		velocity.x = move_toward(velocity.x, target_speed, cur_accel * delta)
	surface.apply_surface_slip(delta, current_surface)

	if not is_on_floor():                                          _to(PlayerState.FALL);   return
	if _jump_pressed():                                            _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("crouch"):                          _to(PlayerState.SLIDE);  return
	if not Input.is_action_pressed("sprint") or absf(input_dir) < 0.1:
		_to(PlayerState.RUN)


func _state_off_balance(delta: float, input_dir: float) -> void:
	# Stumbling — heavily reduced control, rotation.x wobble handled in _update_visuals
	var current_surface: SurfaceData = surface.get_surface()
	var cur_fric := current_surface.friction if current_surface else default_friction
	velocity.x = move_toward(velocity.x, input_dir * speed * off_balance_control, cur_fric * 0.4 * delta)
	surface.apply_surface_slip(delta, current_surface)

	if not is_on_floor(): _to(PlayerState.FALL);        return
	if _jump_pressed():   _to(PlayerState.JUMP);        return  # You can still jump!
	if _off_balance_timer <= 0.0:
		_to(PlayerState.RUN if absf(input_dir) > 0.1 else PlayerState.IDLE)


func _state_jump(delta: float, input_dir: float) -> void:
	_air_move(delta, input_dir)
	_handle_air_crouch()
	_handle_wall_contact(input_dir)

	if is_on_floor(): _land(); return
	if velocity.y <= 0.0: _to(PlayerState.FALL); return

	# Wall jump while rising
	if Input.is_action_just_pressed("jump"):
		_try_wall_jump()


func _state_fall(delta: float, input_dir: float) -> void:
	_handle_air_crouch()
	_handle_wall_contact(input_dir)

	if Input.is_action_just_pressed("jump"):
		if _coyote_timer > 0.0:
			_to(PlayerState.JUMP)  # Coyote time — feel like you're still on the ledge
			return
		_jump_buffer_timer = jump_buffer_time
		_try_wall_jump()

	_air_move(delta, input_dir)
	if is_on_floor(): _land()


func _state_crouch(delta: float, input_dir: float) -> void:
	# Slow crouch-walk — tunable via crouch_speed_mult in the Inspector
	var current_surface: SurfaceData = surface.get_surface()
	var cur_fric := current_surface.friction if current_surface else default_friction
	velocity.x = move_toward(velocity.x, input_dir * speed * crouch_speed_mult, cur_fric * delta)

	if not is_on_floor():                    _to(PlayerState.FALL);   return
	if _jump_pressed():                      _to(PlayerState.JUMP);   return
	if not Input.is_action_pressed("crouch"):
		_to(PlayerState.RUN if absf(input_dir) > 0.1 else PlayerState.IDLE)
		return
	# Crouching on any slope begins a downhill slide — even from a standstill.
	# On flat ground, crouch-walking never triggers a slide; flat slides come
	# from pressing crouch while already running fast (handled in _state_run).
	var floor_n := get_floor_normal()
	if absf(floor_n.x) > 0.1:
		_to(PlayerState.SLIDE)


func _state_slide(delta: float, input_dir: float) -> void:
	# Releasing crouch exits the slide — but only after the lock window expires.
	# The lock stops accidental slides from cancelling on the same frame they start.
	if not Input.is_action_pressed("crouch") and _slide_lock_timer <= 0.0:
		_to(PlayerState.RUN if absf(velocity.x) > 0.5 else PlayerState.IDLE)
		return

	var floor_n  := get_floor_normal()
	var on_slope := is_on_floor() and absf(floor_n.x) > 0.05

	# ── Slope gravity ─────────────────────────────────────────────────────────
	# Project gravity onto the floor surface to get the physics-correct
	# acceleration along the slope.  Sign is automatic:
	#   floor_n.x > 0  →  slope drops to the right  →  pushes player rightward
	#   floor_n.x < 0  →  slope drops to the left   →  pushes player leftward
	var slope_accel := (_gravity * gravity_multiplier * downhill_force \
		* floor_n.x * floor_n.y) if on_slope else 0.0

	# ── Adaptive friction ─────────────────────────────────────────────────────
	# Going downhill (velocity and slope force share sign): gravity does the work,
	# so friction is nearly zero — the slide accelerates freely.
	# Going uphill (opposing signs): heavy braking on top of the gravity fighting you.
	# Flat ground: standard slide deceleration.
	var going_downhill := on_slope and velocity.x * slope_accel > 0.0
	var effective_friction: float
	if going_downhill:
		effective_friction = slide_friction * 0.15
	elif on_slope:
		effective_friction = slide_friction * 2.0
	else:
		effective_friction = slide_friction

	velocity.x  = move_toward(velocity.x, 0.0, effective_friction * delta)
	velocity.x += slope_accel * delta

	# Safety cap — slide_max_speed is intentionally high so downhill runs feel free
	velocity.x = clampf(velocity.x, -slide_max_speed, slide_max_speed)

	if not is_on_floor():   _to(PlayerState.FALL);  return
	if _jump_pressed():     _to(PlayerState.JUMP);  return

	# Timer ends flat slides; on a slope the slide never self-ends — slope
	# gravity reverses uphill momentum and carries you back downhill. Exits on
	# a slope: stand up (release crouch), jump, or leave the floor.
	var timed_out := not going_downhill and _slide_timer <= 0.0
	if (timed_out or absf(velocity.x) < slide_end_speed) and not on_slope:
		if Input.is_action_pressed("crouch"): _to(PlayerState.CROUCH)
		else: _to(PlayerState.IDLE if absf(velocity.x) < 0.5 else PlayerState.RUN)


## Hit reaction: ALL controls locked until the stun timer expires. Gravity and
## surface physics still apply — you can be stunned mid-air (flying the
## knockback arc) or on ice (sliding helplessly). apply_hit refreshes the
## timer, so consecutive hits keep the player locked.
func _state_stunned(delta: float, _input_dir: float) -> void:
	if is_on_floor():
		var current_surface: SurfaceData = surface.get_surface()
		var cur_fric := current_surface.friction if current_surface else default_friction
		velocity.x = move_toward(velocity.x, 0.0, cur_fric * 0.5 * delta)
		surface.apply_surface_slip(delta, current_surface)

	if hazards.stun_timer > 0.0:
		return
	# Recover
	if not is_on_floor():
		_to(PlayerState.FALL)
	elif absf(velocity.x) > 0.5:
		_to(PlayerState.RUN)
	else:
		_to(PlayerState.IDLE)


# ─────────────────────────────────────────────────────────────────────────────
# ── Shared Helpers ────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

func _air_move(delta: float, input_dir: float) -> void:
	# Passive drag keeps slide-jump momentum alive through the arc.
	# Tune air_drag in the Inspector (default 0.04 = very light bleed).
	velocity.x = move_toward(velocity.x, 0.0, default_friction * air_drag * delta)

	if absf(input_dir) < 0.1:
		return  # No input: passive drag only, full momentum preserved

	var target        := input_dir * speed
	var same_dir      = sign(velocity.x) == sign(input_dir)
	var above_speed   = same_dir and absf(velocity.x) > speed

	if above_speed:
		# Pressing with momentum — don't fight built-up speed, let drag bleed it.
		return
	else:
		# Normal air steering or braking against momentum
		velocity.x = move_toward(velocity.x, target, acceleration * air_control * delta)


func _land() -> void:
	_visual_scale_target = visuals.squash_on_land
	_last_wall_jump_dir       = 0.0  # Touching the floor re-arms every wall
	_same_wall_cooldown_timer = 0.0  # Floor resets the same-wall penalty
	landed.emit()
	# Buffered jump fires immediately on touch-down
	if _jump_buffer_timer > 0.0:
		_to(PlayerState.JUMP)
	elif Input.is_action_pressed("crouch") and absf(velocity.x) > slide_end_speed:
		_to(PlayerState.SLIDE)  # Land-slide: convert air momentum into a ground slide
	elif Input.is_action_pressed("crouch"):
		_to(PlayerState.CROUCH)
	elif absf(velocity.x) > 0.5:
		_to(PlayerState.RUN)
	else:
		_to(PlayerState.IDLE)


## Unified jump check: floor, coyote, OR (for grounded states) just pressed.
func _jump_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


## Reads crouch input while airborne and toggles the crouched collision shape.
## Lets the player duck through tight overhead gaps mid-jump or mid-fall.
## JUMP and FALL states call this every frame.
func _handle_air_crouch() -> void:
	if Input.is_action_pressed("crouch"):
		if not _air_crouch:
			_air_crouch          = true
			_set_crouch(true)
			_visual_base_scale   = Vector3(1.0, 0.55, 1.0)
			_visual_scale_target = Vector3(1.0, 0.55, 1.0)
	elif _air_crouch:
		_air_crouch          = false
		_set_crouch(false)
		_visual_base_scale   = Vector3.ONE
		_visual_scale_target = Vector3.ONE


## Proximity wall detection via RayCast3D (Celeste-style). Being NEAR a
## jumpable wall is enough — no physical contact required, which is far more
## forgiving than reading is_on_wall(). Checks both sides; right takes priority.
## Returns the wall normal's X sign (points away from the wall), or 0.0.
func _nearby_jumpable_wall_normal_x() -> float:
	for ray in [_wall_ray_right, _wall_ray_left]:
		if not ray.is_colliding():
			continue
		var n := ray.get_collision_normal()
		if absf(n.y) >= 0.5:
			continue  # Floor or steep slope — not a wall
		var body := ray.get_collider()
		if body and body.is_in_group("wall_jumpable"):
			return signf(n.x)
	return 0.0


## Called every airborne frame. Refreshes the wall-coyote window and applies
## the sticky wall slide while the player presses into a jumpable wall.
func _handle_wall_contact(input_dir: float) -> void:
	var wall_nx := _nearby_jumpable_wall_normal_x()
	if wall_nx == 0.0:
		return

	# Touching the OPPOSITE wall instantly clears the same-wall penalty so a
	# chimney of two facing walls climbs at full height.
	if _last_wall_jump_dir != 0.0 and wall_nx != _last_wall_jump_dir:
		_same_wall_cooldown_timer = 0.0

	# Any contact refreshes the coyote window — a jump press shortly after
	# leaving the wall still counts
	_wall_coyote_timer    = wall_coyote_time
	_wall_coyote_normal_x = wall_nx

	# Sticky slide: pressing INTO the wall (input opposes the normal) caps
	# fall speed, giving time to aim the jump
	if input_dir * wall_nx < -0.1 and velocity.y < -wall_slide_speed:
		velocity.y = -wall_slide_speed


func _try_wall_jump() -> void:
	# Accept proximity detection, or recent contact within the wall-coyote window
	var wall_nx := _nearby_jumpable_wall_normal_x()
	if wall_nx == 0.0 and _wall_coyote_timer > 0.0:
		wall_nx = _wall_coyote_normal_x
	if wall_nx == 0.0:
		return

	# Same-wall penalty (NOT a hard block): jumping the same wall again within
	# the cooldown window gives a reduced vertical boost. Pogo-climbing one wall
	# is punished; ping-ponging two opposing walls stays full-height because
	# touching the other wall clears the timer (see _handle_wall_contact).
	var is_same_wall := (wall_nx == _last_wall_jump_dir) and _same_wall_cooldown_timer > 0.0
	var jump_y       := wall_jump_force.y * (same_wall_penalty if is_same_wall else 1.0)

	# Push away from wall and upward — direct velocity set bypasses the normal
	# transition system since we want to stay in the JUMP state
	velocity.x                = wall_nx * wall_jump_force.x
	velocity.y                = jump_y
	_last_wall_jump_dir       = wall_nx
	_same_wall_cooldown_timer = same_wall_cooldown  # Start/restart the penalty window
	_wall_coyote_timer        = 0.0
	_coyote_timer             = 0.0
	_jump_buffer_timer        = 0.0
	_visual_scale_target      = visuals.squash_on_jump
	if current_state != PlayerState.JUMP:
		current_state = PlayerState.JUMP
		state_changed.emit(current_state)


func _set_crouch(crouching: bool) -> void:
	if stand_collision:
		stand_collision.disabled = crouching
	if crouch_collision:
		crouch_collision.disabled = not crouching


# ─────────────────────────────────────────────────────────────────────────────
# ── Camera Interface ──────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# The camera reads camera_velocity, never target.velocity directly.
# Each state sets what it *wants* the camera to see, filtering out physics chaos.

func _update_camera_velocity(delta: float) -> void:
	match current_state:
		PlayerState.OFF_BALANCE:
			# Dampen heavily — don't let the camera track the stumble.
			# Delta-scaled (≈ the old 0.08/frame at 60fps) so it behaves the
			# same at every framerate.
			camera_velocity = camera_velocity.lerp(Vector2.ZERO, minf(5.0 * delta, 1.0))

		PlayerState.SLIDE:
			# Slight exaggeration to sell the speed
			camera_velocity = Vector2(velocity.x * 1.15, velocity.y)

		_:
			camera_velocity = Vector2(velocity.x, velocity.y)


# In player.gd — a single public hook, nothing else exposed
func enter_stunned() -> void:
	_to(PlayerState.STUNNED)

# In player.gd — just delegates, no logic here
func apply_hit(knockback: Vector2) -> void:
	hazards.apply_hit(knockback)

## 3D hit variant for off-track hazards (spinning bars). The Z component ejects
## the player from the lane; the Z-recovery in _physics_process pulls them back.
func apply_hit_3d(knockback: Vector3) -> void:
	hazards.apply_hit_3d(knockback)


## Public bounce interface for trampolines/bounce pads. Friendly, not a hazard:
## sets an absolute upward velocity (consistent apex regardless of fall speed),
## optionally preserves horizontal momentum, and enters the air state cleanly.
func bounce(force: float, horizontal_keep: float = 1.0) -> void:
	velocity.y = force
	velocity.x *= horizontal_keep
	# Force into JUMP so air control, squash, and wall logic all apply normally.
	# Direct assignment (not _to) avoids re-running JUMP entry, which would
	# overwrite velocity.y with the standard jump_velocity.
	if current_state != PlayerState.JUMP and current_state != PlayerState.FALL:
		_set_crouch(false)  # In case they were crouched/sliding on the pad
		_visual_base_scale   = Vector3.ONE
	current_state = PlayerState.JUMP
	_visual_scale_target = visuals.squash_on_jump
	state_changed.emit(current_state)
