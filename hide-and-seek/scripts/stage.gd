extends Node3D
@onready var stage_cam: Camera3D = $stageCam
@onready var camera_3d: Camera3D = $"../player/head/Camera3D"

var use_player_cam = true

func _input(event):
	if event.is_action_pressed("switch_cam"):
		use_player_cam = !use_player_cam
		if use_player_cam:
			camera_3d.current = true
			stage_cam.current = false
		else:
			stage_cam.current = true
			camera_3d.current = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
