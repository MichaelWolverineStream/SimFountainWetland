extends Control

## Layer-mean DO as horizontal bars, surface layer at the top.

@export var gradient_texture: GradientTexture1D = preload("res://assets/do_gradient.tres")
@export var max_do := 14.0
@export var layer_height_m := 0.25
@export var min_height := 150.0

var _values := PackedFloat32Array()


func set_values(values: PackedFloat32Array) -> void:
	if values.size() != _values.size():
		custom_minimum_size.y = maxf(min_height, values.size() * (_font_size() + 5.0))
	_values = values
	queue_redraw()


func _font_size() -> int:
	return roundi(get_theme_default_font_size() * 0.85)


func _draw() -> void:
	var count := _values.size()
	if count == 0:
		return
	var font := get_theme_default_font()
	var font_size := _font_size()
	var text_color := get_theme_color("font_color", "Label")
	var label_width := font.get_string_size("0.00 m", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0
	var value_width := font.get_string_size("00.0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0
	var row := size.y / count
	var bar_width := size.x - label_width - value_width
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	for i in count:
		var value := _values[i]
		var top := i * row
		var middle := top + row * 0.5 + baseline
		var label := "%.2f m" % ((i + 0.5) * layer_height_m)
		draw_string(font, Vector2(0.0, middle), label, HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, text_color.darkened(0.2))
		var fraction := clampf(value / max_do, 0.0, 1.0)
		draw_rect(Rect2(label_width, top + 2.0, bar_width, row - 4.0), Color(1.0, 1.0, 1.0, 0.06))
		draw_rect(Rect2(label_width, top + 2.0, maxf(2.0, bar_width * fraction), row - 4.0), gradient_texture.gradient.sample(fraction))
		draw_string(font, Vector2(label_width + bar_width + 6.0, middle), "%.1f" % value, HORIZONTAL_ALIGNMENT_LEFT, value_width, font_size, text_color)
