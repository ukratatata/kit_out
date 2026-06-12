# res://scripts/player.gd
# Kit Out — Player Controller
# State machine: IDLE · RUN · SPRINT · OFF_BALANCE · JUMP · FALL · CROUCH · SLIDE
#
# Wall jumping: tag surfaces with the group "wall_jumpable" in the scene
# Special surfaces (ice, mud…): create SurfaceData resources (.tres) and add
#   them to the "custom_surfaces" array — floors are matched by node group.
# ────────────────────────────────────────────────────────────────────────────

class_name KitOutPlayer
extends CharacterBody3D


# ── Signals ──────────────────────────────────────────────────────────────────
signal state_changed(new_state: PlayerState)
signal landed        ## Connect to particle emitters, audio, etc.
signal took_damage   ## Camera connects here to trigger screen shake


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
	# WALL_JUMP reserved — implemented as a direct velocity kick in JUMP/FALL
}


# ── Node References ───────────────────────────────────────────────────────────
@onready var visual_container: Node3D       = $VisualContainer
@onready var stand_collision: CollisionShape3D = $CollisionShape3D

## Second collision shape used while crouching/sliding. Assign in the Inspector.
@export var crouch_collision: CollisionShape3D


# ── Horizontal Movement ───────────────────────────────────────────────────────
@export_group("Horizontal Movement")
@export var speed: float        = 12.0
@export var acceleration: float = 100.0

@export_group("Surface Interactions")
## Friction on plain ground that belongs to no special surface group.
@export var default_friction: float = 80.0
## Designer-defined surfaces (ice, mud, sand…). Each entry matches a node
## group and overrides friction/acceleration/max speed while standing on it.
## Add elements and assign .tres files created from surface_data.gd.
@export var custom_surfaces: Array[SurfaceData] = []


# ── Vertical Movement ─────────────────────────────────────────────────────────
@export_group("Vertical Movement")
@export var jump_velocity: float        = 20.0
@export var gravity_multiplier: float   = 4.0
## Extra gravity multiplier applied only while falling — makes the arc snappier.
@export var fall_gravity_bonus: float   = 1.3


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
## Snaps the character to slopes — eliminates the stepping/bouncing feeling on ramps.
@export var slope_snap_length: float = 0.35
## Half the standing capsule height (default 2.0 capsule → 1.0 here).
## Used to anchor the visual to the feet during squash. Update if you resize the capsule.
@export var stand_half_height: float  = 1.0

@export_group("Air Control")
## Passive horizontal drag while airborne, as a fraction of ground friction.
## Low values let slide-jump momentum survive the full arc.
@export_range(0.0, 0.5, 0.01) var air_drag: float       = 0.04
## Fraction of ground acceleration available for steering mid-air.
@export_range(0.0, 1.0, 0.05) var air_control: float    = 0.45
## Friction multiplier when running while above normal run speed (post-slide bleed).
## Lower = momentum fades more slowly back to run speed.
@export_range(0.0, 1.0, 0.05) var momentum_bleed: float = 0.35


# ── Visual Feel ───────────────────────────────────────────────────────────────
@export_group("Visual Feel")
## Turning speed for the visual container rotation.
@export var visual_rotation_speed: float  = 15.0
@export var squash_on_jump: Vector3       = Vector3(0.75, 1.30, 0.75)
@export var squash_on_land: Vector3       = Vector3(1.35, 0.70, 1.35)
@export var squash_recovery_speed: float  = 12.0
## Lean angle (radians) at the start of a sprint when stamina is full — subtle but present.
@export var sprint_lean_base: float   = 0.05
## Extra lean added as stamina drains. At 0 stamina: total lean = base + max ≈ 14°.
@export var sprint_lean_max: float    = 0.20
## How quickly the lean settles to its target angle.
@export var sprint_lean_speed: float  = 6.0
## Seconds of standing idle before the cat turns to look at the camera.
@export var idle_look_delay: float    = 2.0


# ── Runtime Variables ─────────────────────────────────────────────────────────
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
var _stumble_on_land: bool       = false  # Set by apply_hit: play OFF_BALANCE on touchdown

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
	floor_snap_length = slope_snap_length  # Prevents stepping/bouncing on ramps
	if crouch_collision:
		crouch_collision.disabled = true
	# Spawn looking at the camera (yaw 180°). First input turns the cat toward
	# travel direction with a clean quarter-turn instead of a 3/4 spin from yaw 0.
	visual_container.rotation.y = PI


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_apply_gravity(delta)

	var input_dir := Input.get_axis("move_left", "move_right")
	_run_state(delta, input_dir)

	# Belt-and-suspenders 2.5D lock (axis_lock_linear_z is also set in the scene)
	velocity.z = 0.0
	move_and_slide()

	_update_camera_velocity(delta)
	_update_visuals(delta, input_dir)


# ── Timers ────────────────────────────────────────────────────────────────────

func _tick_timers(delta: float) -> void:
	# Coyote window opens the moment the player leaves the floor without jumping
	if _was_on_floor and not is_on_floor() and current_state != PlayerState.JUMP:
		_coyote_timer = coyote_time
	_was_on_floor = is_on_floor()

	_coyote_timer      = maxf(_coyote_timer      - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer  - delta, 0.0)
	_off_balance_timer = maxf(_off_balance_timer  - delta, 0.0)
	_wall_coyote_timer = maxf(_wall_coyote_timer  - delta, 0.0)

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
			_visual_scale_target = squash_on_jump

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
	var surface := _get_surface()
	var cur_fric := surface.friction if surface else default_friction
	velocity.x = move_toward(velocity.x, 0.0, cur_fric * delta)
	_apply_surface_slip(delta, surface)

	if not is_on_floor():        _to(PlayerState.FALL);   return
	if _jump_pressed():          _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("crouch"): _to(PlayerState.CROUCH); return
	if absf(input_dir) > 0.1:   _to(PlayerState.RUN)


func _state_run(delta: float, input_dir: float) -> void:
	# Read the surface underfoot once, derive everything from its data packet.
	# null = plain ground → default values. Adding new surfaces needs no code.
	var surface := _get_surface()
	var cur_fric  := surface.friction if surface else default_friction
	var cur_accel := acceleration * (surface.acceleration_mult if surface else 1.0)
	var cur_speed := speed * (surface.max_speed_mult if surface else 1.0)

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
	_apply_surface_slip(delta, surface)

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
	var surface := _get_surface()
	var cur_fric     := surface.friction if surface else default_friction
	var cur_accel    := acceleration * (surface.acceleration_mult if surface else 1.0)
	var sprint_speed := speed * sprint_multiplier * (surface.max_speed_mult if surface else 1.0)
	var target_speed := input_dir * sprint_speed
	var same_dir       = sign(velocity.x) == sign(input_dir)
	var is_above_speed = same_dir and absf(velocity.x) > sprint_speed
	if is_above_speed:
		# Carrying momentum from a slide or trampoline — brake softly
		velocity.x = move_toward(velocity.x, target_speed, cur_fric * momentum_bleed * delta)
	else:
		# Normal sprint acceleration (with the surface penalty if any)
		velocity.x = move_toward(velocity.x, target_speed, cur_accel * delta)
	_apply_surface_slip(delta, surface)

	if not is_on_floor():                                          _to(PlayerState.FALL);   return
	if _jump_pressed():                                            _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("crouch"):                          _to(PlayerState.SLIDE);  return
	if not Input.is_action_pressed("sprint") or absf(input_dir) < 0.1:
		_to(PlayerState.RUN)


func _state_off_balance(delta: float, input_dir: float) -> void:
	# Stumbling — heavily reduced control, rotation.x wobble handled in _update_visuals
	var surface := _get_surface()
	var cur_fric := surface.friction if surface else default_friction
	velocity.x = move_toward(velocity.x, input_dir * speed * off_balance_control, cur_fric * 0.4 * delta)
	_apply_surface_slip(delta, surface)

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
	var surface := _get_surface()
	var cur_fric := surface.friction if surface else default_friction
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
	_visual_scale_target = squash_on_land
	landed.emit()
	_last_wall_jump_dir = 0.0  # Touching the floor re-arms every wall
	# A pending hit-stagger beats everything: landing from a knockback arc
	# plays the stumble and eats any buffered jump — no instant recovery.
	if _stumble_on_land:
		_stumble_on_land   = false
		_jump_buffer_timer = 0.0
		_to(PlayerState.OFF_BALANCE)
	# Buffered jump fires immediately on touch-down
	elif _jump_buffer_timer > 0.0:
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


## Public hit interface for hazards (hammers, projectiles, traps…).
## Sets knockback velocity, fires the took_damage signal (camera shake
## auto-connects to it), and staggers the player: grounded horizontal hits
## enter OFF_BALANCE; launched hits go to FALL so air physics handles the arc.
## State exit cleanup runs automatically — a hit during a slide restores the
## standing collision shape, a hit mid-air-crouch resets it, etc.
func apply_hit(knockback: Vector2) -> void:
	velocity.x = knockback.x
	velocity.y = knockback.y
	took_damage.emit()
	if is_on_floor() and knockback.y <= 0.0:
		_to(PlayerState.OFF_BALANCE)
	else:
		# Launched: fly the knockback arc in FALL, then stumble on touchdown
		_stumble_on_land = true
		_to(PlayerState.FALL)


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


## Returns the X sign of the normal of a jumpable wall the player is touching,
## or 0.0 if not touching one. Scans all contacts — robust against simultaneous
## floor + wall contact.
func _touching_jumpable_wall_normal_x() -> float:
	if not is_on_wall():
		return 0.0
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.5:
			continue  # Floor or ceiling contact — not a wall
		var body := col.get_collider()
		if body and body.is_in_group("wall_jumpable"):
			return signf(n.x)
	return 0.0


## Called every airborne frame. Refreshes the wall-coyote window and applies
## the sticky wall slide while the player presses into a jumpable wall.
func _handle_wall_contact(input_dir: float) -> void:
	var wall_nx := _touching_jumpable_wall_normal_x()
	if wall_nx == 0.0:
		return

	# Any contact refreshes the coyote window — a jump press shortly after
	# leaving the wall still counts
	_wall_coyote_timer    = wall_coyote_time
	_wall_coyote_normal_x = wall_nx

	# Sticky slide: pressing INTO the wall (input opposes the normal) caps
	# fall speed, giving time to aim the jump
	if input_dir * wall_nx < -0.1 and velocity.y < -wall_slide_speed:
		velocity.y = -wall_slide_speed


func _try_wall_jump() -> void:
	# Accept direct contact, or recent contact within the wall-coyote window
	var wall_nx := _touching_jumpable_wall_normal_x()
	if wall_nx == 0.0 and _wall_coyote_timer > 0.0:
		wall_nx = _wall_coyote_normal_x
	if wall_nx == 0.0:
		return

	# One jump per wall: the wall you just jumped from is spent until you touch
	# the floor or jump off a wall facing the other way. Ping-ponging between
	# two opposing walls works; pogo-climbing a single wall does not.
	if wall_nx == _last_wall_jump_dir:
		return

	# Push away from wall and upward — direct velocity set bypasses the normal
	# transition system since we want to stay in the JUMP state
	velocity.x           = wall_nx * wall_jump_force.x
	velocity.y           = wall_jump_force.y
	_last_wall_jump_dir  = wall_nx
	_stumble_on_land     = false  # Wall-jumping out of a knockback arc = clean recovery
	_wall_coyote_timer   = 0.0
	_coyote_timer        = 0.0
	_jump_buffer_timer   = 0.0
	_visual_scale_target = squash_on_jump
	if current_state != PlayerState.JUMP:
		current_state = PlayerState.JUMP
		state_changed.emit(current_state)


## Returns the SurfaceData of the special surface underfoot, or null when on
## plain ground or airborne. Uses a short downward raycast instead of slide
## collisions: with gravity disabled on the floor, move_and_slide often records
## ZERO collisions even though is_on_floor() is true — a raycast always sees
## the floor regardless of physical contact pressure.
func _get_surface() -> SurfaceData:
	if not is_on_floor() or custom_surfaces.is_empty():
		return null

	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * (stand_half_height + slope_snap_length + 0.25),
		collision_mask,
		[get_rid()]  # Never hit our own capsule
	)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return null

	var body: Object = hit["collider"]
	for surf in custom_surfaces:
		# "surf and" guards against empty (null) Inspector array slots
		if surf and body.is_in_group(surf.group_name):
			return surf
	return null


## Downhill pull from slippery surfaces (SurfaceData.slope_slip). Lets icy
## ramps drag the player downhill even while standing still. Called by the
## grounded states right after their friction step, so surface friction is
## what resists the pull — ice (friction 8) barely resists, while a designer
## could give a high-friction surface some slip and still hold the player.
func _apply_surface_slip(delta: float, surface: SurfaceData) -> void:
	if not surface or surface.slope_slip <= 0.0 or not is_on_floor():
		return
	var n := get_floor_normal()
	if absf(n.x) < 0.05:
		return  # Flat ground — nothing to slip down
	# Same slope projection the SLIDE state uses: gravity along the surface
	velocity.x += _gravity * gravity_multiplier * surface.slope_slip * n.x * n.y * delta


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


# ─────────────────────────────────────────────────────────────────────────────
# ── Visuals ───────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

func _update_visuals(delta: float, input_dir: float) -> void:
	if absf(input_dir) > 0.1:
		_last_input_dir = input_dir

	# ── Facing rotation ───────────────────────────────────────────────────────
	# Runs every frame — not only while input is held — so turns always finish
	# after the key is released, and the idle glance can play with no input at all.
	if current_state != PlayerState.OFF_BALANCE:
		# Travel facing: Right = 270° (3π/2) | Left = 90° (π/2)
		var target_rot := 3.0 * PI / 2.0 if _last_input_dir > 0.0 else PI / 2.0
		# Idle glance: after a short pause standing still, look at the camera (180°)
		if current_state == PlayerState.IDLE and _idle_timer >= idle_look_delay:
			target_rot = PI

		# The engine reads Euler yaw in (-π, π]; normalize to [0, τ) so the plain
		# lerp stays inside the [90°, 270°] arc. Plain lerp (NOT lerp_angle) is
		# deliberate: every turn sweeps through 180°, so the cat shows its face
		# to the camera mid-turn instead of turning through its back.
		var current_yaw := visual_container.rotation.y
		if current_yaw < 0.0:
			current_yaw += TAU
		visual_container.rotation.y = lerp(
			current_yaw, target_rot,
			clampf(visual_rotation_speed * delta, 0.0, 1.0)  # Clamped — no overshoot on frame spikes
		)

	# ── Off-balance wobble / sprint lean ──────────────────────────────────────
	if current_state == PlayerState.OFF_BALANCE:
		# rotation.x tilts in the screen XY plane (world Z-axis) — visible side sway.
		visual_container.rotation.x = sin(Time.get_ticks_msec() * 0.012) * 0.18
	elif current_state == PlayerState.SPRINT:
		# Lean forward in the direction of travel using rotation.x.
		# For a −Z-facing model after the yaw above, local X = world ±Z, so
		# rotation.x tilts in the screen XY plane. Negative lean_amt = forward
		# lean for both facing directions automatically.
		var stamina_t := sprint_stamina / maxf(sprint_stamina_max, 0.001)
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
		_visual_scale_target, squash_recovery_speed * delta
	)
	# Recover toward _visual_base_scale — respects crouch/slide resting scale, not always ONE
	_visual_scale_target = _visual_scale_target.lerp(_visual_base_scale, squash_recovery_speed * delta)

	# ── Foot anchoring ────────────────────────────────────────────────────────
	# The VisualContainer is centred at y=0 (mid-capsule). Scaling in Y moves the
	# bottom away from the floor. This compensates so the feet never float or sink.
	# Formula: shift down by (1 - scale.y) * half_height, keep bottom at -half_height.
	visual_container.position.y = (visual_container.scale.y - 1.0) * stand_half_height
