extends CanvasLayer

## HUD built in code. It only shows data and emits intent signals; main.gd owns the game flow.
## Everything hangs off one full-screen Control that carries the theme, so the HUD follows the
## window size (canvas_items stretch) and the "UI size" setting (root content scale factor).

signal speed_selected(ticks_per_step: int)
signal reset_pressed
signal environment_changed(season: int, wind: int, rain: bool, bloom: bool)
signal set_baseline_pressed
signal compare_pressed
signal stop_pressed
signal show_report_pressed
signal make_baseline_pressed
signal add_fountain_pressed
signal move_pump_pressed
signal move_sprayer_pressed
signal remove_fountain_pressed
signal clear_fountains_pressed
signal fountain_selected(id: int)
signal lpm_changed(lpm: float)
signal slice_changed(enabled: bool, cell_x: int, flip: bool)
signal water_view_changed(nature: bool)

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const WINDS := ["Calm", "Moderate", "High"]
const SPEEDS := {"Pause": 0, "1x": 1, "4x": 4, "16x": 16}
const UI_SIZES := ["Small", "Medium", "Large", "Extra large"]
const UI_SCALES := [0.85, 1.0, 1.2, 1.4]
const SETTINGS_PATH := "user://settings.cfg"
const FONT_NAMES := ["Arial Rounded MT Bold", "Nunito", "Varela Round", "Quicksand", "Segoe UI", "Helvetica Neue", "sans-serif"]
const FONT_SIZE := 20
const SMALL_SIZE := 17
const TITLE_SIZE := 22
const STAGE_SIZE := 24
const PANEL_WIDTH := 340.0
const MARGIN := 10.0
const GAP := 10.0
const TEXT := Color(0.94, 0.96, 0.98)
const MUTED := Color(0.70, 0.78, 0.84)
const ACCENT := Color(0.55, 0.86, 1.0)
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)
const DepthProfile := preload("res://scripts/depth_profile.gd")
const ReportPanel := preload("res://scripts/report_panel.gd")
const GRADIENT := preload("res://assets/do_gradient.tres")

var _root: Control
var _top_bar: Control
var _bottom_bar: Control
var _left_scroll: ScrollContainer
var _right_scroll: ScrollContainer
var _fit_queued := false
var _legend: Control
var _view_buttons: Array[Button] = []
var _nature_view := true
var _ui_size: OptionButton
var _stage_label: Label
var _hint_label: Label
var _time_label: Label
var _baseline_button: Button
var _compare_button: Button
var _stop_button: Button
var _progress: ProgressBar
var _speed_buttons := {}
var _season: OptionButton
var _wind: OptionButton
var _rain: CheckBox
var _bloom: CheckBox
var _fountain_title: Label
var _unit_list: VBoxContainer
var _unit_group := ButtonGroup.new()
var _add_button: Button
var _remove_button: Button
var _move_pump_button: Button
var _move_sprayer_button: Button
var _clear_button: Button
var _lpm_slider: HSlider
var _lpm_label: Label
var _fountain_label: Label
var _totals_label: Label
var _fountains_enabled := true
var _can_add := true
var _has_selection := false
var _has_units := false
var _slice_enabled: CheckBox
var _slice_slider: HSlider
var _slice_flip: CheckBox
var _slice_label: Label
var _stat_values := {}
var _profile: DepthProfile
var _baseline_label: Label
var _report_button: Button
var _report: ReportPanel
var _footer: Label


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = _make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(MARGIN))
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := _vbox(margin, int(GAP))

	_build_top_bar(column)
	var middle := _hbox(column, 0)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_scroll = _side_scroll(middle)
	_spacer(middle)
	_right_scroll = _side_scroll(middle)
	_build_left_panel()
	_build_right_panel()
	_build_bottom_bar(column)
	_update_legend()
	_report = ReportPanel.new()
	_root.add_child(_report)
	_report.make_baseline_pressed.connect(make_baseline_pressed.emit)

	_root.resized.connect(_queue_fit)
	_top_bar.minimum_size_changed.connect(_queue_fit)
	_bottom_bar.minimum_size_changed.connect(_queue_fit)
	_load_settings()
	_queue_fit()


# ---- Public API (called by main.gd) ----

func set_status(title: String, hint: String) -> void:
	_stage_label.text = title
	_hint_label.text = hint
	_hint_label.visible = not hint.is_empty()


## Measuring swaps Set baseline / Compare for Stop; Compare needs a baseline.
func set_measuring(measuring: bool, has_baseline: bool) -> void:
	_baseline_button.visible = not measuring
	_compare_button.visible = not measuring
	_compare_button.disabled = not has_baseline
	_compare_button.tooltip_text = "" if has_baseline else "Set a baseline first."
	_stop_button.visible = measuring


func set_controls_enabled(environment: bool, fountain: bool, speed: bool) -> void:
	for control: BaseButton in [_season, _wind, _rain, _bloom]:
		control.disabled = not environment
	_fountains_enabled = fountain
	_update_fountain_buttons()
	for button: Button in _speed_buttons.values():
		button.disabled = not speed


func set_speed(ticks_per_step: int) -> void:
	if _speed_buttons.has(ticks_per_step):
		(_speed_buttons[ticks_per_step] as Button).set_pressed_no_signal(true)


## mode: 0 none, 1 pump, 2 sprayer. adding: placing a new unit rather than moving one.
func set_placement_mode(mode: int, unit_number := 0, adding := false) -> void:
	_add_button.set_pressed_no_signal(adding and mode != 0)
	_move_pump_button.set_pressed_no_signal(not adding and mode == 1)
	_move_sprayer_button.set_pressed_no_signal(not adding and mode == 2)
	match [mode, adding]:
		[1, true]:
			show_message("Fountain %d: click deep water to place the pump (it sits on the bottom). Esc cancels." % unit_number)
		[2, true]:
			show_message("Fountain %d: now click where the sprayer should float. Esc cancels adding it." % unit_number)
		[1, false]:
			show_message("Fountain %d: click a water column to move the pump. Esc cancels." % unit_number)
		[2, false]:
			show_message("Fountain %d: click a water column to move the sprayer. Esc cancels." % unit_number)
		_:
			show_message(_controls_hint())


func is_nature_view() -> bool:
	return _nature_view


func toggle_water_view() -> void:
	_view_buttons[0 if _nature_view else 1].button_pressed = true


func get_environment() -> Array:
	return [_season.selected, _wind.selected, _rain.button_pressed, _bloom.button_pressed]


func set_lpm(lpm: float) -> void:
	_lpm_slider.set_value_no_signal(lpm)
	_update_lpm_label()


func set_max_lpm(max_lpm: float) -> void:
	_lpm_slider.max_value = max_lpm


func configure_slice(min_x: int, max_x: int, value: int) -> void:
	_slice_slider.min_value = min_x
	_slice_slider.max_value = max_x
	_slice_slider.set_value_no_signal(value)
	_update_slice_label()


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
	_set_stat("power", "%.2f kW" % stats.power_kw)
	_set_stat("today", "%.1f kWh" % stats.today_kwh)
	_set_stat("energy", "%.1f kWh" % stats.total_kwh)
	_profile.set_values(layers)


## units: SimulationNode.GetFountains(); totals: GetFountainTotals().
func update_fountains(units: Array, selected_id: int, totals: Dictionary, max_units: int) -> void:
	_fountain_title.text = "Fountains (%d/%d)" % [units.size(), max_units]
	for child in _unit_list.get_children():
		_unit_list.remove_child(child)
		child.queue_free()
	var selected: Dictionary = {}
	for index in units.size():
		var unit: Dictionary = units[index]
		var id: int = unit.id
		var button := _button(_unit_list, _unit_text(index + 1, unit), func() -> void: fountain_selected.emit(id))
		button.toggle_mode = true
		button.button_group = _unit_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_pressed_no_signal(id == selected_id)
		if id == selected_id:
			selected = unit
			selected["number"] = index + 1
	_has_units = not units.is_empty()
	_can_add = units.size() < max_units
	_has_selection = not selected.is_empty()
	if _has_selection:
		_lpm_slider.set_value_no_signal(selected.lpm)
	_update_lpm_label()
	_update_fountain_buttons()
	_fountain_label.visible = _has_selection
	if _has_selection:
		_fountain_label.text = _unit_details(selected)
	var count: int = totals.get("count", 0)
	_totals_label.visible = count > 0
	if count > 0:
		_totals_label.text = "All fountains: %d running, %d L/min, %.1f kWh/day" % [
			totals.active, roundi(totals.total_lpm), totals.power_kw * 24.0]


## m: a measurement snapshot from main.gd, or {} when there is no baseline yet.
func set_baseline(m: Dictionary) -> void:
	if m.is_empty():
		_baseline_label.text = "No baseline yet. Pick conditions and fountains, then press Set baseline. Change something and press Compare with baseline."
		_baseline_label.add_theme_color_override("font_color", MUTED)
		return
	var lines := PackedStringArray()
	lines.append(m.environment_text)
	lines.append(m.fountain_text)
	lines.append("Mean DO %.2f mg/L, hypoxic %.0f%%" % [m.mean_do, m.hypoxic_fraction * 100.0])
	lines.append("Bottom %.2f mg/L, %.1f kWh/day" % [m.bottom_mean_do, m.kwh_per_day])
	lines.append(("Settled after %d days" if m.settled else "Not fully settled after %d days") % m.days)
	_baseline_label.text = "\n".join(lines)
	_baseline_label.add_theme_color_override("font_color", TEXT)


func set_has_report(has_report: bool) -> void:
	_report_button.visible = has_report


func show_report(baseline: Dictionary, comparison: Dictionary, hypoxia_threshold: float) -> void:
	_report.open(baseline, comparison, hypoxia_threshold)


func hide_report() -> void:
	_report.close()


func is_report_open() -> bool:
	return _report.visible


static func environment_text(environment: Array) -> String:
	var parts := PackedStringArray([SEASONS[environment[0]], "%s wind" % WINDS[environment[1]].to_lower()])
	if environment[2]:
		parts.append("rain")
	if environment[3]:
		parts.append("algae bloom")
	return ", ".join(parts)


static func fountain_summary(m: Dictionary) -> String:
	var count: int = m.fountain_count
	if count == 0:
		return "No fountains"
	return "%d fountain%s, %d L/min" % [count, "" if count == 1 else "s", roundi(m.total_lpm)]


func show_message(text: String, is_error := false) -> void:
	_footer.text = text
	_footer.add_theme_color_override("font_color", BAD if is_error else TEXT)


# ---- Building ----

func _build_top_bar(parent: Control) -> void:
	_top_bar = _panel(parent)
	var column := _vbox(_top_bar, 4)
	var row := _hbox(column, 10)
	_stage_label = _label(row, "")
	_stage_label.add_theme_font_size_override("font_size", STAGE_SIZE)
	_stage_label.add_theme_color_override("font_color", ACCENT)
	_stage_label.custom_minimum_size.x = 170
	_time_label = _label(row, "Day 0  00:00")
	_time_label.custom_minimum_size.x = 150
	var speeds := _hbox(row, 3)
	var group := ButtonGroup.new()
	for text: String in SPEEDS:
		var ticks: int = SPEEDS[text]
		var button := _button(speeds, text, func() -> void: speed_selected.emit(ticks))
		button.toggle_mode = true
		button.button_group = group
		_speed_buttons[ticks] = button
	_button(row, "Reset", reset_pressed.emit)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(220, 0)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.visible = false
	row.add_child(_progress)
	_spacer(row)
	_baseline_button = _button(row, "Set baseline", set_baseline_pressed.emit)
	_baseline_button.tooltip_text = "Measure the current settings as the reference to compare against."
	_compare_button = _button(row, "Compare with baseline", compare_pressed.emit)
	_compare_button.theme_type_variation = &"AccentButton"
	_stop_button = _button(row, "Stop", stop_pressed.emit)
	_stop_button.visible = false
	_hint_label = _label(column, "")
	_hint_label.add_theme_color_override("font_color", MUTED)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_left_panel() -> void:
	var box := _side_panel(_left_scroll)

	_title(box, "Environment")
	_season = _option(box, "Season", SEASONS, 1)
	_wind = _option(box, "Wind", WINDS, 0)
	var row := _hbox(box, 16)
	_rain = _check(row, "Rain")
	_bloom = _check(row, "Algae bloom")
	_season.item_selected.connect(func(_index: int) -> void: _emit_environment())
	_wind.item_selected.connect(func(_index: int) -> void: _emit_environment())
	_rain.toggled.connect(func(_on: bool) -> void: _emit_environment())
	_bloom.toggled.connect(func(_on: bool) -> void: _emit_environment())

	_separator(box)
	_fountain_title = _title(box, "Fountains")
	_unit_list = _vbox(box, 4)
	row = _hbox(box)
	_add_button = _button(row, "Add fountain", add_fountain_pressed.emit)
	_add_button.toggle_mode = true
	_add_button.theme_type_variation = &"AccentButton"
	_remove_button = _button(row, "Remove", remove_fountain_pressed.emit)
	_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row = _hbox(box)
	_move_pump_button = _button(row, "Move pump", move_pump_pressed.emit)
	_move_sprayer_button = _button(row, "Move sprayer", move_sprayer_pressed.emit)
	for button: Button in [_move_pump_button, _move_sprayer_button]:
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row = _hbox(box)
	_lpm_label = _label(row, "Flow: 0 L/min")
	_lpm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_button = _button(row, "Clear all", clear_fountains_pressed.emit)
	_lpm_slider = _slider(box)
	_lpm_slider.max_value = 3000
	_lpm_slider.step = 50
	_lpm_slider.value_changed.connect(_on_lpm_changed)
	_fountain_label = _label(box, "")
	_fountain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fountain_label.add_theme_font_size_override("font_size", SMALL_SIZE)
	_fountain_label.add_theme_color_override("font_color", MUTED)
	_totals_label = _label(box, "")
	_totals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_totals_label.add_theme_font_size_override("font_size", SMALL_SIZE)
	update_fountains([], -1, {}, 8)

	_separator(box)
	_title(box, "Cross-section")
	row = _hbox(box, 16)
	_slice_enabled = _check(row, "Slice along X")
	_slice_flip = _check(row, "Flip side")
	row = _hbox(box)
	_slice_label = _label(row, "")
	_slice_label.custom_minimum_size.x = 70
	_slice_slider = _slider(row)
	_slice_slider.step = 1
	_slice_enabled.toggled.connect(func(_on: bool) -> void: _emit_slice())
	_slice_flip.toggled.connect(func(_on: bool) -> void: _emit_slice())
	_slice_slider.value_changed.connect(func(_value: float) -> void: _emit_slice())

	_separator(box)
	_title(box, "View")
	row = _hbox(box)
	_label(row, "Water").custom_minimum_size.x = 90
	var group := ButtonGroup.new()
	for i in 2:
		var button := _button(row, ["Oxygen", "Nature"][i])
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_set_nature_view(i == 1))
		_view_buttons.append(button)
	_view_buttons[1].set_pressed_no_signal(true)
	_ui_size = _option(box, "UI size", UI_SIZES, 1)
	_ui_size.item_selected.connect(_on_ui_size_selected)


func _build_right_panel() -> void:
	var box := _side_panel(_right_scroll)

	_title(box, "Baseline")
	_baseline_label = _label(box, "")
	_baseline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_baseline_label.add_theme_font_size_override("font_size", SMALL_SIZE)
	_report_button = _button(box, "Show last report", show_report_pressed.emit)
	set_baseline({})
	set_has_report(false)

	_separator(box)
	_title(box, "Dissolved oxygen")
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for entry: Array in [
		["mean", "Mean DO"], ["range", "Min / max"], ["surface", "Surface layer"], ["bottom", "Bottom cells"],
		["hypoxic", "Hypoxic volume"], ["total", "Total DO"], ["rolling_mean", "24 h mean DO"],
		["rolling_hypoxic", "24 h hypoxic"], ["power", "Pump power"],
		["today", "Energy today"], ["energy", "Energy total"],
	]:
		_label(grid, entry[1]).add_theme_color_override("font_color", MUTED)
		var value := _label(grid, "-")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stat_values[entry[0]] = value

	_separator(box)
	_title(box, "Depth profile (mg/L)")
	_profile = DepthProfile.new()
	_profile.custom_minimum_size = Vector2(PANEL_WIDTH, 170)
	box.add_child(_profile)


func _build_bottom_bar(parent: Control) -> void:
	_bottom_bar = _hbox(parent, 12)
	_footer = _label(_bottom_bar, "")
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.size_flags_vertical = Control.SIZE_SHRINK_END
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_theme_font_size_override("font_size", SMALL_SIZE)
	_footer.add_theme_constant_override("outline_size", 6)
	_footer.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 0.85))
	show_message(_controls_hint())

	var panel := _panel(_bottom_bar)
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_legend = panel
	var box := _vbox(panel, 2)
	box.custom_minimum_size.x = 300
	var caption := _label(box, "Dissolved oxygen (mg/L)")
	caption.add_theme_font_size_override("font_size", SMALL_SIZE)
	caption.add_theme_color_override("font_color", MUTED)
	var legend := TextureRect.new()
	legend.texture = GRADIENT
	legend.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	legend.stretch_mode = TextureRect.STRETCH_SCALE
	legend.custom_minimum_size = Vector2(0, 14)
	box.add_child(legend)
	var ticks := _hbox(box)
	for tick: Array in [["0", HORIZONTAL_ALIGNMENT_LEFT], ["7", HORIZONTAL_ALIGNMENT_CENTER], ["14", HORIZONTAL_ALIGNMENT_RIGHT]]:
		var label := _label(ticks, tick[0])
		label.horizontal_alignment = tick[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", SMALL_SIZE)


func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("separation", "VBoxContainer", 6)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("h_separation", "GridContainer", 16)
	theme.set_constant("v_separation", "GridContainer", 3)
	theme.set_constant("separation", "HSeparator", 14)

	var panel := _style(Color(0.08, 0.11, 0.15, 0.88), 14, Vector2(14, 12))
	panel.border_color = Color(1.0, 1.0, 1.0, 0.07)
	panel.set_border_width_all(1)
	panel.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	panel.shadow_size = 6
	panel.shadow_offset = Vector2(0, 2)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_type_variation("ReportPanel", "PanelContainer")
	var report := panel.duplicate() as StyleBoxFlat
	report.bg_color = Color(0.07, 0.1, 0.14, 0.97)
	report.set_corner_radius_all(18)
	report.set_content_margin_all(22)
	report.border_color = Color(ACCENT, 0.45)
	report.set_border_width_all(2)
	report.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	report.shadow_size = 24
	report.shadow_offset = Vector2(0, 6)
	theme.set_stylebox("panel", "ReportPanel", report)
	theme.set_type_variation("ReportCard", "PanelContainer")
	var card := _style(Color(0.12, 0.17, 0.23, 1.0), 12, Vector2(14, 10))
	card.border_color = Color(1.0, 1.0, 1.0, 0.08)
	card.set_border_width_all(1)
	theme.set_stylebox("panel", "ReportCard", card)

	_button_styles(theme, "Button", Color(0.19, 0.30, 0.40), Color(0.16, 0.52, 0.70))
	theme.set_type_variation("AccentButton", "Button")
	_button_styles(theme, "AccentButton", Color(0.20, 0.58, 0.40), Color(0.16, 0.46, 0.32))
	for item: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(item, "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	# CheckBox inherits Button, so give it flat styles explicitly.
	var flat := StyleBoxEmpty.new()
	flat.set_content_margin_all(2)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckBox", flat)
	# The default check icons are small and dark; draw readable ones.
	var checked := _check_icon(true)
	var unchecked := _check_icon(false)
	theme.set_icon("checked", "CheckBox", checked)
	theme.set_icon("checked_disabled", "CheckBox", checked)
	theme.set_icon("unchecked", "CheckBox", unchecked)
	theme.set_icon("unchecked_disabled", "CheckBox", unchecked)
	theme.set_constant("h_separation", "CheckBox", 8)

	theme.set_stylebox("panel", "PopupMenu", _style(Color(0.1, 0.14, 0.19, 0.98), 10, Vector2(6, 6)))
	theme.set_stylebox("hover", "PopupMenu", _style(Color(0.16, 0.52, 0.70), 8, Vector2(6, 2)))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	theme.set_stylebox("slider", "HSlider", _style(Color(0.2, 0.26, 0.32), 4, Vector2(0, 3)))
	var fill := _style(Color(0.33, 0.66, 0.86), 4, Vector2(0, 3))
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme.set_stylebox("background", "ProgressBar", _style(Color(0.2, 0.26, 0.32), 8, Vector2.ZERO))
	theme.set_stylebox("fill", "ProgressBar", _style(Color(0.20, 0.58, 0.40), 8, Vector2.ZERO))
	return theme


func _button_styles(theme: Theme, type: String, base: Color, pressed: Color) -> void:
	var margin := Vector2(14, 6)
	theme.set_stylebox("normal", type, _style(base, 10, margin))
	theme.set_stylebox("hover", type, _style(base.lightened(0.15), 10, margin))
	theme.set_stylebox("pressed", type, _style(pressed, 10, margin))
	theme.set_stylebox("hover_pressed", type, _style(pressed.lightened(0.1), 10, margin))
	theme.set_stylebox("disabled", type, _style(Color(base.darkened(0.35), 0.7), 10, margin))
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())


static func _style(color: Color, radius: int, margin: Vector2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	return box


# Rounded box icon with anti-aliased edges; checked shows a white tick on blue.
static func _check_icon(checked: bool, size := 22) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := Vector2(size, size) * 0.5
	var radius := 4.0
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - half
			var q := p.abs() - (half - Vector2(2.0 + radius, 2.0 + radius))
			var box := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var coverage := clampf(0.5 - box, 0.0, 1.0)
			var color: Color
			if checked:
				var tick := minf(_segment_distance(p, Vector2(-4.5, 0.0), Vector2(-1.5, 3.5)), _segment_distance(p, Vector2(-1.5, 3.5), Vector2(4.5, -3.5)))
				color = Color(0.16, 0.52, 0.70).lerp(Color.WHITE, clampf(1.9 - tick, 0.0, 1.0))
			else:
				color = Color(0.13, 0.18, 0.23).lerp(MUTED, clampf(box + 2.0, 0.0, 1.0))
			color.a = coverage
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---- Layout ----

func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit_side_panels.call_deferred()


# Side panels take their natural height and scroll only when the window is too short.
# The available height comes from the root, not the middle row, to avoid a resize feedback loop.
func _fit_side_panels() -> void:
	_fit_queued = false
	var available := _root.size.y - 2.0 * MARGIN - 2.0 * GAP \
			- _top_bar.get_combined_minimum_size().y - _bottom_bar.get_combined_minimum_size().y
	for scroll: ScrollContainer in [_left_scroll, _right_scroll]:
		var content := scroll.get_child(0) as Control
		scroll.custom_minimum_size.y = maxf(0.0, minf(content.get_combined_minimum_size().y, available))


func _controls_hint() -> String:
	var alt := "Option" if OS.get_name() == "macOS" else "Alt"
	return "Orbit: right-drag, %s+drag or Q/E   Pan: Shift+drag or WASD   Zoom: scroll, pinch or +/-   Home: reset view   V: water view" % alt


func _set_nature_view(nature: bool) -> void:
	if nature == _nature_view:
		return
	_nature_view = nature
	_update_legend()
	water_view_changed.emit(nature)


func _update_legend() -> void:
	_legend.visible = not _nature_view or _slice_enabled.button_pressed


func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var index := clampi(int(config.get_value("ui", "size", 1)), 0, UI_SCALES.size() - 1)
	_ui_size.select(index)
	_apply_ui_size(index)


func _on_ui_size_selected(index: int) -> void:
	_apply_ui_size(index)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("ui", "size", index)
	config.save(SETTINGS_PATH)


func _apply_ui_size(index: int) -> void:
	get_tree().root.content_scale_factor = UI_SCALES[index]
	_queue_fit()


# ---- Helpers ----

func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	# Containers default to PASS; STOP keeps clicks on panels out of the 3D scene.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	return panel


func _side_scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(scroll)
	return scroll


func _side_panel(scroll: ScrollContainer) -> VBoxContainer:
	var panel := _panel(scroll)
	panel.minimum_size_changed.connect(_queue_fit)
	var box := _vbox(panel)
	box.custom_minimum_size.x = PANEL_WIDTH
	return box


func _vbox(parent: Control, separation := -1) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if separation >= 0:
		box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _hbox(parent: Control, separation := -1) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if separation >= 0:
		box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _spacer(parent: Control) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


func _separator(parent: Control) -> void:
	parent.add_child(HSeparator.new())


func _title(parent: Control, text: String) -> Label:
	var label := _label(parent, text)
	label.add_theme_font_size_override("font_size", TITLE_SIZE)
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, callback := Callable()) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	if callback.is_valid():
		button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _check(parent: Control, text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.focus_mode = Control.FOCUS_NONE
	parent.add_child(check)
	return check


func _slider(parent: Control) -> HSlider:
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(slider)
	return slider


func _option(parent: Control, text: String, items: Array, selected: int) -> OptionButton:
	var row := _hbox(parent)
	var label := _label(row, text)
	label.custom_minimum_size.x = 90
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	for item: String in items:
		option.add_item(item)
	option.selected = selected
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _set_stat(key: String, text: String, color := TEXT) -> void:
	var label: Label = _stat_values[key]
	label.text = text
	label.add_theme_color_override("font_color", color)


func _unit_text(number: int, unit: Dictionary) -> String:
	var state: String
	if not unit.has_pump:
		state = "needs a pump"
	elif not unit.has_sprayer:
		state = "needs a sprayer"
	elif unit.lpm <= 0.0:
		state = "off"
	else:
		state = "%d L/min, %.2f kW" % [roundi(unit.lpm), unit.power_kw]
	return "#%d   %s" % [number, state]


func _unit_details(unit: Dictionary) -> String:
	if not (unit.has_pump and unit.has_sprayer):
		return "Fountain %d: needs a %s" % [unit.number, "pump" if not unit.has_pump else "sprayer"]
	return "Fountain %d: %.1f kWh/day" % [unit.number, unit.power_kw * 24.0]


func _update_fountain_buttons() -> void:
	_add_button.disabled = not (_fountains_enabled and _can_add)
	_add_button.tooltip_text = "" if _can_add else "Maximum number of fountains reached."
	for button: Button in [_remove_button, _move_pump_button, _move_sprayer_button]:
		button.disabled = not (_fountains_enabled and _has_selection)
	_clear_button.disabled = not (_fountains_enabled and _has_units)
	_lpm_slider.editable = _fountains_enabled and _has_selection
	for button: Button in _unit_list.get_children():
		button.disabled = not _fountains_enabled


func _update_lpm_label() -> void:
	_lpm_label.text = "Flow: %d L/min" % roundi(_lpm_slider.value) if _has_selection else "Flow: -"


func _emit_environment() -> void:
	environment_changed.emit(_season.selected, _wind.selected, _rain.button_pressed, _bloom.button_pressed)


func _on_lpm_changed(value: float) -> void:
	_update_lpm_label()
	lpm_changed.emit(value)


func _emit_slice() -> void:
	_update_slice_label()
	_update_legend()
	slice_changed.emit(_slice_enabled.button_pressed, int(_slice_slider.value), _slice_flip.button_pressed)


func _update_slice_label() -> void:
	_slice_label.text = "x = %d" % int(_slice_slider.value)
