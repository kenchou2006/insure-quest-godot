extends Control
var board: Control
var kind := ""
func _draw() -> void:
	if is_instance_valid(board):
		board.draw_layer(self, kind)
