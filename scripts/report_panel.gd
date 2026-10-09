extends Control

## Centred report comparing a comparison measurement against the baseline. Built in code
## under the HUD root so it inherits the HUD theme. Esc, Close or a click outside closes it.

signal closed
signal make_baseline_pressed

const ProfileCompare := preload("res://scripts/profile_compare.gd")
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const WINDS := ["Calm", "Moderate", "High"]
const CONTENT_WIDTH := 760.0
const PANEL_PADDING := 48.0
const MAX_HEIGHT_FRACTION := 0.86
const TEXT := Color(0.94, 0.96, 0.98)
const MUTED := Color(0.70, 0.78, 0.84)
const ACCENT := Color(0.55, 0.86, 1.0)
const BASE_COLOR := Color(0.62, 0.70, 0.80)
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)
const SMALL_SIZE := 17
const HEADING_SIZE := 30
# label, key, unit, scale, decimals, better (+1 higher is better, -1 lower is better, 0 neutral)
const METRICS := [
	["Mean DO", "mean_do", "mg/L", 1.0, 2, 1],
	["Surface layer", "surface_mean_do", "mg/L", 1.0, 2, 1],
	["Bottom cells", "bottom_mean_do", "mg/L", 1.0, 2, 1],
	["Lowest cell", "min_do", "mg/L", 1.0, 2, 1],
	["Highest cell", "max_do", "mg/L", 1.0, 2, 0],
	["Hypoxic volume", "hypoxic_fraction", "%", 100.0, 1, -1],
	["Oxygen in the water", "total_do_kg", "kg", 1.0, 1, 1],
	["Fountains", "fountain_count", "", 1.0, 0, 0],
	["Total flow", "total_lpm", "L/min", 1.0, 0, 0],
	["Energy", "kwh_per_day", "kWh/day", 1.0, 1, -1],
]

var _panel: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _tween: Tween
var _fit_queued := false


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.03, 0.06, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_backdrop_input)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"ReportPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)
	_content.minimum_size_changed.connect(_queue_fit)
	resized.connect(_queue_fit)


func open(baseline: Dictionary, comparison: Dictionary, hypoxia_threshold: float) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_build(baseline, comparison, hypoxia_threshold)
	_scroll.scroll_vertical = 0
	visible = true
	_fit()
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	_panel.scale = Vector2.ONE
	await get_tree().process_frame
	if not visible:
		return
	_fit()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * 0.92
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, 0.18)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	modulate.a = 1.0
	_panel.scale = Vector2.ONE
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit.call_deferred()


# Fixed content width (narrower on small windows); the scroll area grows with the content
# up to a fraction of the window height and scrolls beyond that.
func _fit() -> void:
	_fit_queued = false
	if _content == null:
		return
	_content.custom_minimum_size.x = minf(CONTENT_WIDTH, size.x * 0.94 - PANEL_PADDING)
	var max_height := size.y * MAX_HEIGHT_FRACTION - PANEL_PADDING
	_scroll.custom_minimum_size.y = maxf(0.0, minf(_content.get_combined_minimum_size().y, max_height))


# ---- Content ----

func _build(b: Dictionary, c: Dictionary, threshold: float) -> void:
	var header := _hbox(_content, 8)
	var title := _label(header, "Comparison report")
	title.add_theme_font_size_override("font_size", HEADING_SIZE)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := _button(header, "Close", close)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var subtitle := _label(_content, "Each run starts from the same morning and runs until the oxygen settles. Numbers are averages over the final 24 hours.")
	_small(subtitle, MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var cards := _hbox(_content, 10)
	_scenario_card(cards, "BASELINE", BASE_COLOR, b)
	var arrow := _label(cards, "→")
	arrow.add_theme_font_size_override("font_size", HEADING_SIZE)
	arrow.add_theme_color_override("font_color", MUTED)
	_scenario_card(cards, "COMPARISON", ACCENT, c)

	var changed := _label(_content, _what_changed(b, c))
	changed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var headlines := _vbox(_content, 4)
	for line: Array in _headlines(b, c, threshold):
		var row := _hbox(headlines, 10)
		var icon := _label(row, line[0])
		icon.add_theme_color_override("font_color", line[1])
		icon.custom_minimum_size.x = 22
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var text := _label(row, line[2])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_content.add_child(HSeparator.new())
	_heading(_content, "Depth profile, 24 h average")
	var chart := ProfileCompare.new()
	_content.add_child(chart)
	chart.set_data(b, c, threshold)

	_content.add_child(HSeparator.new())
	_heading(_content, "All numbers")
	_metrics(b, c)

	if not (b.settled and c.settled):
		var note := _label(_content, "One run had not fully settled after %d days, so small differences may not hold up." % maxi(b.days, c.days))
		_small(note, Color(1.0, 0.8, 0.45))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var buttons := _hbox(_content, 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var keep := _button(buttons, "Make this the new baseline", func() -> void:
		make_baseline_pressed.emit()
		close())
	keep.tooltip_text = "Use the comparison run as the reference for the next comparison."
	var done := _button(buttons, "Close", close)
	done.theme_type_variation = &"AccentButton"


func _scenario_card(parent: Control, caption: String, color: Color, m: Dictionary) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ReportCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box := _vbox(card, 3)
	var head := _hbox(box, 8)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(swatch)
	_small(_label(head, caption), color)
	_label(box, m.environment_text).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(box, m.fountain_text)
	var big := _label(box, "%.2f mg/L mean DO" % m.mean_do)
	big.add_theme_font_size_override("font_size", 24)
	big.add_theme_color_override("font_color", color.lightened(0.15))
	_small(_label(box, ("Settled after %d days" if m.settled else "Stopped after %d days") % m.days), MUTED)


func _what_changed(b: Dictionary, c: Dictionary) -> String:
	var changes := PackedStringArray()
	var be: Array = b.environment
	var ce: Array = c.environment
	if be[0] != ce[0]:
		changes.append("season %s → %s" % [SEASONS[be[0]], SEASONS[ce[0]]])
	if be[1] != ce[1]:
		changes.append("wind %s → %s" % [WINDS[be[1]].to_lower(), WINDS[ce[1]].to_lower()])
	if be[2] != ce[2]:
		changes.append("rain %s" % ("on" if ce[2] else "off"))
	if be[3] != ce[3]:
		changes.append("algae bloom %s" % ("on" if ce[3] else "off"))
	if b.fountain_count != c.fountain_count:
		changes.append("fountains %d → %d" % [b.fountain_count, c.fountain_count])
	elif not is_equal_approx(b.total_lpm, c.total_lpm):
		changes.append("total flow %d → %d L/min" % [roundi(b.total_lpm), roundi(c.total_lpm)])
	elif b.layout != c.layout:
		changes.append("fountain positions")
	if changes.is_empty():
		return "What changed: nothing. Both runs used the same settings, so the results match."
	return "What changed: %s." % ", ".join(changes)


# Returns [glyph, colour, sentence] triples.
func _headlines(b: Dictionary, c: Dictionary, threshold: float) -> Array:
	var lines := []
	var d: float = c.mean_do - b.mean_do
	if absf(d) < 0.05:
		lines.append(["●", MUTED, "Average oxygen stayed about the same at %.2f mg/L." % c.mean_do])
	else:
		var percent := d / maxf(b.mean_do, 0.01) * 100.0
		lines.append(["▲" if d > 0.0 else "▼", GOOD if d > 0.0 else BAD,
				"Average oxygen %s from %.2f to %.2f mg/L (%+.0f%%)." % ["rose" if d > 0.0 else "fell", b.mean_do, c.mean_do, percent]])

	var bh: float = b.hypoxic_fraction * 100.0
	var ch: float = c.hypoxic_fraction * 100.0
	if absf(ch - bh) < 0.5:
		lines.append(["●", MUTED, "Low-oxygen water (below %.1f mg/L) stayed at about %.0f%% of the pond." % [threshold, ch]])
	else:
		lines.append(["▼" if ch < bh else "▲", GOOD if ch < bh else BAD,
				"Low-oxygen water (below %.1f mg/L) %s from %.0f%% to %.0f%% of the pond." % [threshold, "shrank" if ch < bh else "grew", bh, ch]])

	var bd: float = c.bottom_mean_do - b.bottom_mean_do
	if absf(bd) < 0.05:
		lines.append(["●", MUTED, "Water at the bottom stayed at about %.2f mg/L." % c.bottom_mean_do])
	else:
		lines.append(["▲" if bd > 0.0 else "▼", GOOD if bd > 0.0 else BAD,
				"Water at the bottom went from %.2f to %.2f mg/L." % [b.bottom_mean_do, c.bottom_mean_do]])

	var e: float = c.kwh_per_day - b.kwh_per_day
	if absf(e) < 0.05:
		lines.append(["●", MUTED, "Energy use is the same: %.1f kWh/day." % c.kwh_per_day])
	else:
		var gain := d / absf(e)
		var sentence := "The fountains use %.1f kWh/day %s (%.1f → %.1f)." % [absf(e), "more" if e > 0.0 else "less", b.kwh_per_day, c.kwh_per_day]
		if e > 0.0:
			sentence += " Each extra kWh/day bought %+.3f mg/L of mean DO." % gain
		else:
			sentence += " Each kWh/day saved changed mean DO by %+.3f mg/L." % gain
		lines.append(["⚡", Color(1.0, 0.85, 0.4), sentence])
	return lines


func _metrics(b: Dictionary, c: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	for heading: String in ["", "Baseline", "Comparison", "Change"]:
		var label := _label(grid, heading)
		_small(label, MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for metric: Array in METRICS:
		var factor: float = metric[3]
		var decimals: int = metric[4]
		var better: int = metric[5]
		var unit: String = metric[2]
		var bv: float = float(b[metric[1]]) * factor
		var cv: float = float(c[metric[1]]) * factor
		var metric_label := _label(grid, metric[0])
		metric_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metric_label.add_theme_color_override("font_color", MUTED)
		_value(grid, _format(bv, decimals, unit), TEXT)
		_value(grid, _format(cv, decimals, unit), TEXT)
		var delta := cv - bv
		var epsilon := 0.5 * pow(10.0, -decimals)
		if absf(delta) < epsilon:
			_value(grid, "≈ 0", MUTED)
			continue
		var color := ACCENT
		if better != 0:
			color = GOOD if delta * better > 0.0 else BAD
		var change_unit := " pts" if unit == "%" else ""
		_value(grid, "%s %s%s" % ["▲" if delta > 0.0 else "▼", _number(absf(delta), decimals), change_unit], color)


func _format(value: float, decimals: int, unit: String) -> String:
	if unit == "%":
		return "%s %%" % _number(value, decimals)
	return "%s %s" % [_number(value, decimals), unit] if unit != "" else _number(value, decimals)


func _number(value: float, decimals: int) -> String:
	return ("%." + str(decimals) + "f") % value


# ---- Helpers ----

func _value(parent: Control, text: String, color: Color) -> void:
	var label := _label(parent, text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", color)


func _heading(parent: Control, text: String) -> void:
	var label := _label(parent, text)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", ACCENT)


func _small(label: Label, color: Color) -> Label:
	label.add_theme_font_size_override("font_size", SMALL_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


func _label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _vbox(parent: Control, separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _hbox(parent: Control, separation: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box
