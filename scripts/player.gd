# res://scripts/player.gd
# Kit Out — Player Controller
# State machine: IDLE · RUN · SPRINT · OFF_BALANCE · JUMP · FALL · CROUCH · SLIDE
#
# ── SCENE SETUP REQUIRED ────────────────────────────────────────────────────
# The player scene needs one additional node before crouching works:
#   1. Add a second CollisionShape3D child to Player, name it "CrouchCollision"
#   2. Give it a CapsuleShape3D with radius 0.5, height 0.8 (half the standing height)
#   3. In the Inspector, tick "Disabled" on it so it starts off
#   4. Assign it to the `crouch_collision` export slot in this node's Inspector
#
# Wall jumping: tag surfaces with the group "wall_jumpable" in the scene
# Ice surfaces: tag surfaces with the group "ice_surface" in the scene
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

## See setup instructions at the top of this file.
@export var crouch_collision: CollisionShape3D


# ── Horizontal Movement ───────────────────────────────────────────────────────
@export_group("Horizontal Movement")
@export var speed: float        = 12.0
@export var acceleration: float = 100.0
@export var friction: float     = 80.0
## Used when the floor body is in the "ice_surface" group.
@export var ice_friction: float = 8.0


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
## Wall-jump push: x = horizontal force away from wall, y = vertical force.
@export var wall_jump_force: Vector2 = Vector2(14.0, 18.0)


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
## Speed burst added to velocity.x at the start of a slide.
@export var slide_boost: float         = 4.0
## Friction applied while sliding (lower = longer slide).
@export var slide_friction: float      = 18.0
## Slide ends (or becomes a crouch) when horizontal speed drops below this.
@export var slide_end_speed: float     = 3.0
## Hard cap on how long a single slide can last.
@export var slide_max_duration: float  = 1.5
## Extra acceleration added when sliding downhill on a slope.
@export var downhill_force: float      = 15.0

@export_group("Physics Tuning")
## Snaps the character to slopes — eliminates the stepping/bouncing feeling on ramps.
@export var slope_snap_length: float = 0.35
## Half the standing capsule height (default 2.0 capsule → 1.0 here).
## Used to anchor the visual to the feet during squash. Update if you resize the capsule.
@export var stand_half_height: float  = 1.0


# ── Visual Feel ───────────────────────────────────────────────────────────────
@export_group("Visual Feel")
## Turning speed for the visual container rotation (replaces the old hardcoded 0.2).
@export var visual_rotation_speed: float  = 15.0
@export var squash_on_jump: Vector3       = Vector3(0.75, 1.30, 0.75)
@export var squash_on_land: Vector3       = Vector3(1.35, 0.70, 1.35)
@export var squash_recovery_speed: float  = 12.0


# ── Runtime Variables ─────────────────────────────────────────────────────────
var current_state: PlayerState = PlayerState.FALL

var _coyote_timer: float      = 0.0
var _jump_buffer_timer: float = 0.0
var _off_balance_timer: float = 0.0
var _slide_timer: float       = 0.0

var sprint_stamina: float     = 0.0

var _was_on_floor: bool       = false
var _last_input_dir: float    = 1.0  # Last non-zero input — used for idle facing
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


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_apply_gravity(delta)

	var input_dir := Input.get_axis("move_left", "move_right")
	_run_state(delta, input_dir)

	# Belt-and-suspenders 2.5D lock (axis_lock_linear_z is also set in the scene)
	velocity.z = 0.0
	move_and_slide()

	_update_camera_velocity()
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

	if current_state == PlayerState.SLIDE:
		_slide_timer = maxf(_slide_timer - delta, 0.0)

	if current_state != PlayerState.SPRINT:
		sprint_stamina = minf(sprint_stamina + stamina_regen_rate * delta, sprint_stamina_max)


# ── Gravity ───────────────────────────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
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
			_slide_timer = slide_max_duration
			# Boost in the direction of travel (or last input if nearly stopped)
			var dir: float = sign(velocity.x) if absf(velocity.x) > 0.1 else _last_input_dir
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

func _state_idle(_delta: float, input_dir: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * _delta)

	if not is_on_floor():        _to(PlayerState.FALL);   return
	if _jump_pressed():          _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("crouch"): _to(PlayerState.CROUCH); return
	if absf(input_dir) > 0.1:   _to(PlayerState.RUN)


func _state_run(delta: float, input_dir: float) -> void:
	var cur_fric := _get_friction()
	if absf(input_dir) > 0.1:
		velocity.x = move_toward(velocity.x, input_dir * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, cur_fric * delta)

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

	velocity.x = move_toward(velocity.x, input_dir * speed * sprint_multiplier, acceleration * delta)

	if not is_on_floor():                                          _to(PlayerState.FALL);   return
	if _jump_pressed():                                            _to(PlayerState.JUMP);   return
	if Input.is_action_pressed("crouch"):                          _to(PlayerState.SLIDE);  return
	if not Input.is_action_pressed("sprint") or absf(input_dir) < 0.1:
		_to(PlayerState.RUN)


func _state_off_balance(delta: float, input_dir: float) -> void:
	# Stumbling — heavily reduced control, slight Z-wobble handled in _update_visuals
	velocity.x = move_toward(velocity.x, input_dir * speed * off_balance_control, friction * 0.4 * delta)

	if not is_on_floor(): _to(PlayerState.FALL);        return
	if _jump_pressed():   _to(PlayerState.JUMP);        return  # You can still jump!
	if _off_balance_timer <= 0.0:
		_to(PlayerState.RUN if absf(input_dir) > 0.1 else PlayerState.IDLE)


func _state_jump(delta: float, input_dir: float) -> void:
	_air_move(delta, input_dir)

	if is_on_floor(): _land(); return
	if velocity.y <= 0.0: _to(PlayerState.FALL); return

	# Wall jump while rising
	if Input.is_action_just_pressed("jump"):
		_try_wall_jump()


func _state_fall(delta: float, input_dir: float) -> void:
	if Input.is_action_just_pressed("jump"):
		if _coyote_timer > 0.0:
			_to(PlayerState.JUMP)  # Coyote time — feel like you're still on the ledge
			return
		_jump_buffer_timer = jump_buffer_time
		_try_wall_jump()

	_air_move(delta, input_dir)
	if is_on_floor(): _land()


func _state_crouch(delta: float, input_dir: float) -> void:
	# Slow movement while crouching
	velocity.x = move_toward(velocity.x, input_dir * speed * 0.5, friction * delta)

	if not is_on_floor():                    _to(PlayerState.FALL);   return
	if _jump_pressed():                      _to(PlayerState.JUMP);   return
	if not Input.is_action_pressed("crouch"):
		_to(PlayerState.RUN if absf(input_dir) > 0.1 else PlayerState.IDLE)
		return
	# Build speed while crouched → transition to slide
	if absf(velocity.x) > slide_end_speed:
		_to(PlayerState.SLIDE)


func _state_slide(delta: float, input_dir: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, slide_friction * delta)

	# Extra push on downhill slopes
	var floor_n := get_floor_normal()
	if is_on_floor() and absf(floor_n.x) > 0.05:
		velocity.x -= floor_n.x * downhill_force * delta

	if not is_on_floor():      _to(PlayerState.FALL);  return
	if _jump_pressed():        _to(PlayerState.JUMP);  return

	if _slide_timer <= 0.0 or absf(velocity.x) < slide_end_speed:
		if Input.is_action_pressed("crouch"): _to(PlayerState.CROUCH)
		else: _to(PlayerState.IDLE if absf(velocity.x) < 0.5 else PlayerState.RUN)


# ─────────────────────────────────────────────────────────────────────────────
# ── Shared Helpers ────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

func _air_move(delta: float, input_dir: float) -> void:
	if absf(input_dir) > 0.1:
		velocity.x = move_toward(velocity.x, input_dir * speed, acceleration * 0.5 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * 0.25 * delta)


func _land() -> void:
	_visual_scale_target = squash_on_land
	landed.emit()
	# Buffered jump fires immediately on touch-down
	if _jump_buffer_timer > 0.0:
		_to(PlayerState.JUMP)
	elif Input.is_action_pressed("crouch"):
		_to(PlayerState.CROUCH)
	elif absf(velocity.x) > 0.5:
		_to(PlayerState.RUN)
	else:
		_to(PlayerState.IDLE)


## Unified jump check: floor, coyote, OR (for grounded states) just pressed.
func _jump_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


func _try_wall_jump() -> void:
	if not is_on_wall():
		return
	var col := get_last_slide_collision()
	if not col:
		return
	var wall_body := col.get_collider()
	if not wall_body or not wall_body.is_in_group("wall_jumpable"):
		return
	# Push away from wall and upward — direct velocity set bypasses the normal
	# transition system since we want to stay in the JUMP state
	var wall_normal := col.get_normal()
	velocity.x          = wall_normal.x * wall_jump_force.x
	velocity.y          = wall_jump_force.y
	_coyote_timer       = 0.0
	_jump_buffer_timer  = 0.0
	_visual_scale_target = squash_on_jump
	if current_state != PlayerState.JUMP:
		current_state = PlayerState.JUMP
		state_changed.emit(current_state)


func _get_friction() -> float:
	if not is_on_floor():
		return friction * 0.25
	var col := get_last_slide_collision()
	if col:
		var body := col.get_collider()
		if body and body.is_in_group("ice_surface"):
			return ice_friction
	return friction


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

func _update_camera_velocity() -> void:
	match current_state:
		PlayerState.OFF_BALANCE:
			# Dampen heavily — don't let the camera track the stumble
			camera_velocity = camera_velocity.lerp(Vector2.ZERO, 0.08)

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

	# ── Facing rotation (was hardcoded 0.2 weight — now delta-correct) ────────
	if current_state != PlayerState.OFF_BALANCE:
		var target_rot := PI / 2.0 if _last_input_dir > 0.0 else -PI / 2.0
		visual_container.rotation.y = lerp_angle(
			visual_container.rotation.y, target_rot, visual_rotation_speed * delta
		)

	# ── Off-balance wobble ────────────────────────────────────────────────────
	if current_state == PlayerState.OFF_BALANCE:
		visual_container.rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.18
	else:
		visual_container.rotation.z = lerp_angle(
			visual_container.rotation.z, 0.0, 8.0 * delta
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
