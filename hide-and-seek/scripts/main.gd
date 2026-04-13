extends Node3D

@export var arena_size := 20.0
@export var wall_height := 3.0
@export var wall_thickness := 0.5
@export var episode_length_steps := 180
@export var preparation_steps := 60
@export var sight_reward := 1.0
@export var step_penalty := -0.01
@export var debug_step_logging := true
@export var action_repeat := 5

const boxScene := preload("res://scenes/box.tscn")
const hiderScene := preload("res://scenes/hider.tscn")
const seekerScene := preload("res://scenes/seeker.tscn")
const SLOT_GROUP := "block_slot"
const ACTION_IDLE := 0

var player_cam: Camera3D
var hider_cam: Camera3D
@onready var stage_cam: Camera3D = $stage/stageCam

var hider
var seekerPos := Vector3(0, 1, 0)
var hiderPos := Vector3(-5, 1, -5)
var player

var layout_nodes: Array[Node] = []
var box_nodes: Array[RigidBody3D] = []
var box_spawn_positions: Array[Vector3] = []

var episode_step := 0
var episode_active := false

var layouts = [
	{
		"name": "simple_room",
		"inner_walls": [
			{ "pos": Vector2(-7, 0), "length": 6.0, "horizontal": true },
			{ "pos": Vector2(-1, 0), "length": 2.0, "horizontal": true },
			{ "pos": Vector2(0, -5), "length": 10.0, "horizontal": false },
		],
		"boxes": [
			Vector3(2, 0.5, 2),
			Vector3(-3, 0.5, -1),
		],
		"block_slots": [
			{ "pos": Vector3(-3, 1.0, 0), "size": Vector3(3.0, 2.4, 1.5), "yaw": 0.0 },
		],
	}
]

func _ready() -> void:
	_create_outer_walls()
	load_layout(0)
	_spawn_player()
	stage_cam.current = true
	reset_episode()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		reset_episode()
	if event.is_action_pressed("debug_reset"):
		var reset_data := reset_episode()
		if debug_step_logging:
			_log_step_result("reset", reset_data)
	if event.is_action_pressed("debug_step"):
		_run_debug_step()
	if event.is_action_pressed("hider_cam"):
		stage_cam.current = false
		player_cam.current = false
		hider_cam.current = true

	if event.is_action_pressed("player_cam"):
		stage_cam.current = false
		player_cam.current = true
		hider_cam.current = false

	if event.is_action_pressed("stage_cam"):
		stage_cam.current = true
		player_cam.current = false
		hider_cam.current = false

func load_layout(index: int) -> void:
	for node in layout_nodes:
		if is_instance_valid(node):
			node.queue_free()
	layout_nodes.clear()
	box_nodes.clear()
	box_spawn_positions.clear()

	var layout = layouts[index]

	for w in layout["inner_walls"]:
		var pos2: Vector2 = w["pos"]
		var length: float = w["length"]
		var horizontal: bool = w["horizontal"]
		var pos3 := Vector3(pos2.x, wall_height / 2.0, pos2.y)
		_create_inner_wall(pos3, length, horizontal)

	for i in range(layout["boxes"].size()):
		_create_box(layout["boxes"][i], i + 1)

	for slot_data in layout.get("block_slots", []):
		_create_block_slot(slot_data["pos"], slot_data["size"], slot_data["yaw"])

func _create_outer_walls() -> void:
	var half := arena_size / 2.0
	var walls_data = [
		["North", Vector3(0, wall_height / 2, -half), arena_size, wall_thickness],
		["South", Vector3(0, wall_height / 2, half), arena_size, wall_thickness],
		["East", Vector3(half, wall_height / 2, 0), wall_thickness, arena_size],
		["West", Vector3(-half, wall_height / 2, 0), wall_thickness, arena_size],
	]

	for data in walls_data:
		var wall_name = data[0]
		var pos = data[1]
		var sx = data[2]
		var sz = data[3]
		var wall = _create_wall(wall_name, pos, sx, sz)
		add_child(wall)

func _create_wall(wall_name: String, pos: Vector3, size_x: float, size_z: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "Wall_" + wall_name
	wall.position = pos

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_x, wall_height, size_z)
	mesh_instance.mesh = mesh
	wall.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, wall_height, size_z)
	collider.shape = shape
	wall.add_child(collider)

	return wall

func _create_inner_wall(pos: Vector3, length: float, horizontal: bool) -> void:
	var size_x := length if horizontal else wall_thickness
	var size_z := wall_thickness if horizontal else length
	var wall = _create_wall("Inner", pos, size_x, size_z)
	add_child(wall)
	layout_nodes.append(wall)

func _spawn_player() -> void:
	if player == null:
		player = seekerScene.instantiate()
		add_child(player)
	if hider == null:
		hider = hiderScene.instantiate()
		add_child(hider)

	player.hider_ref = hider
	player.position = seekerPos
	hider.position = hiderPos
	hider_cam = hider.get_node("head/Camera3D")
	player_cam = player.get_node("head/Camera3D")

func _create_box(pos: Vector3, idx: int) -> void:
	var box := boxScene.instantiate()
	box.name = "Box" + str(idx)

	var mesh_instance := box.get_node("MeshInstance3D")
	mesh_instance.mesh.size = Vector3(2, 2, 2)

	var collider := box.get_node("CollisionShape3D")
	collider.shape.size = Vector3(2, 2, 2)

	box.position = Vector3(pos.x, collider.shape.size.y / 2.0, pos.z)

	add_child(box)
	layout_nodes.append(box)
	box_nodes.append(box)
	box_spawn_positions.append(box.position)

func _create_block_slot(pos: Vector3, size: Vector3, yaw: float) -> void:
	var slot := Area3D.new()
	slot.name = "BlockSlot"
	slot.position = pos
	slot.rotation.y = yaw
	slot.add_to_group(SLOT_GROUP)
	slot.set_meta("snap_position", pos)
	slot.set_meta("snap_yaw", yaw)

	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	slot.add_child(collider)

	add_child(slot)
	layout_nodes.append(slot)

func reset_episode() -> Dictionary:
	episode_step = 0
	episode_active = true

	if player:
		player.reset_agent_state(seekerPos)
		player.clear_action_override()
	if hider:
		hider.reset_agent_state(hiderPos)

	for i in range(box_nodes.size()):
		var box := box_nodes[i]
		if not is_instance_valid(box):
			continue
		box.freeze = false
		box.collision_layer = 2
		box.collision_mask = 15
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.global_position = box_spawn_positions[i]
		box.rotation = Vector3.ZERO

	return {
		"observation": player.get_observation() if player else [],
		"reward": 0.0,
		"done": false,
		"info": {
			"episode_step": episode_step,
			"in_preparation": true,
		},
	}

func step(action: int) -> Dictionary:
	if not episode_active:
		reset_episode()

	if player:
		if episode_step < preparation_steps:
			player.set_action(ACTION_IDLE)
		else:
			player.set_action(action)

	for _i in range(action_repeat):
		await get_tree().physics_frame

	if player:
		player.clear_action_override()

	episode_step += 1

	var in_preparation := episode_step <= preparation_steps
	var sees_hider: bool = player.sees_hider() if player != null else false
	var done := false
	var reward := 0.0

	if not in_preparation:
		reward = sight_reward if sees_hider else step_penalty
		done = sees_hider

	if episode_step >= episode_length_steps:
		done = true

	if done:
		episode_active = false

	return {
		"observation": player.get_observation() if player else [],
		"reward": reward,
		"done": done,
		"info": {
			"episode_step": episode_step,
			"in_preparation": in_preparation,
			"sees_hider": sees_hider,
		},
	}

func _run_debug_step() -> void:
	var action := randi_range(0, 4)
	var result = await step(action)
	if debug_step_logging:
		_log_step_result("action=%d" % action, result)

func _log_step_result(label: String, result: Dictionary) -> void:
	var observation = result.get("observation", [])
	var info: Dictionary = result.get("info", {})
	print(
		"[ENV %s] obs=%d reward=%.3f done=%s prep=%s step=%s sees_hider=%s" % [
			label,
			observation.size(),
			float(result.get("reward", 0.0)),
			str(result.get("done", false)),
			str(info.get("in_preparation", false)),
			str(info.get("episode_step", -1)),
			str(info.get("sees_hider", false)),
		]
	)
