# res://scripts/game_state.gd
# Kit Out — Global Game State (Autoload Singleton)
#
# REGISTER AS AUTOLOAD: Project Settings → Globals/Autoload
#   Path: res://scripts/game_state.gd   Name: GameState
#
# Survives get_tree().reload_current_scene(), which is what makes checkpoints
# and the race timer work across restarts.

extends Node

# ── Signals ──────────────────────────────────────────────────────────────────
signal run_started
signal run_finished(time: float, is_best: bool)
signal timer_reset


# ── Checkpoints ───────────────────────────────────────────────────────────────
## World-space respawn position of the most recent checkpoint reached.
var last_checkpoint: Vector3 = Vector3.INF
## Progress key of the active checkpoint (its X position along the track).
var checkpoint_progress: float = -INF


# ── Race Timer ────────────────────────────────────────────────────────────────
## Seconds elapsed in the current run. Live while _timing is true.
var run_time: float = 0.0
## Best completion time for this level (seconds). INF = none set yet.
var best_time: float = INF

# ── Level registry ────────────────────────────────────────────────────────────
## Ordered list of playable levels. The main menu and the "Next level" button
## both read this. Add an entry per course as you build them.
const LEVELS: Array[Dictionary] = [
	{ "name": "Cat Course 1", "path": "res://scenes/levels/cat_course_1.tscn" },
]

## Path of the level currently being played. Set by start_level() / the menu.
## Lets the finish screen know which level to retry and what comes next.
var current_level_path: String = ""

var _timing: bool = false
var _finished: bool = false


func _process(delta: float) -> void:
	if _timing:
		run_time += delta


# ── Timer control (called by StartLine / FinishLine) ──────────────────────────

## Begin timing. Called when the player crosses the start line. Idempotent —
## crossing the start again mid-run won't restart the clock.
func start_run() -> void:
	if _timing or _finished:
		return
	run_time = 0.0
	_timing  = true
	_finished = false
	run_started.emit()


## Stop timing and record the result. Returns nothing; listen to run_finished.
func finish_run() -> void:
	if not _timing or _finished:
		return
	_timing   = false
	_finished = true
	# Safety net: if the level was launched directly (F6 in the editor) rather
	# than through the menu, current_level_path is empty — fill it from the live
	# scene so "Retry"/"Next level" still work.
	if current_level_path == "" and get_tree().current_scene:
		current_level_path = get_tree().current_scene.scene_file_path
	var is_best := run_time < best_time
	if is_best:
		best_time = run_time
	run_finished.emit(run_time, is_best)


## True while the clock is running.
func is_timing() -> bool:
	return _timing


## Reset just the timer state (e.g. on a restart) without touching best_time.
func reset_timer() -> void:
	run_time  = 0.0
	_timing   = false
	_finished = false
	timer_reset.emit()


# ── Checkpoints ───────────────────────────────────────────────────────────────

func set_checkpoint(world_pos: Vector3, progress: float) -> void:
	if progress <= checkpoint_progress:
		return
	last_checkpoint     = world_pos
	checkpoint_progress = progress


func has_checkpoint() -> bool:
	return last_checkpoint != Vector3.INF


func clear_checkpoints() -> void:
	last_checkpoint     = Vector3.INF
	checkpoint_progress = -INF


## Full reset for "Restart Level": wipes checkpoints AND the timer (keeps best_time).
func reset_level() -> void:
	clear_checkpoints()
	reset_timer()


# ── Level flow ────────────────────────────────────────────────────────────────

## Loads a level cleanly: resets run state, remembers which level is active,
## and changes scene. Called by the main menu and the "Next level" button.
## best_time is per-session and per-level; switching levels clears it so each
## course tracks its own best (until we add per-level disk saves).
func start_level(path: String) -> void:
	reset_level()
	if path != current_level_path:
		best_time = INF  # New level — its own best time
	current_level_path = path
	get_tree().change_scene_to_file(path)


## Index of current_level_path in LEVELS, or -1 if not found.
func current_level_index() -> int:
	for i in LEVELS.size():
		if LEVELS[i]["path"] == current_level_path:
			return i
	return -1


## Path of the next level after the current one, or "" if this is the last.
func next_level_path() -> String:
	var idx := current_level_index()
	if idx >= 0 and idx + 1 < LEVELS.size():
		return LEVELS[idx + 1]["path"]
	return ""
