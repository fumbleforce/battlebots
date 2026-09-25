class_name BotView
extends RefCounted
## Detached presentation snapshot. Consumers must not write state back to simulation.

var entity_id: int = 0
var pose: Transform3D = Transform3D.IDENTITY
var core_fraction: float = 1.0
var overheated := false
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
## Fitted HP of each armour area in `zones`; presentation only (HUD plate map).
var plate_max: Dictionary = {}
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
## Speedometer (presentation only): authoritative speed in the hull plane over
## the drive's normal top speed (NAN when unknown), and the top speed nitro
## reaches on the same scale (1.0 without nitro, e.g. 2.0 with it).
var speed_fraction := NAN
var nitro_speed_fraction := 1.0
## The normal top speed those fractions are measured against, in m/s.
var top_speed := 0.0
var jump_charge_fraction := 0.0
var jump_cooldown := 0.0
## Atlas roof turret: "cannon", "plasma" or empty. Yaw is chassis-relative;
## elevation reuses gun_pitch. Shots reuse the shot_sequence/last_shot fields.
var turret_kind := ""
var turret_yaw := 0.0
## Attachment model ("cannon", "plasma_quad"...) and the presentation's
## smoothed yaw/pitch for reticles; authority never reads these.
var turret_model := ""
var turret_display := Vector2.ZERO
## Replicated hold on another bot (harpoon tether, spear impalement): its
## entity id (0 = none) and the world anchor point on it.
var grip_target := 0
var grip_point := Vector3.ZERO
## Front tool pose 0..1: spear carriage lift or grinder arm raise.
var tool_pose := 0.0
## Kill-spree combo (0 = none) and whether the bot is being cooled (zone or
## post-kill boost), from data/heat_relief.json rules.
var spree := 0
var cooling := false
## How the bot was destroyed (#72): {kind, point, axis, force}, with point and
## axis in the body frame, or empty while alive or after a non-combat knockout.
## Presentation breaks the wreck to match (saw halves, railgun tunnel, blast).
var death: Dictionary = {}
