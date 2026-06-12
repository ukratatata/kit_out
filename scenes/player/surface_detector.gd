extends Node


## Designer-defined surfaces (ice, mud, sand…). Each entry matches a node
## group and overrides friction/acceleration/max speed while standing on it.
## Add elements and assign .tres files created from surface_data.gd.
@export var custom_surfaces: Array[SurfaceData] = []
## Snaps the character to slopes — eliminates the stepping/bouncing feeling on ramps.
@export var slope_snap_length: float = 0.35

# Grab a reference to the main player script
@onready var player: KitOutPlayer = get_parent()

## Returns the SurfaceData of the special surface underfoot, or null when on
## plain ground or airborne. Uses a short downward raycast instead of slide
## collisions: with gravity disabled on the floor, move_and_slide often records
## ZERO collisions even though is_on_floor() is true — a raycast always sees
## the floor regardless of physical contact pressure.
func get_surface() -> SurfaceData:
	if not player.is_on_floor() or custom_surfaces.is_empty():
		return null

	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		player.global_position,
		player.global_position + Vector3.DOWN * (player.stand_half_height + slope_snap_length + 0.9),
		player.collision_mask,
		[player.get_rid()]  # Never hit our own capsule
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
func apply_surface_slip(delta: float, surface: SurfaceData) -> void:
	# 1. Check if we have a valid surface and slip value
	if not surface or surface.slope_slip <= 0.0 or not player.is_on_floor():
		return
		
	# 2. Get the floor normal directly from the player
	var n := player.get_floor_normal()
	if absf(n.x) < 0.05:
		return  # Flat ground — nothing to slip down
		
	# 3. Apply the slip velocity
	player.velocity.x += player._gravity * player.gravity_multiplier * surface.slope_slip * n.x * n.y * delta
