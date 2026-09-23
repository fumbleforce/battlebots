extends SceneTree
## Detached jump force bar states; authored views are not gameplay evidence.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var gauge := HudJumpGauge.new()
	root.add_child(gauge)
	await process_frame
	check(not gauge.visible and gauge.size.y > 0.0, "idle gauge is hidden but has height")
	var bot := BotView.new()
	gauge.render(bot, true)
	check(not gauge.visible, "no charge and no cooldown hides the bar")
	bot.jump_charge_fraction = 0.5
	gauge.render(bot, true)
	check(gauge.visible and is_equal_approx(gauge.charge, 0.5), "holding Jump shows the charging bar")
	gauge.render(bot, false)
	check(not gauge.visible, "round lock hides the bar")
	bot.jump_charge_fraction = 1.7
	gauge.render(bot, true)
	check(gauge.charge == 1.0, "charge is clamped to full")
	bot.jump_charge_fraction = NAN
	bot.jump_cooldown = 2.5
	gauge.render(bot, true)
	check(gauge.visible and gauge.charge == 0.0 and gauge.cooldown == 2.5, "cooldown keeps the bar visible and rejects invalid charge")
	bot.eliminated = true
	gauge.render(bot, true)
	check(not gauge.visible, "eliminated bots hide the bar")
	gauge.render(null, true)
	check(not gauge.visible, "missing view hides the bar")
	gauge.apply_accessibility(1.5, Color.RED, true)
	check(gauge.size.y > 26.0 and gauge.accent == Color.RED, "large text grows the bar and applies the palette accent")
	await process_frame
	if failures == 0:
		print("JUMP GAUGE PASS")
	quit(failures)
