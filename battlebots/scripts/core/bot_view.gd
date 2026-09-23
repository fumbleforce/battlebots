class_name BotView
extends RefCounted
## Detached presentation snapshot. Consumers must not write state back to simulation.

var entity_id: int = 0
var pose: Transform3D = Transform3D.IDENTITY
var core_fraction: float = 1.0
var battery_fraction: float = 1.0
var heat_fraction: float = 0.0
var weapon_charge_fraction: float = 0.0
var weapon_state: StringName = &"idle"
var recovery_available: bool = false
var eliminated: bool = false
## Additive MVP fields. Baseline/B mocks retain neutral defaults.
var owner_id: int = 0
var team: int = 0
var server_tick: int = 0
var zones: Dictionary = {}
var weapon_cooldown: float = 0.0
var recovery_cooldown: float = 0.0
var immobilized_remaining: float = 0.0
var failure_reason: String = ""
var has_auxiliary_weapon := false
var secondary_charge := 0.0
var secondary_active := false
var shot_sequence := 0
var last_shot_from := Vector3.ZERO
var last_shot_to := Vector3.ZERO
var last_shot_tick := -1
var gun_pitch := 0.0
var nitro_active := false
var jump_charge_fraction := 0.0
var jump_cooldown := 0.0
## Atlas roof turret: "cannon", "plasma" or empty. Yaw is chassis-relative;
## elevation reuses gun_pitch. Shots reuse the shot_sequence/last_shot fields.
var turret_kind := ""
var turret_yaw := 0.0
