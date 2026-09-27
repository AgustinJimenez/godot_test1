class_name ProceduralWalkParameterControls
extends RefCounted
## Keeps the lab's parameter sliders and their mode-aware defaults together.

var _entries: Array[Dictionary] = []


func add_slider(parent: VBoxContainer, title: String, minimum: float,
		maximum: float, initial: float, callback: Callable) -> HSlider:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = initial
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	_entries.append({"slider": slider, "default": initial, "callback": callback})
	return slider


func set_default(slider: HSlider, value: float) -> void:
	for entry: Dictionary in _entries:
		if entry["slider"] == slider:
			slider.set_value_no_signal(value)
			entry["default"] = slider.value
			(entry["callback"] as Callable).call(slider.value)
			return


func reset() -> void:
	for entry: Dictionary in _entries:
		var slider := entry["slider"] as HSlider
		var value := float(entry["default"])
		slider.set_value_no_signal(value)
		(entry["callback"] as Callable).call(slider.value)
