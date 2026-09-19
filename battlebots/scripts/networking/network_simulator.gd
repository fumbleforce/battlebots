class_name NetworkSimulator
extends RefCounted
## Opt-in deterministic test harness for unreliable input/snapshot delivery only.
## Reliable ENet control is untouched. This is not an OS/router impairment model.
var delay_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0
var duplicate := 0.0
var clock := 0.0
var pending: Array = []
var random := RandomNumberGenerator.new()
func _init() -> void:
	random.seed = 12345
func send(deliver: Callable) -> void:
	if random.randf() < loss:
		return
	var delay := maxf(0, delay_ms + random.randf_range(-jitter_ms, jitter_ms)) / 1000.0
	if delay <= 0:
		deliver.call()
	else:
		pending.append({"at":clock + delay, "call":deliver})
	if random.randf() < duplicate:
		pending.append({"at":clock + delay + 0.02, "call":deliver})
func tick(delta: float) -> void:
	clock += delta
	var ready: Array = []
	for index: int in range(pending.size() - 1, -1, -1):
		if pending[index].at <= clock:
			ready.append(pending[index])
			pending.remove_at(index)
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
	for item: Dictionary in ready:
		item.call.call()
