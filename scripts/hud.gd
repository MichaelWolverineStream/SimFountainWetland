extends CanvasLayer

## HUD built in code. It only shows data and emits intent signals; main.gd owns the game flow.

signal primary_action_pressed
signal speed_selected(ticks_per_step: int)
signal reset_pressed
signal environment_changed(season: int, wind: int, rain: bool, bloom: bool)
signal place_pump_pressed
signal place_sprayer_pressed
signal clear_fountain_pressed
signal lpm_changed(lpm: float)
signal slice_changed(enabled: bool, cell_x: int, flip: bool)
signal keep_tuning_pressed
signal new_scenario_pressed

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const WINDS := ["Calm", "Moderate", "High"]
const SPEEDS := {"Pause": 0, "1x": 1, "4x": 4, "16x": 16}
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)
const DepthProfile := preload("res://scripts/depth_profile.gd")
const GRADIENT := preload("res://assets/do_gradient.tres")

var _style: StyleBoxFlat
var _stage_label: Label
var _hint_label: Label
var _time_label: Label
var _action_button: Button
var _progress: ProgressBar
var _speed_buttons := {}
var _season: OptionButton
var _wind: OptionButton
var _rain: CheckBox
var _bloom: CheckBox
var _pump_button: Button
var _sprayer_button: Button
var _clear_button: Button
var _lpm_slider: HSlider
var _lpm_label: Label
var _fountain_label: Label
var _slice_enabled: CheckBox
var _slice_slider: HSlider
var _slice_flip: CheckBox
var _slice_label: Label
var _stat_values := {}
var _target_label: Label
var _profile: DepthProfile
var _results: PanelContainer
var _results_grid: GridContainer
var _results_verdict: Label
var _results_detail: Label
var _footer: Label


func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.07, 0.09, 0.11, 0.86)
	_style.set_corner_radius_all(6)
	_style.set_content_margin_all(10)
	_build_top_bar()
	_build_left_panel()
	_build_right_panel()
	_build_results()
	_build_footer()


# ---- Public API (called by main.gd) ----

func set_stage(title: String, hint: String, action_text: String, action_enabled: bool) -> void:
	_stage_label.text = title
	_hint_label.text = hint
	_action_button.text = action_text
	_action_button.visible = action_text != ""
	_action_button.disabled = not action_enabled


func set_controls_enabled(environment: bool, fountain: bool, speed: bool) -> void:
	for control: BaseButton in [_season, _wind, _rain, _bloom]:
		control.disabled = not environment
	for control: BaseButton in [_pump_button, _sprayer_button, _clear_button]:
		control.disabled = not fountain
	_lpm_slider.editable = fountain
	for button: Button in _speed_buttons.values():
		button.disabled = not speed


func set_speed(ticks_per_step: int) -> void:
	if _speed_buttons.has(ticks_per_step):
		(_speed_buttons[ticks_per_step] as Button).set_pressed_no_signal(true)


func set_placement_mode(mode: int) -> void:
	_pump_button.text = "Click water..." if mode == 1 else "Place pump"
	_sprayer_button.text = "Click water..." if mode == 2 else "Place sprayer"


func get_environment() -> Array:
	return [_season.selected, _wind.selected, _rain.button_pressed, _bloom.button_pressed]


func set_lpm(lpm: float) -> void:
	_lpm_slider.set_value_no_signal(lpm)
	_lpm_label.text = "Flow: %d L/min" % roundi(lpm)


func set_max_lpm(max_lpm: float) -> void:
	_lpm_slider.max_value = max_lpm


func configure_slice(min_x: int, max_x: int, value: int) -> void:
	_slice_slider.min_value = min_x
	_slice_slider.max_value = max_x
	_slice_slider.set_value_no_signal(value)
	_update_slice_label()


func set_targets(target_do: float, max_hypoxic: float, required_days: int) -> void:
	_target_label.text = "Target: 24 h mean DO >= %.1f mg/L and hypoxic <= %d%% for %d days in a row" % [target_do, roundi(max_hypoxic * 100.0), required_days]


func set_progress(done: int, total: int) -> void:
	_progress.visible = total > 0
	_progress.max_value = maxi(1, total)
	_progress.value = done


func update_time(day: int, hour: int) -> void:
	_time_label.text = "Day %d  %02d:00" % [day, hour]


func update_stats(stats: Dictionary, layers: PackedFloat32Array) -> void:
	if stats.is_empty():
		return
	_set_stat("mean", "%.2f mg/L" % stats.mean_do)
	_set_stat("range", "%.1f / %.1f" % [stats.min_do, stats.max_do])
	_set_stat("surface", "%.2f mg/L" % stats.surface_mean_do)
	_set_stat("bottom", "%.2f mg/L" % stats.bottom_mean_do)
	_set_stat("hypoxic", "%.1f %%" % (stats.hypoxic_fraction * 100.0))
	_set_stat("total", "%.1f kg" % stats.total_do_kg)
	_set_stat("rolling_mean", "%.2f mg/L" % stats.rolling_mean_do)
	_set_stat("rolling_hypoxic", "%.1f %%" % (stats.rolling_hypoxic_fraction * 100.0))
	var streak: int = stats.pass_streak_days
	_set_stat("streak", "%d day%s%s" % [streak, "" if streak == 1 else "s", "  PASS" if stats.passed else ""], GOOD if stats.passed else Color.WHITE)
	_set_stat("power", "%.2f kW" % stats.power_kw)
	_set_stat("today", "%.1f kWh" % stats.today_kwh)
	_set_stat("energy", "%.1f kWh" % stats.total_kwh)
	_profile.set_values(layers)


func update_fountain(info: Dictionary) -> void:
	if info.is_empty() or not (info.has_pump or info.has_sprayer):
		_fountain_label.text = "Place a pump in deep water and a sprayer where the spray should land."
		return
	var lines := PackedStringArray()
	lines.append("Pump: %s   Sprayer: %s" % ["placed" if info.has_pump else "-", "placed" if info.has_sprayer else "-"])
	if info.has_pump and info.has_sprayer:
		lines.append("Pipe %.1f m, head %.2f m" % [info.pipe_length_m, info.head_m])
		lines.append("Power %.2f kW (%.1f kWh/day)" % [info.power_kw, info.power_kw * 24.0])
		lines.append("Pump zone radius %.1f cells" % info.pump_zone_radius)
	_fountain_label.text = "\n".join(lines)


func show_results(data: Dictionary) -> void:
	for child in _results_grid.get_children():
		child.queue_free()
	for cell in ["", "Baseline", "Fountain"]:
		_label(_results_grid, cell).add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	_result_row("24 h mean DO", "%.2f mg/L" % data.baseline_mean_do, "%.2f mg/L" % data.mean_do)
	_result_row("Hypoxic volume", "%.1f %%" % (data.baseline_hypoxic * 100.0), "%.1f %%" % (data.hypoxic * 100.0))
	_result_row("Energy", "0 kWh/day", "%.1f kWh/day" % data.kwh_per_day)
	var passed: bool = data.passed
	_results_verdict.text = "PASS" if passed else "FAIL"
	_results_verdict.add_theme_color_override("font_color", GOOD if passed else BAD)
	var detail := PackedStringArray()
	detail.append("%d of %d required passing days." % [data.streak, data.required_days])
	if data.kwh_per_day > 0.0:
		detail.append("DO gain per kWh: %+.3f mg/L per kWh/day" % data.gain_per_kwh)
	detail.append("Passing designs are ranked by lowest kWh/day." if passed else "Try a deeper pump, a better sprayer spot or more flow.")
	var best: float = data.get("best_kwh_per_day", INF)
	if best < INF:
		detail.append("Best passing design this scenario: %.1f kWh/day" % best)
	if data.get("stale", false):
		detail.append("Baseline is stale: the environment changed after it was measured.")
	_results_detail.text = "\n".join(detail)
	_results.visible = true


func hide_results() -> void:
	_results.visible = false


func show_message(text: String, is_error := false) -> void:
	_footer.text = text
	_footer.add_theme_color_override("font_color", BAD if is_error else Color(0.85, 0.88, 0.9))


# ---- Building ----

func _build_top_bar() -> void:
	var panel := _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	_stage_label = _label(row, "")
	_stage_label.add_theme_font_size_override("font_size", 20)
	_stage_label.custom_minimum_size.x = 180
	_time_label = _label(row, "Day 0  00:00")
	_time_label.custom_minimum_size.x = 120
	var group := ButtonGroup.new()
	for text: String in SPEEDS:
		var ticks: int = SPEEDS[text]
		var button := _button(row, text, func() -> void: speed_selected.emit(ticks))
		button.toggle_mode = true
		button.button_group = group
		_speed_buttons[ticks] = button
	_button(row, "Reset", reset_pressed.emit)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(220, 0)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.visible = false
	row.add_child(_progress)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_action_button = _button(row, "", primary_action_pressed.emit)
	_action_button.add_theme_font_size_override("font_size", 18)
	_hint_label = _label(column, "")
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))


func _build_left_panel() -> void:
	var panel := _panel()
	panel.position = Vector2(8, 96)
	var box := _vbox(panel, 300)

	_title(box, "Environment")
	_season = _option(box, "Season", SEASONS, 1)
	_wind = _option(box, "Wind", WINDS, 0)
	_rain = _check(box, "Rain")
	_bloom = _check(box, "Algae bloom")
	_season.item_selected.connect(func(_index: int) -> void: _emit_environment())
	_wind.item_selected.connect(func(_index: int) -> void: _emit_environment())
	_rain.toggled.connect(func(_on: bool) -> void: _emit_environment())
	_bloom.toggled.connect(func(_on: bool) -> void: _emit_environment())

	box.add_child(HSeparator.new())
	_title(box, "Fountain")
	var row := HBoxContainer.new()
	box.add_child(row)
	_pump_button = _button(row, "Place pump", place_pump_pressed.emit)
	_sprayer_button = _button(row, "Place sprayer", place_sprayer_pressed.emit)
	_clear_button = _button(row, "Clear", clear_fountain_pressed.emit)
	_lpm_label = _label(box, "Flow: 0 L/min")
	_lpm_slider = HSlider.new()
	_lpm_slider.max_value = 3000
	_lpm_slider.step = 50
	_lpm_slider.value_changed.connect(_on_lpm_changed)
	box.add_child(_lpm_slider)
	_fountain_label = _label(box, "")
	_fountain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_fountain({})

	box.add_child(HSeparator.new())
	_title(box, "Cross-section")
	_slice_enabled = _check(box, "Slice along X")
	_slice_flip = _check(box, "Flip kept side")
	_slice_label = _label(box, "")
	_slice_slider = HSlider.new()
	_slice_slider.step = 1
	box.add_child(_slice_slider)
	_slice_enabled.toggled.connect(func(_on: bool) -> void: _emit_slice())
	_slice_flip.toggled.connect(func(_on: bool) -> void: _emit_slice())
	_slice_slider.value_changed.connect(func(_value: float) -> void: _emit_slice())


func _build_right_panel() -> void:
	var panel := _panel()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -338
	panel.offset_right = -8
	panel.offset_top = 96
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var box := _vbox(panel, 320)

	_title(box, "Dissolved oxygen")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	for entry: Array in [
		["mean", "Mean DO"], ["range", "Min / max"], ["surface", "Surface layer"], ["bottom", "Bottom cells"],
		["hypoxic", "Hypoxic volume"], ["total", "Total DO"], ["rolling_mean", "24 h mean DO"],
		["rolling_hypoxic", "24 h hypoxic"], ["streak", "Pass streak"], ["power", "Pump power"],
		["today", "Energy today"], ["energy", "Energy total"],
	]:
		_label(grid, entry[1]).add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		_stat_values[entry[0]] = _label(grid, "-")
	_target_label = _label(box, "")
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	box.add_child(HSeparator.new())
	_title(box, "Depth profile (layer mean, mg/L)")
	_profile = DepthProfile.new()
	_profile.custom_minimum_size = Vector2(320, 170)
	box.add_child(_profile)

	box.add_child(HSeparator.new())
	var legend := TextureRect.new()
	legend.texture = GRADIENT
	legend.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	legend.stretch_mode = TextureRect.STRETCH_SCALE
	legend.custom_minimum_size = Vector2(320, 16)
	box.add_child(legend)
	var ticks := HBoxContainer.new()
	box.add_child(ticks)
	for tick: Array in [["0", HORIZONTAL_ALIGNMENT_LEFT], ["7", HORIZONTAL_ALIGNMENT_CENTER], ["14 mg/L", HORIZONTAL_ALIGNMENT_RIGHT]]:
		var label := _label(ticks, tick[0])
		label.horizontal_alignment = tick[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_results() -> void:
	_results = _panel()
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results.grow_vertical = Control.GROW_DIRECTION_BOTH
	_results.visible = false
	var box := _vbox(_results, 420)
	_title(box, "Results")
	_results_verdict = _label(box, "")
	_results_verdict.add_theme_font_size_override("font_size", 36)
	_results_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_grid = GridContainer.new()
	_results_grid.columns = 3
	_results_grid.add_theme_constant_override("h_separation", 24)
	box.add_child(_results_grid)
	_results_detail = _label(box, "")
	_results_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_button(row, "Keep tuning", keep_tuning_pressed.emit)
	_button(row, "New scenario", new_scenario_pressed.emit)


func _build_footer() -> void:
	_footer = Label.new()
	add_child(_footer)
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_footer.add_theme_constant_override("outline_size", 4)
	_footer.add_theme_color_override("font_outline_color", Color.BLACK)
	show_message("RMB drag: orbit   MMB drag: pan   Wheel: zoom   Esc: cancel placement")


# ---- Helpers ----

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style)
	add_child(panel)
	return panel


func _vbox(parent: Control, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = width
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	return box


func _title(parent: Control, text: String) -> Label:
	var label := _label(parent, text)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	return label


func _label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _check(parent: Control, text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	parent.add_child(check)
	return check


func _option(parent: Control, text: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, text)
	label.custom_minimum_size.x = 80
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item)
	option.selected = selected
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _set_stat(key: String, text: String, color := Color.WHITE) -> void:
	var label: Label = _stat_values[key]
	label.text = text
	label.add_theme_color_override("font_color", color)


func _result_row(metric: String, baseline: String, fountain: String) -> void:
	_label(_results_grid, metric)
	_label(_results_grid, baseline)
	_label(_results_grid, fountain)


func _emit_environment() -> void:
	environment_changed.emit(_season.selected, _wind.selected, _rain.button_pressed, _bloom.button_pressed)


func _on_lpm_changed(value: float) -> void:
	_lpm_label.text = "Flow: %d L/min" % roundi(value)
	lpm_changed.emit(value)


func _emit_slice() -> void:
	_update_slice_label()
	slice_changed.emit(_slice_enabled.button_pressed, int(_slice_slider.value), _slice_flip.button_pressed)


func _update_slice_label() -> void:
	_slice_label.text = "Column x = %d" % int(_slice_slider.value)
