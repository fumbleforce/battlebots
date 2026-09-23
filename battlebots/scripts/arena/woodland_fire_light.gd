extends OmniLight3D
## Brazier flicker. Presentation only; the phase comes from the light position.
var _base := 0.0
var _phase := 0.0

func _ready() -> void:
	_base = light_energy
	_phase = fmod(absf(position.x * 0.37 + position.z * 0.61), TAU)

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + _phase
	light_energy = _base * (0.82 + sin(t * 9.0) * 0.08 + sin(t * 23.0 + 1.3) * 0.06 + sin(t * 4.1) * 0.04)
