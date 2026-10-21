extends StaticBody3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var open = false

func interact():
	if open == false:
		animation_player.play("door_open")
		open = true
	elif open == true:
		animation_player.play_backwards("door_open")
		open = false
