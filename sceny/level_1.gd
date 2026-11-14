extends Node2D

@onready var moves_number = 4

func _ready() -> void:
	Global.max_moves = moves_number
