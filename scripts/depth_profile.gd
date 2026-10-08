extends Control

## Layer-mean DO as horizontal bars, surface layer at the top.

@export var gradient_texture: GradientTexture1D = preload("res://assets/do_gradient.tres")
@export var max_do := 14.0
@export var label_width := 64.0
@export var layer_height_m := 0.25

var _values := PackedFloat32Array()


func set_values(values: PackedFloat32Array) -> void:
	_values = values
	queue_redraw()


func _draw() -> void:
	var count := _values.size()
	if count == 0:
		return
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var row := size.y / count
	var bar_width := size.x - label_width * 2.0
	for i in count:
		var value := _values[i]
		var top := i * row
		var label := "%.2f m" % ((i + 0.5) * layer_height_m)
		draw_string(font, Vector2(0.0, top + row * 0.5 + font_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size)
		var fraction := clampf(value / max_do, 0.0, 1.0)
		var color := gradient_texture.gradient.sample(fraction)
		draw_rect(Rect2(label_width, top + 1.0, maxf(1.0, bar_width * fraction), row - 2.0), color)
		var text := "%.1f" % value
		draw_string(font, Vector2(label_width + bar_width + 6.0, top + row * 0.5 + font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size)
