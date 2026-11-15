extends Node2D

@onready var moves_number = 5
@onready var total_gems = 3

func _ready() -> void:
	Global.max_moves = moves_number
	Global.total_gems = total_gems
