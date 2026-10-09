extends Control

## Depth profile comparison: per water layer a muted baseline bar above a DO-coloured
## comparison bar, each with a 24 h min-max whisker. Shows the hypoxic band, a wavy water
## surface, the sediment and the change per layer in a right-hand column.

const GRADIENT := preload("res://assets/do_gradient.tres")
const GRADIENT_MAX := 14.0
const BASE_COLOR := Color(0.62, 0.70, 0.80)
const TEXT := Color(0.94, 0.96, 0.98)
const MUTED := Color(0.70, 0.78, 0.84)
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)
const HYPOXIC := Color(1.0, 0.4, 0.35)
const SURFACE := Color(0.6, 0.88, 1.0)
const SEDIMENT := Color(0.40, 0.31, 0.22)

@export var layer_height_m := 0.25

var _b_mean := PackedFloat32Array()
var _b_min := PackedFloat32Array()
var _b_max := PackedFloat32Array()
var _c_mean := PackedFloat32Array()
var _c_min := PackedFloat32Array()
var _c_max := PackedFloat32Array()
var _threshold := 2.0
var _axis_max := 14.0
var _bar_box := StyleBoxFlat.new()


func _init() -> void:
	_bar_box.set_corner_radius_all(4)
	_bar_box.anti_aliasing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(baseline: Dictionary, comparison: Dictionary, hypoxia_threshold: float) -> void:
	_b_mean = baseline.layer_mean
	_b_min = baseline.layer_min
	_b_max = baseline.layer_max
	_c_mean = comparison.layer_mean
	_c_min = comparison.layer_min
	_c_max = comparison.layer_max
	_threshold = hypoxia_threshold
	var top := 0.0
	for values: PackedFloat32Array in [_b_max, _c_max]:
		for value in values:
			top = maxf(top, value)
	_axis_max = maxf(8.0, ceilf((top + 0.25) / 2.0) * 2.0)
	_update_minimum_size()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_update_minimum_size()


func _layer_count() -> int:
	return mini(_b_mean.size(), _c_mean.size())


func _font_size() -> int:
	return roundi(get_theme_default_font_size() * 0.8)


func _bar_height() -> float:
	return roundf(_font_size() * 0.7)


func _row_height() -> float:
	return _bar_height() * 2.0 + 9.0


func _legend_height() -> float:
	return _font_size() + 16.0


func _surface_height() -> float:
	return _font_size() + 6.0


func _sediment_height() -> float:
	return 14.0


func _axis_height() -> float:
	return _font_size() + 8.0


func _update_minimum_size() -> void:
	custom_minimum_size.y = _legend_height() + _surface_height() + _layer_count() * _row_height() \
			+ _sediment_height() + _axis_height()


func _draw() -> void:
	var count := _layer_count()
	if count == 0:
		return
	var font := get_theme_default_font()
	var font_size := _font_size()
	var ascent := font.get_ascent(font_size)
	var centre_offset := (ascent - font.get_descent(font_size)) * 0.5
	var label_width := font.get_string_size("0.00 m", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 12.0
	var delta_width := font.get_string_size("+00.0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14.0
	var x0 := label_width
	var plot_width := size.x - label_width - delta_width
	var row := _row_height()
	var bar := _bar_height()
	var surface_y := _legend_height() + _surface_height()
	var bottom_y := surface_y + count * row
	var to_x := func(value: float) -> float: return x0 + plot_width * clampf(value / _axis_max, 0.0, 1.0)

	_draw_legend(font, font_size, ascent)

	# Water body with a soft vertical gradient.
	var water := PackedVector2Array([Vector2(x0, surface_y), Vector2(x0 + plot_width, surface_y),
			Vector2(x0 + plot_width, bottom_y), Vector2(x0, bottom_y)])
	var top_tint := Color(0.25, 0.55, 0.75, 0.16)
	var deep_tint := Color(0.08, 0.2, 0.32, 0.28)
	draw_polygon(water, PackedColorArray([top_tint, top_tint, deep_tint, deep_tint]))

	# Hypoxic band and its threshold line.
	var threshold_x: float = to_x.call(_threshold)
	draw_rect(Rect2(x0, surface_y, threshold_x - x0, bottom_y - surface_y), Color(HYPOXIC, 0.14))
	draw_dashed_line(Vector2(threshold_x, surface_y - 4.0), Vector2(threshold_x, bottom_y), Color(HYPOXIC, 0.8), 1.5, 5.0)

	# Grid lines every 2 mg/L with tick labels under the sediment.
	var axis_y := bottom_y + _sediment_height() + 4.0 + ascent
	var tick := 0.0
	while tick <= _axis_max + 0.01:
		var x: float = to_x.call(tick)
		if tick > 0.0:
			draw_line(Vector2(x, surface_y), Vector2(x, bottom_y), Color(1.0, 1.0, 1.0, 0.08), 1.0)
		var text := "%d" % roundi(tick)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(clampf(x - width * 0.5, x0, x0 + plot_width - width), axis_y), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MUTED)
		tick += 2.0
	draw_string(font, Vector2(x0 + plot_width + 8.0, axis_y), "mg/L", HORIZONTAL_ALIGNMENT_LEFT, delta_width, font_size, MUTED)

	_draw_surface(x0, plot_width, surface_y)
	draw_string(font, Vector2(x0 + plot_width + 8.0, surface_y - 6.0), "change", HORIZONTAL_ALIGNMENT_LEFT, delta_width,
			roundi(font_size * 0.85), MUTED)

	for i in count:
		var y := surface_y + i * row
		var middle := y + row * 0.5
		draw_string(font, Vector2(0.0, middle + centre_offset), "%.2f m" % ((i + 0.5) * layer_height_m),
				HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, MUTED)
		var base_rect := Rect2(x0, y + 4.0, maxf(3.0, to_x.call(_b_mean[i]) - x0), bar)
		var comp_rect := Rect2(x0, y + 5.0 + bar, maxf(3.0, to_x.call(_c_mean[i]) - x0), bar)
		_bar(base_rect, Color(BASE_COLOR, 0.7))
		_bar(comp_rect, GRADIENT.gradient.sample(clampf(_c_mean[i] / GRADIENT_MAX, 0.0, 1.0)))
		_whisker(to_x.call(_b_min[i]), to_x.call(_b_max[i]), base_rect.get_center().y, bar)
		_whisker(to_x.call(_c_min[i]), to_x.call(_c_max[i]), comp_rect.get_center().y, bar)
		var delta := _c_mean[i] - _b_mean[i]
		var color := MUTED
		if delta >= 0.05:
			color = GOOD
		elif delta <= -0.05:
			color = BAD
		draw_string(font, Vector2(x0 + plot_width + 8.0, middle + centre_offset),
				"%+.1f" % delta if absf(delta) >= 0.05 else "0.0", HORIZONTAL_ALIGNMENT_LEFT, delta_width, font_size, color)

	_draw_sediment(x0, plot_width, bottom_y)


func _draw_legend(font: Font, font_size: int, ascent: float) -> void:
	var x := 0.0
	var swatch := Vector2(22.0, roundf(font_size * 0.6))
	var y := 4.0
	var text_y := y + swatch.y * 0.5 + (ascent - font.get_descent(font_size)) * 0.5
	var items := [
		["Baseline", 0], ["Comparison", 1], ["24 h range", 2], ["Hypoxic (< %.1f mg/L)" % _threshold, 3],
	]
	for item: Array in items:
		var rect := Rect2(Vector2(x, y), swatch)
		match item[1]:
			0:
				_bar(rect, Color(BASE_COLOR, 0.7))
			1:
				var steps := 6
				for s in steps:
					var part := Rect2(rect.position + Vector2(rect.size.x * s / steps, 0.0), Vector2(rect.size.x / steps + 0.5, rect.size.y))
					draw_rect(part, GRADIENT.gradient.sample((s + 0.5) / steps))
			2:
				_whisker(rect.position.x + 2.0, rect.end.x - 2.0, rect.get_center().y, swatch.y)
			3:
				draw_rect(rect, Color(HYPOXIC, 0.25))
				draw_dashed_line(Vector2(rect.end.x - 2.0, rect.position.y), Vector2(rect.end.x - 2.0, rect.end.y), HYPOXIC, 1.5, 3.0)
		x += swatch.x + 6.0
		draw_string(font, Vector2(x, text_y), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT)
		x += font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 18.0


func _draw_surface(x0: float, width: float, y: float) -> void:
	var points := PackedVector2Array()
	var steps := 48
	for s in steps + 1:
		var t := float(s) / steps
		points.append(Vector2(x0 + width * t, y - 2.0 + sin(t * TAU * 6.0) * 2.0))
	draw_polyline(points, SURFACE, 2.0, true)
	# A few bubbles rising from the surface.
	for bubble: Vector3 in [Vector3(0.18, 7.0, 2.5), Vector3(0.22, 12.0, 1.8), Vector3(0.63, 9.0, 2.2), Vector3(0.86, 6.0, 1.6)]:
		draw_arc(Vector2(x0 + width * bubble.x, y - bubble.y), bubble.z, 0.0, TAU, 12, Color(SURFACE, 0.8), 1.2, true)


func _draw_sediment(x0: float, width: float, y: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = SEDIMENT
	box.corner_radius_bottom_left = 6
	box.corner_radius_bottom_right = 6
	box.anti_aliasing = true
	draw_style_box(box, Rect2(x0, y, width, _sediment_height()))
	# Pebbles at fixed pseudo-random spots so the strip looks the same every redraw.
	for i in 18:
		var t := fposmod(i * 0.618034, 1.0)
		var r := 1.5 + fposmod(i * 0.3819, 1.0) * 2.0
		var py := y + 4.0 + fposmod(i * 0.7548, 1.0) * (_sediment_height() - 8.0)
		draw_circle(Vector2(x0 + 6.0 + (width - 12.0) * t, py), r, SEDIMENT.lightened(0.18 + fposmod(i * 0.41, 1.0) * 0.2), true, -1.0, true)


func _bar(rect: Rect2, color: Color) -> void:
	_bar_box.bg_color = color
	draw_style_box(_bar_box, rect)


func _whisker(from_x: float, to_x: float, y: float, height: float) -> void:
	var color := Color(1.0, 1.0, 1.0, 0.75)
	var cap := height * 0.35
	draw_line(Vector2(from_x, y), Vector2(to_x, y), color, 1.5, true)
	draw_line(Vector2(from_x, y - cap), Vector2(from_x, y + cap), color, 1.5, true)
	draw_line(Vector2(to_x, y - cap), Vector2(to_x, y + cap), color, 1.5, true)
