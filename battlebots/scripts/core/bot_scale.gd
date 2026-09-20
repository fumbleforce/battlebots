class_name BotScale
extends RefCounted
## Canonical hulls are now three times their original linear dimensions.
const FACTOR := 3.0
const AUTHORING_HEIGHT := 0.5

static func from_size(size: Vector3) -> float:
	return size.y / AUTHORING_HEIGHT
