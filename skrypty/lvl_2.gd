extends Node2D

@onready var moves_number = 3
@onready var total_gems = 1

func _ready() -> void:
	Global.max_moves = moves_number
	Global.total_gems = total_gems
