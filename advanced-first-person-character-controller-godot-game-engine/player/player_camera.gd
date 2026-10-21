extends Camera3D

@export var head_path: NodePath
@onready var head = get_node(head_path)

# Säädä tätä (esim. 10.0 - 20.0). Pienempi luku = pehmeämpi, mutta hitaampi.
@export var smooth_speed: float = 15.0 

func _ready():
	# Irrotetaan kamera hahmon hierarkiasta, jotta se voi liikkua vapaasti
	set_as_top_level(true)

func _physics_process(delta):
	# Lasketaan tavoitesijainti (pään paikka)
	var target_transform = head.global_transform
	
	# Pehmennetään siirtymää (lerp = linear interpolation)
	global_transform.origin = global_transform.origin.lerp(target_transform.origin, smooth_speed * delta)
	
	# Pidetään kameran kulma samana kuin päällä (hiiri-ohjaus)
	global_transform.basis = target_transform.basis
