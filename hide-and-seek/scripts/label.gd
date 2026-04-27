extends Label

func _ready() -> void:
	text = """Controls:
1 - Stage camera
2 - Seeker camera
3 - Hider camera
L - Cycle level
R - Reset episode
FPS: ..."""

func _process(_delta: float) -> void:
	text = """Controls:
1 - Stage camera
2 - Seeker camera
3 - Hider camera
L - Cycle level
R - Reset episode
FPS: %s""" % Engine.get_frames_per_second()
