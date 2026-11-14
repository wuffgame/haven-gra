extends Node

var total_gems: int = 0
var collected_gems: int = 0

func _ready() -> void:
	reset_level()

func reset_level() -> void:
	await get_tree().process_frame
	total_gems = get_tree().get_nodes_in_group("gems").size()
	print("w tym poziomie trzea zebrac ", total_gems)

func gem_collected() -> void:
	collected_gems += 1
	print("zebrales gem ", collected_gems, "/", total_gems)
	
	if collected_gems >= total_gems:
		win_level()

func win_level() -> void:
	print("przeszedles lvl")
