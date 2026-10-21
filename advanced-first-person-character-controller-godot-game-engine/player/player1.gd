extends CharacterBody3D


@onready var head: Node3D = $Head
@onready var eyes: Node3D = $Head/Eyes
@onready var camera_3d: Camera3D = $Head/Eyes/Camera3D
@onready var standing_collision_shape = $standing_collision_shape
@onready var crouching_collision_shape = $crouching_collision_shape
@onready var standup_check: RayCast3D = $StandupCheck
@onready var interaction_raycast = $Head/Eyes/Camera3D/Interaction_Raycast
@onready var sound_material_scanner_ray: RayCast3D = $sound_material_scanner_ray
@onready var walk_concrete: AudioStreamPlayer3D = $audio/walk_concrete
@onready var walk_grass: AudioStreamPlayer3D = $audio/walk_grass
@onready var walk_wood: AudioStreamPlayer3D = $audio/walk_wood
@onready var walk_metal: AudioStreamPlayer3D = $audio/walk_metal
@onready var walk_carpet: AudioStreamPlayer3D = $audio/walk_carpet





const walking_speed: float = 3.0
const sprinting_speed: float = 4.0
const crouching_speed: float = 1.0
var current_speed: float = 0.0
var moving: bool = false
var input_dir: Vector2 = Vector2.ZERO
var direction: Vector3 = Vector3.ZERO
const crouching_depth: float = -0.9
const jump_velocity: float = 4.0

var lerp_speed: float = 10.0

var current_stepping_sound_timer = 0.0
@export var step_delay_walk: float = 0.5
@export var step_delay_run: float = 0.3
@export var step_delay_crouch: float = 0.8

var base_fov: float  = 90.0
var mouse_sensitivty: float = 0.3

enum PlayerState {
	IDLE_STAND,
	IDLE_CROUCH,
	CROUCHING,
	WALKING,
	SPRINTING,
	AIR
	}

var player_state: PlayerState = PlayerState.IDLE_STAND

const head_bobbing_sprinting_speed: float = 22.0
const head_bobbing_walking_speed: float = 14.0
const head_bobbing_crouching_speed: float = 10.0
const head_bobbing_sprinting_intensity: float = 0.2
const head_bobbing_walking_intensity: float = 0.1
const head_bobbing_crouching_intensity: float = 0.05
var head_bobbing_current_intensity: float = 0.0
var head_bobbing_vector: Vector2 = Vector2.ZERO
var head_bobbing_index: float = 0.0

const MAX_STEP_HEIGHT = 0.5
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor = -INF


func  is_surface_too_step(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func _run_body_test_motion(from : Transform3D, motion : Vector3, result = null) -> bool:
	if not result: result = PhysicsTestMotionResult3D.new()
	var params = PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(self.get_rid(), params, result)



func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	var floor_below : bool = %StairsBelowRayCast3D.is_colliding() and not is_surface_too_step(%StairsBelowRayCast3D.get_collision_normal())
	var was_on_floor_last_frame = Engine.get_physics_frames() - _last_frame_was_on_floor == 1
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if _run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap

func _snap_up_stairs_check(delta) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	var expected_move_motion = self.velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance = self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	#  We give some clearance above to ensure there's ample room for the player.
	#  If it hits a step <= MAX_STEP_HEIGHT, we can teleport the player on top of the step
	#  along with their intended motion forward.
	var down_check_result = KinematicCollision3D.new()
	if (self.test_move(step_pos_with_clearance, Vector3(0,-MAX_STEP_HEIGHT*2,0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get stuck on a stair. Too little and can jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get stuck on a stair. Too little and can jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_position() - self.global_position).y > MAX_STEP_HEIGHT: return false
		%StairsAheadRayCast3D.global_position = down_check_result.get_position() + Vector3(0,MAX_STEP_HEIGHT,0) + expected_move_motion.normalized() * 0.1
		%StairsAheadRayCast3D.force_raycast_update()
		if %StairsAheadRayCast3D.is_colliding() and not is_surface_too_step(%StairsAheadRayCast3D.get_collision_normal()):
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivty))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivty))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85),deg_to_rad(85))


func _physics_process(delta) -> void:
	if is_on_floor(): _last_frame_was_on_floor = Engine.get_physics_frames()
	
	uptadePlayerState()
	updateCamera(delta)
	
	# Add the gravity.
	if not is_on_floor():
		if velocity.y >= 0:
			velocity += get_gravity() * delta
		else:
			velocity += get_gravity() * delta * 2.0

	# Handle jump.
	if is_on_floor() or _snapped_to_stairs_last_frame:
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = jump_velocity
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	input_dir = Input.get_vector("left", "right", "forward", "backward")
	direction = lerp(direction,(transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * 10.0)
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	
	if velocity.length() > 0.1 and is_on_floor():
		if $stepping_sound_timer.is_stopped():
			dynamic_player_walking_saund()
			$stepping_sound_timer.start(current_stepping_sound_timer)
	
	
	if not _snap_up_stairs_check(delta):
		
		move_and_slide()
		_snap_down_to_stairs_check()
	
	updatePlayerSteppingSoundTimer(player_state)
	



func uptadePlayerState() -> void:
	moving = (input_dir != Vector2.ZERO)
	if not is_on_floor():
		player_state = PlayerState.AIR
	else:
		if Input.is_action_pressed("crouch"):
			if not moving:
				player_state = PlayerState.IDLE_CROUCH
			else:
				player_state = PlayerState.CROUCHING
		elif !standup_check.is_colliding():
			if not moving:
				player_state = PlayerState.IDLE_STAND
			elif Input.is_action_pressed("sprint"):
				player_state = PlayerState.SPRINTING
			else:
				player_state = PlayerState.WALKING
		
	updatePlayerColShape(player_state)
	updatePlayerSpeed(player_state)

func updatePlayerColShape(_player_state: PlayerState) -> void:
	if _player_state == PlayerState.CROUCHING or _player_state == PlayerState.IDLE_CROUCH:
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
	else:
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true

func updatePlayerSpeed(_player_state: PlayerState) -> void:
	if _player_state == PlayerState.CROUCHING or _player_state == PlayerState.IDLE_CROUCH:
		current_speed = crouching_speed
	elif _player_state == PlayerState.WALKING:
		current_speed = walking_speed
	elif _player_state == PlayerState.SPRINTING:
		current_speed = sprinting_speed
	

func updatePlayerSteppingSoundTimer(_player_state: PlayerState):
	if _player_state == PlayerState.CROUCHING or _player_state == PlayerState.IDLE_CROUCH:
		current_stepping_sound_timer = step_delay_crouch
	elif _player_state == PlayerState.WALKING:
		current_stepping_sound_timer = step_delay_walk
	elif _player_state == PlayerState.SPRINTING:
		current_stepping_sound_timer = step_delay_run
	


func updateCamera(delta: float) -> void:
	if player_state == PlayerState.AIR:
		pass
	
	if player_state == PlayerState.CROUCHING or player_state == PlayerState.IDLE_CROUCH:
		head.position.y = lerp(head.position.y, 1.8 + crouching_depth, delta*lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov*0.95, delta*lerp_speed)
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
		head_bobbing_index += head_bobbing_crouching_speed * delta
	elif player_state == PlayerState.IDLE_STAND:
		head.position.y = lerp(head.position.y, 1.8, delta*lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov, delta*lerp_speed)
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
	elif player_state == PlayerState.WALKING:
		head.position.y = lerp(head.position.y, 1.8, delta*lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov, delta*lerp_speed)
		head_bobbing_current_intensity = head_bobbing_walking_intensity
		head_bobbing_index += head_bobbing_walking_speed * delta
	elif player_state == PlayerState.SPRINTING:
		head.position.y = lerp(head.position.y, 1.8, delta*lerp_speed)
		camera_3d.fov = lerp(camera_3d.fov, base_fov*1.05, delta*lerp_speed)
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
		head_bobbing_index += head_bobbing_sprinting_speed * delta
		
	
	head_bobbing_vector.y = sin(head_bobbing_index)
	head_bobbing_vector.x = (sin(head_bobbing_index/2.0)+0.5)
	if moving:
		eyes.position.y = lerp(eyes.position.y , head_bobbing_vector.y*(head_bobbing_current_intensity/2.0),delta*lerp_speed)
		eyes.position.x = lerp(eyes.position.x , head_bobbing_vector.x*(head_bobbing_current_intensity),delta*lerp_speed)
	else:
		eyes.position.y = lerp(eyes.position.y , 0.0,delta*lerp_speed)
		eyes.position.x = lerp(eyes.position.x , 0.0,delta*lerp_speed)

func dynamic_player_walking_saund() -> void:
	if sound_material_scanner_ray.is_colliding():
		var sound_collider = sound_material_scanner_ray.get_collider()
		if sound_collider.is_in_group("grass"):
			walk_grass.play()
			print("walk_grass")
		elif sound_collider.is_in_group("wood"):
			walk_wood.play()
			print("walk_wood")
		elif sound_collider.is_in_group("concrete"):
			walk_concrete.play()
			print("walk_concrete")
		elif sound_collider.is_in_group("metal"):
			walk_metal.play()
			print("walk_metal")
		elif sound_collider.is_in_group("carpet"):
			walk_carpet.play()
			print("walk_carpet")
		
	


func _process(_delta):
	if interaction_raycast.is_colliding():
		var collider = interaction_raycast.get_collider()
		if collider.has_method("interact"):
			if Input.is_action_just_pressed("interact"):
				collider.interact()
