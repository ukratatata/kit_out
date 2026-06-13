# res://scenes/player/land_dust.gd
# Kit Out — Landing Dust
# A GPUParticles3D that puffs a one-shot dust burst when the player lands.
# Attached as a child of the Player; connects to the player's `landed` signal.
#
# Burst size scales with impact speed: a gentle step barely puffs, a dive-bomb
# kicks up a big cloud. Reads the player's velocity.y at the moment of landing.

extends GPUParticles3D


## Fall speed (downward) below which no dust shows at all.
@export var min_impact: float    = 6.0
## Fall speed at which the dust reaches full size.
@export var full_impact: float   = 35.0
## Particle count at full impact (scaled down for gentle landings).
@export var max_particles: int   = 18


@onready var _player: KitOutPlayer = get_parent()


func _ready() -> void:
	emitting = false
	one_shot = true
	_player.landed.connect(_on_landed)


func _on_landed() -> void:
	var impact := absf(_player.velocity.y)
	if impact < min_impact:
		return  # Too gentle to kick up dust
	# Scale the burst with how hard they hit
	var t := clampf((impact - min_impact) / (full_impact - min_impact), 0.0, 1.0)
	amount = maxi(int(max_particles * t), 4)
	restart()       # Reset and fire the one-shot burst
	emitting = true
