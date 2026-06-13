# res://scripts/race_gate.gd
# Kit Out — Race Gate (start line / finish line)
#
# One reusable trigger that either STARTS or FINISHES the run timer, depending
# on its `mode`. Drop two into a level: a Start gate near spawn, a Finish gate
# at the end. Both report to the GameState autoload.
#
# SETUP: place and scale so the collision volume spans the full track width the
# player must pass through. Set `mode` in the Inspector.

class_name RaceGate
extends Area3D


enum Mode { START, FINISH }

## START begins the timer when the player crosses; FINISH stops and records it.
@export var mode: Mode = Mode.START
## Optional banner mesh tint isn't required — left to the scene's materials.

var _used: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask  = 2  # Player layer
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is KitOutPlayer:
		return
	match mode:
		Mode.START:
			# The start line can fire every fresh run (after a reset clears the
			# timer), but not repeatedly mid-run — GameState.start_run guards that.
			GameState.start_run()
		Mode.FINISH:
			if _used:
				return
			_used = true
			GameState.finish_run()
