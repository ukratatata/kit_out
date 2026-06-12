# res://scripts/surface_data.gd
# Kit Out — Surface Data (data-driven surface system)
#
# A designer-editable "data packet" describing how a floor type behaves.
# Create instances as .tres files (or inline in the Inspector), then add them
# to the player's "custom_surfaces" array. Floors are matched by node group.
#
# Adding a new surface (mud, sand, conveyor…) requires ZERO code changes:
# create a resource, set group_name, tune the numbers, tag the floor node.

class_name SurfaceData
extends Resource


## Node group that identifies this surface in the scene (e.g. "ice_surface").
@export var group_name: String = ""

## Ground friction while on this surface (normal ground is 80).
@export var friction: float = 80.0

## Multiplier on ground acceleration (0.15 = very slippery steering).
@export_range(0.0, 2.0, 0.05) var acceleration_mult: float = 1.0

## Multiplier on max run speed (mud or water can cap the player below normal).
@export var max_speed_mult: float = 1.0

## Downhill pull on slopes while standing/walking on this surface (not sliding).
## 0 = none (default — normal ground). 1.0 = full projected slope gravity:
## the player cannot rest on an inclined ramp and drifts downhill even idle.
@export_range(0.0, 2.0, 0.05) var slope_slip: float = 0.0
