extends Control

const PLAYER_TEXTURE: Texture2D = preload("res://Piłka-Gracz.png")
const ENEMY_TEXTURE: Texture2D = preload("res://Kostka-Enemy.png")
const MENU_BUTTON_TEXTURE: Texture2D = preload("res://Assets/UI/menu_button.png")
const UI_FONT: Font = preload("res://Assets/UI/augiepixel.ttf")

const BALL_RADIUS: float = 19.0
const ENEMY_RADIUS: float = 28.0
const ENEMY_HP: int = 2
const BALL_SPEED: float = 350.0
const AIM_TRIGGER_TIME: float = 0.62
const AIM_TIME_SCALE: float = 0.32
const MAX_LEVELS: int = 3
const ENEMY_FLEE_SPEED: float = 125.0
const ENEMY_FLEE_RANGE: float = 300.0

enum GameMode { MENU, PLAYING, LEVEL_CLEAR, WON, LOST }

var game_mode: GameMode = GameMode.MENU
var arena := Rect2()
var view_size := Vector2.ZERO
var ball_position := Vector2.ZERO
var ball_velocity := Vector2.ZERO
var enemies: Array = []
var wall_bounces_since_targeted: int = 0
var targeted_bounce_active: bool = false
var level_index: int = 0
var player_hp: int = 0
var player_max_hp: int = 0
var aiming: bool = false
var aim_locked: bool = false
var aim_normal := Vector2.UP
var aim_point := Vector2.ZERO
var aim_direction := Vector2.UP
var aim_preview_points: Array[Vector2] = []
var aim_preview_hit_position := Vector2.ZERO
var aim_preview_exit_position := Vector2.ZERO
var aim_preview_enemy_index: int = -1
var camera_zoom: float = 1.0
var hit_flash: float = 0.0
var shake_timer: float = 0.0
var elapsed: float = 0.0

var start_button := Rect2()
var continue_button := Rect2()
var retry_button := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout()


func _on_viewport_size_changed() -> void:
	_layout()
	queue_redraw()


func _layout() -> void:
	view_size = get_viewport_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return

	var arena_width: float = minf(view_size.x * 0.84, view_size.y * 1.25)
	var arena_height: float = minf(view_size.y * 0.76, view_size.x * 0.68)
	var ratio: float = arena_width / arena_height
	if ratio > 1.72:
		arena_width = arena_height * 1.72
	elif ratio < 1.20:
		arena_height = arena_width / 1.20

	var top_limit: float = minf(116.0, view_size.y * 0.16)
	arena = Rect2(
		Vector2((view_size.x - arena_width) * 0.5, maxf(top_limit, (view_size.y - arena_height) * 0.52)),
		Vector2(arena_width, arena_height)
	)
	if arena.end.y > view_size.y - 28.0:
		arena.position.y = view_size.y - arena.size.y - 28.0

	start_button = Rect2(Vector2(view_size.x * 0.5 - 150.0, view_size.y * 0.62), Vector2(300.0, 72.0))
	continue_button = Rect2(Vector2(view_size.x * 0.5 - 165.0, view_size.y * 0.59), Vector2(330.0, 80.0))
	retry_button = Rect2(Vector2(view_size.x * 0.5 - 165.0, view_size.y * 0.62), Vector2(330.0, 80.0))

	if game_mode == GameMode.PLAYING:
		_place_enemies_for_current_level()


func _place_enemies_for_current_level() -> void:
	if enemies.is_empty():
		return
	var spots: Array[Vector2] = [
		Vector2(0.25, 0.28),
		Vector2(0.50, 0.26),
		Vector2(0.75, 0.28),
		Vector2(0.36, 0.52),
		Vector2(0.64, 0.52),
	]
	for i in range(enemies.size()):
		var spot: Vector2 = spots[i % spots.size()]
		var spawn_position: Vector2 = arena.position + arena.size * spot
		enemies[i]["position"] = spawn_position


func _start_game() -> void:
	level_index = 0
	_start_level()


func _start_level() -> void:
	game_mode = GameMode.PLAYING
	aiming = false
	aim_locked = false
	aim_preview_points.clear()
	aim_preview_enemy_index = -1
	wall_bounces_since_targeted = 0
	targeted_bounce_active = false
	camera_zoom = 1.0
	hit_flash = 0.0
	shake_timer = 0.0

	var enemy_count: int = 3 + level_index
	enemies.clear()
	for i in range(enemy_count):
		enemies.append({
			"position": Vector2.ZERO,
			"hp": ENEMY_HP,
			"max_hp": ENEMY_HP,
			"touching": false,
			"evasion_direction": Vector2.ZERO,
			"evasion_timer": 0.0,
		})

	_place_enemies_for_current_level()
	var total_enemy_hp: int = enemy_count * ENEMY_HP
	player_max_hp = total_enemy_hp * 2
	player_hp = player_max_hp
	ball_position = Vector2(arena.position.x + arena.size.x * 0.5, arena.position.y + arena.size.y * 0.78)
	ball_velocity = Vector2(0.58, -0.82).normalized() * BALL_SPEED
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	var mouse_position: Vector2 = event.position
	match game_mode:
		GameMode.MENU:
			if start_button.has_point(mouse_position):
				_start_game()
		GameMode.PLAYING:
			if aiming:
				aim_direction = _get_aim_direction(get_local_mouse_position(), aim_point, aim_normal)
				aim_locked = true
		GameMode.LEVEL_CLEAR:
			if continue_button.has_point(mouse_position):
				level_index += 1
				_start_level()
		GameMode.WON, GameMode.LOST:
			if retry_button.has_point(mouse_position):
				_start_game()

	accept_event()


func _process(delta: float) -> void:
	elapsed += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	shake_timer = maxf(0.0, shake_timer - delta)

	if game_mode == GameMode.PLAYING:
		_update_game(delta)

	queue_redraw()


func _update_game(delta: float) -> void:
	var prediction: Dictionary = _predict_wall()
	var was_aiming: bool = aiming
	aiming = float(prediction["time"]) <= AIM_TRIGGER_TIME
	if aiming and not was_aiming:
		aim_locked = false
	if aiming:
		aim_normal = prediction["normal"]
		aim_point = prediction["point"]
		if not aim_locked:
			aim_direction = _get_aim_direction(get_local_mouse_position(), aim_point, aim_normal)

	var game_delta: float = delta * (AIM_TIME_SCALE if aiming else 1.0)
	if hit_flash > 0.0 and shake_timer > 0.0:
		game_delta *= 0.25

	ball_position += ball_velocity * game_delta
	_handle_wall_collisions()
	_update_enemies(game_delta)
	_handle_enemy_collisions()
	_update_aim_preview()

	var zoom_target: float = 1.075 if aiming else 1.0
	camera_zoom = lerpf(camera_zoom, zoom_target, 1.0 - exp(-delta * 5.0))

	if player_hp <= 0:
		game_mode = GameMode.LOST
	elif enemies.is_empty():
		game_mode = GameMode.WON if level_index >= MAX_LEVELS - 1 else GameMode.LEVEL_CLEAR


func _update_aim_preview() -> void:
	aim_preview_points.clear()
	aim_preview_enemy_index = -1
	if not aiming:
		return

	var direction: Vector2 = ball_velocity.normalized()
	var start: Vector2 = ball_position
	aim_preview_points.append(start)
	var first_hit: Dictionary = _find_enemy_hit_on_segment(start, aim_point)
	if not first_hit.is_empty():
		_store_aim_preview_hit(first_hit, direction)
		return

	aim_preview_points.append(aim_point)
	start = aim_point
	direction = aim_direction
	for _bounce_index in range(4):
		var wall_hit: Dictionary = _find_next_wall_hit(start, direction)
		if wall_hit.is_empty():
			return
		var end: Vector2 = wall_hit["point"]
		var enemy_hit: Dictionary = _find_enemy_hit_on_segment(start, end)
		if not enemy_hit.is_empty():
			_store_aim_preview_hit(enemy_hit, direction)
			return
		aim_preview_points.append(end)
		start = end
		direction = direction.bounce(wall_hit["normal"]).normalized()


func _find_enemy_hit_on_segment(start: Vector2, end: Vector2) -> Dictionary:
	var segment: Vector2 = end - start
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared < 0.0001:
		return {}

	var earliest_t: float = INF
	var hit: Dictionary = {}
	var hit_radius: float = BALL_RADIUS + ENEMY_RADIUS
	for i in range(enemies.size()):
		var enemy_position: Vector2 = enemies[i]["position"]
		var offset: Vector2 = start - enemy_position
		var c: float = offset.length_squared() - hit_radius * hit_radius
		var hit_t: float = 0.0
		if c > 0.0:
			var b: float = 2.0 * offset.dot(segment)
			var discriminant: float = b * b - 4.0 * segment_length_squared * c
			if discriminant < 0.0:
				continue
			hit_t = (-b - sqrt(discriminant)) / (2.0 * segment_length_squared)
			if hit_t < 0.0 or hit_t > 1.0:
				continue
		if hit_t < earliest_t:
			earliest_t = hit_t
			hit = {
				"position": start + segment * hit_t,
				"enemy_index": i,
				"enemy_position": enemy_position,
			}
	return hit


func _find_next_wall_hit(start: Vector2, direction: Vector2) -> Dictionary:
	var left: float = arena.position.x + BALL_RADIUS
	var right: float = arena.end.x - BALL_RADIUS
	var top: float = arena.position.y + BALL_RADIUS
	var bottom: float = arena.end.y - BALL_RADIUS
	var time_x: float = INF
	var time_y: float = INF
	var normal_x := Vector2.ZERO
	var normal_y := Vector2.ZERO

	if direction.x > 0.0001:
		time_x = (right - start.x) / direction.x
		normal_x = Vector2.LEFT
	elif direction.x < -0.0001:
		time_x = (left - start.x) / direction.x
		normal_x = Vector2.RIGHT
	if direction.y > 0.0001:
		time_y = (bottom - start.y) / direction.y
	elif direction.y < -0.0001:
		time_y = (top - start.y) / direction.y
		normal_y = Vector2.DOWN if direction.y < 0.0 else Vector2.UP
	if direction.y > 0.0001:
		normal_y = Vector2.UP

	if time_x == INF and time_y == INF:
		return {}
	if time_x <= time_y:
		var point := start + direction * time_x
		point.x = right if direction.x > 0.0 else left
		return {"point": point, "normal": normal_x}

	var vertical_point := start + direction * time_y
	vertical_point.y = bottom if direction.y > 0.0 else top
	return {"point": vertical_point, "normal": normal_y}


func _store_aim_preview_hit(hit: Dictionary, direction: Vector2) -> void:
	aim_preview_hit_position = hit["position"]
	aim_preview_enemy_index = int(hit["enemy_index"])
	var normal: Vector2 = (aim_preview_hit_position - hit["enemy_position"]).normalized()
	if normal.length_squared() < 0.0001:
		normal = -direction
	var exit_direction: Vector2 = direction.bounce(normal).normalized()
	aim_preview_exit_position = aim_preview_hit_position + exit_direction * 52.0
	aim_preview_points.append(aim_preview_hit_position)
	aim_preview_points.append(aim_preview_exit_position)


func _update_enemies(delta: float) -> void:
	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i]
		var position: Vector2 = enemy["position"]
		var distance: float = position.distance_to(ball_position)
		enemy["evasion_timer"] = float(enemy["evasion_timer"]) - delta

		if distance <= ENEMY_FLEE_RANGE:
			if float(enemy["evasion_timer"]) <= 0.0:
				var away: Vector2 = position - ball_position
				if away.length_squared() < 0.01:
					away = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
				else:
					away = away.normalized()
				var side: Vector2 = Vector2(-away.y, away.x)
				if randf() < 0.5:
					side = -side
				enemy["evasion_direction"] = (away + side * randf_range(0.45, 1.15)).normalized()
				enemy["evasion_timer"] = randf_range(0.45, 0.9)
			position += enemy["evasion_direction"] * ENEMY_FLEE_SPEED * delta
		else:
			enemy["evasion_direction"] = Vector2.ZERO

		var min_bound := Vector2(arena.position.x + ENEMY_RADIUS, arena.position.y + ENEMY_RADIUS)
		var max_bound := Vector2(arena.end.x - ENEMY_RADIUS, arena.end.y - ENEMY_RADIUS)
		var next_position: Vector2 = position
		var evasion_direction: Vector2 = enemy["evasion_direction"]
		if next_position.x <= min_bound.x or next_position.x >= max_bound.x:
			evasion_direction.x = -evasion_direction.x
		if next_position.y <= min_bound.y or next_position.y >= max_bound.y:
			evasion_direction.y = -evasion_direction.y
		enemy["evasion_direction"] = evasion_direction
		position = next_position.clamp(min_bound, max_bound)
		enemy["position"] = position


func _predict_wall() -> Dictionary:
	var left: float = arena.position.x + BALL_RADIUS
	var right: float = arena.end.x - BALL_RADIUS
	var top: float = arena.position.y + BALL_RADIUS
	var bottom: float = arena.end.y - BALL_RADIUS
	var time_x: float = INF
	var normal_x := Vector2.ZERO
	var time_y: float = INF
	var normal_y := Vector2.ZERO

	if ball_velocity.x > 0.0:
		time_x = (right - ball_position.x) / ball_velocity.x
		normal_x = Vector2.LEFT
	elif ball_velocity.x < 0.0:
		time_x = (left - ball_position.x) / ball_velocity.x
		normal_x = Vector2.RIGHT
	if ball_velocity.y > 0.0:
		time_y = (bottom - ball_position.y) / ball_velocity.y
		normal_y = Vector2.UP
	elif ball_velocity.y < 0.0:
		time_y = (top - ball_position.y) / ball_velocity.y
		normal_y = Vector2.DOWN

	if time_x <= time_y:
		var x_point := ball_position + ball_velocity * maxf(0.0, time_x)
		x_point.x = right if ball_velocity.x > 0.0 else left
		return {"time": maxf(0.0, time_x), "normal": normal_x, "point": x_point}

	var y_point := ball_position + ball_velocity * maxf(0.0, time_y)
	y_point.y = bottom if ball_velocity.y > 0.0 else top
	return {"time": maxf(0.0, time_y), "normal": normal_y, "point": y_point}


func _get_aim_direction(mouse_position: Vector2, origin: Vector2, normal: Vector2) -> Vector2:
	var raw_direction: Vector2 = mouse_position - origin
	if raw_direction.length_squared() < 0.0001:
		return normal
	raw_direction = raw_direction.normalized()
	var tangent: Vector2 = Vector2(-normal.y, normal.x)
	var angle: float = atan2(raw_direction.dot(tangent), raw_direction.dot(normal))
	angle = clampf(angle, -PI * 0.5 + 0.04, PI * 0.5 - 0.04)
	return normal.rotated(angle).normalized()


func _handle_wall_collisions() -> void:
	var left: float = arena.position.x + BALL_RADIUS
	var right: float = arena.end.x - BALL_RADIUS
	var top: float = arena.position.y + BALL_RADIUS
	var bottom: float = arena.end.y - BALL_RADIUS

	if ball_position.x < left:
		ball_position.x = left
		_bounce(Vector2.RIGHT)
	elif ball_position.x > right:
		ball_position.x = right
		_bounce(Vector2.LEFT)
	if ball_position.y < top:
		ball_position.y = top
		_bounce(Vector2.DOWN)
	elif ball_position.y > bottom:
		ball_position.y = bottom
		_bounce(Vector2.UP)


func _bounce(normal: Vector2) -> void:
	if aiming and aim_locked:
		player_hp = maxi(0, player_hp - 1)
		targeted_bounce_active = true
		wall_bounces_since_targeted = 0
		var selected: Vector2 = _get_aim_direction(aim_direction, Vector2.ZERO, normal)
		ball_velocity = selected * BALL_SPEED
	else:
		if targeted_bounce_active:
			wall_bounces_since_targeted += 1
		ball_velocity = ball_velocity.bounce(normal).normalized() * BALL_SPEED
	aiming = false
	aim_locked = false
	shake_timer = 0.08


func _handle_enemy_collisions() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		var enemy_position: Vector2 = enemy["position"]
		var difference: Vector2 = ball_position - enemy_position
		var hit_distance: float = BALL_RADIUS + ENEMY_RADIUS
		if difference.length() <= hit_distance:
			if not bool(enemy["touching"]):
				enemy["touching"] = true
				var enemy_damage: int = 1 + wall_bounces_since_targeted if targeted_bounce_active else 1
				enemy["hp"] = maxi(0, int(enemy["hp"]) - enemy_damage)
				targeted_bounce_active = false
				wall_bounces_since_targeted = 0
				var normal: Vector2 = difference.normalized()
				if normal.length_squared() < 0.01:
					normal = -ball_velocity.normalized()
				ball_position = enemy_position + normal * (hit_distance + 1.0)
				aiming = false
				aim_locked = false
				ball_velocity = ball_velocity.bounce(normal).normalized() * BALL_SPEED
				hit_flash = 0.11
				shake_timer = 0.12
				if int(enemy["hp"]) <= 0:
					enemies.remove_at(i)
					continue
		else:
			enemy["touching"] = false


func _draw() -> void:
	_draw_background()
	if game_mode == GameMode.MENU:
		_draw_menu()
		return
	if game_mode == GameMode.PLAYING or game_mode == GameMode.LEVEL_CLEAR or game_mode == GameMode.WON or game_mode == GameMode.LOST:
		_draw_game_world()
		_draw_hud()
	if game_mode == GameMode.LEVEL_CLEAR:
		_draw_overlay("POZIOM UKONCZONY", "Kolejna arena czeka.", continue_button, "NASTEPNY")
	elif game_mode == GameMode.WON:
		_draw_overlay("ZWYCIESTWO", "Wszystkie areny ukonczone.", retry_button, "JESZCZE RAZ")
	elif game_mode == GameMode.LOST:
		_draw_overlay("KONIEC GRY", "HP pilki sie skonczylo.", retry_button, "JESZCZE RAZ")


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), Color("#101211"))
	draw_line(Vector2(24.0, 46.0), Vector2(view_size.x - 24.0, 46.0), Color("#38423b"), 1.0)
	draw_string(UI_FONT, Vector2(28.0, 32.0), "HOLLOW BALLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#aeb6a6"))


func _draw_menu() -> void:
	var center_x: float = view_size.x * 0.5
	draw_string(UI_FONT, Vector2(0.0, view_size.y * 0.39), "HOLLOW BALLS", HORIZONTAL_ALIGNMENT_CENTER, view_size.x, 54, Color("#e6e8df"))
	draw_string(UI_FONT, Vector2(0.0, view_size.y * 0.46), "3 ARENY  /  JEDNA PILKA", HORIZONTAL_ALIGNMENT_CENTER, view_size.x, 20, Color("#8f998b"))
	_draw_button(start_button, "GRAJ")
	draw_string(UI_FONT, Vector2(center_x - 300.0, view_size.y * 0.79), "KLIK: CELOWANE ODBICIE  (-1 HP)", HORIZONTAL_ALIGNMENT_CENTER, 600.0, 15, Color("#727b70"))


func _draw_game_world() -> void:
	var anchor: Vector2 = aim_point if aiming else ball_position
	var offset: Vector2 = anchor * (1.0 - camera_zoom)
	draw_set_transform(offset, 0.0, Vector2(camera_zoom, camera_zoom))

	draw_rect(arena, Color("#171a17"))
	draw_rect(arena, Color("#70796b"), false, 1.0)

	for enemy_variant in enemies:
		var enemy: Dictionary = enemy_variant
		_draw_enemy(enemy)

	var ball_rect := Rect2(ball_position - Vector2(25.0, 25.0), Vector2(50.0, 50.0))
	draw_texture_rect(PLAYER_TEXTURE, ball_rect, false, Color("#f5f2e9"))

	if aiming:
		for i in range(aim_preview_points.size() - 1):
			var segment_color := Color(0.72, 0.76, 0.68, 0.45)
			if aim_preview_enemy_index >= 0 and i >= aim_preview_points.size() - 2:
				segment_color = Color("#d6c784")
			draw_line(aim_preview_points[i], aim_preview_points[i + 1], segment_color, 1.5)

		var guide_end: Vector2 = aim_point + aim_direction * 92.0
		_draw_dashed_line(aim_point, guide_end, Color("#d8d0a6") if aim_locked else Color("#aeb6a6"), 1.5)
		draw_circle(aim_point, 7.0, Color("#f8d878"))
		if aim_preview_enemy_index >= 0:
			draw_circle(aim_preview_hit_position, 4.0, Color("#e8d796"))
			draw_line(
				aim_preview_hit_position + Vector2(-7.0, -7.0),
				aim_preview_hit_position + Vector2(7.0, 7.0),
				Color("#e8d796"),
				1.0
			)
			draw_line(
				aim_preview_hit_position + Vector2(-7.0, 7.0),
				aim_preview_hit_position + Vector2(7.0, -7.0),
				Color("#e8d796"),
				1.0
			)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_enemy(enemy: Dictionary) -> void:
	var center: Vector2 = enemy["position"]
	var enemy_rect := Rect2(center - Vector2(28.0, 28.0), Vector2(56.0, 56.0))
	draw_texture_rect(ENEMY_TEXTURE, enemy_rect, false, Color("#e9e9df"))

	var hp_start: Vector2 = center + Vector2(-6.0, -38.0)
	for i in range(int(enemy["max_hp"])):
		var pip_color: Color = Color("#d8ddd1") if i < int(enemy["hp"]) else Color("#424840")
		draw_rect(Rect2(hp_start + Vector2(i * 9.0, 0.0), Vector2(6.0, 3.0)), pip_color)

	var evasion_direction: Vector2 = enemy["evasion_direction"]
	if evasion_direction.length_squared() > 0.01:
		draw_line(center, center + evasion_direction * 30.0, Color("#858d7f"), 1.0)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var difference: Vector2 = to - from
	var distance: float = difference.length()
	if distance <= 0.0:
		return
	var direction: Vector2 = difference / distance
	var dash_length: float = 10.0
	var gap_length: float = 7.0
	var cursor: float = 0.0
	while cursor < distance:
		var dash_end: float = minf(cursor + dash_length, distance)
		draw_line(from + direction * cursor, from + direction * dash_end, color, width)
		cursor += dash_length + gap_length


func _draw_hud() -> void:
	var label_y: float = maxf(61.0, arena.position.y - 32.0)
	draw_string(UI_FONT, Vector2(arena.position.x, label_y), "ARENA %d / %d" % [level_index + 1, MAX_LEVELS], HORIZONTAL_ALIGNMENT_LEFT, 210.0, 17, Color("#d0d5c9"))
	var damage_preview: int = 1 + (wall_bounces_since_targeted if targeted_bounce_active else 0)
	draw_string(
		UI_FONT,
		Vector2(arena.end.x, label_y),
		"WROGOW %d  /  DMG %d" % [enemies.size(), damage_preview],
		HORIZONTAL_ALIGNMENT_RIGHT,
		300.0,
		17,
		Color("#c3c9b9")
	)
	if targeted_bounce_active:
		draw_string(
			UI_FONT,
			Vector2(arena.end.x, label_y + 22.0),
			"ODBICIA SCIAN: %d" % wall_bounces_since_targeted,
			HORIZONTAL_ALIGNMENT_RIGHT,
			260.0,
			14,
			Color("#92998b")
		)

	var hp_bar := Rect2(Vector2(arena.position.x, arena.end.y + 16.0), Vector2(minf(280.0, arena.size.x * 0.42), 8.0))
	draw_rect(hp_bar, Color("#3d433b"))
	var ratio: float = clampf(float(player_hp) / float(maxi(1, player_max_hp)), 0.0, 1.0)
	var hp_color: Color = Color("#cdd7b0") if ratio > 0.35 else Color("#d58b7c")
	draw_rect(Rect2(hp_bar.position, Vector2(hp_bar.size.x * ratio, hp_bar.size.y)), hp_color)
	draw_string(UI_FONT, hp_bar.position + Vector2(0.0, 30.0), "PILKA  %d / %d" % [player_hp, player_max_hp], HORIZONTAL_ALIGNMENT_LEFT, hp_bar.size.x + 40.0, 14, Color("#b2b9ad"))

	var help_text: String = "CELOWANE ODBICIE: -1 HP" if aiming and not aim_locked else "KAT ZATWIERDZONY: -1 HP" if aiming else "WROGOWIE UCIEKAJA PRZED PILKA"
	draw_string(UI_FONT, Vector2(arena.end.x, arena.end.y + 30.0), help_text, HORIZONTAL_ALIGNMENT_RIGHT, arena.size.x * 0.62, 14, Color("#8f998b"))


func _draw_overlay(title: String, subtitle: String, button_rect: Rect2, button_label: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.04, 0.05, 0.04, 0.78))
	draw_string(UI_FONT, Vector2(0.0, view_size.y * 0.43), title, HORIZONTAL_ALIGNMENT_CENTER, view_size.x, 36, Color("#e5e7db"))
	draw_string(UI_FONT, Vector2(0.0, view_size.y * 0.49), subtitle, HORIZONTAL_ALIGNMENT_CENTER, view_size.x, 16, Color("#a4aa9c"))
	_draw_button(button_rect, button_label)


func _draw_button(button_rect: Rect2, label: String) -> void:
	var hovered: bool = button_rect.has_point(get_local_mouse_position())
	var fill: Color = Color("#f0f2e7") if hovered else Color("#aeb6a6")
	var button_width: float = minf(button_rect.size.x - 10.0, 310.0)
	var button_height: float = button_width / 6.0
	var texture_rect := Rect2(
		Vector2(button_rect.get_center().x - button_width * 0.5, button_rect.get_center().y - button_height * 0.5),
		Vector2(button_width, button_height)
	)
	draw_texture_rect(MENU_BUTTON_TEXTURE, texture_rect, false, fill)
	draw_string(UI_FONT, Vector2(button_rect.position.x + 14.0, button_rect.position.y + 45.0), label, HORIZONTAL_ALIGNMENT_CENTER, button_rect.size.x - 28.0, 22, Color("#121412"))
