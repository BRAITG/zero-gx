extends Level
## A level shown frozen in the editor: no HUD, tour or play wiring.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED  # bodies leave the physics world; nothing moves
