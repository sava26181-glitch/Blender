extends Node3D
# НЕОН-РЕЙД — аренный шутер. Болт против Роя.
# Управление: левая половина экрана — джойстик, кнопка справа — рывок. Стрельба автоматическая.

const ARENA := 17.0
const CYAN := Color(0.02, 0.85, 0.95)
const PINK := Color(1.0, 0.1, 0.35)
const LIME := Color(0.3, 1.0, 0.15)
const GOLD := Color(1.0, 0.8, 0.1)

enum State { MENU, PLAYING, BETWEEN, OVER }
var state := State.MENU

# ресурсы
var bolt_mesh: ArrayMesh
var bug_mesh: ArrayMesh
var core_mesh: ArrayMesh
var spark_mesh: ArrayMesh
var bullet_mesh: SphereMesh
var bullet_mat: StandardMaterial3D

# мир
var cam: Camera3D
var player: Node3D
var player_model: MeshInstance3D
var enemies: Array = []   # {node, hp, speed, phase}
var bullets: Array = []   # {node, vel, life}
var loot: Node3D = null

# игрок
var hp := 100.0
var max_hp := 100.0
var damage := 34.0
var fire_delay := 0.32
var fire_cd := 0.0
var shots := 1
var speed := 7.0
var dash_cd := 0.0
var dash_time := 0.0
var invuln := 0.0
var facing := Vector3(0, 0, 1)

# прогресс
var wave := 0
var to_spawn := 0
var spawn_cd := 0.0
var between_t := 0.0
var score := 0
var best := 0
var kills := 0
var t := 0.0

# ввод
var move_input := Vector2.ZERO
var joy_index := -1
var joy: Joy
var dash_center := Vector2.ZERO
const DASH_R := 80.0

# интерфейс
var ui: CanvasLayer
var hp_fill: ColorRect
var hp_label: Label
var wave_label: Label
var score_label: Label
var toast: Label
var menu_panel: Control
var over_panel: Control
var over_label: Label
var dash_btn: DashButton

# автотест в CI (headless)
var autotest := false
var autotest_t := 0.0


class Joy extends Control:
	var center := Vector2.ZERO
	var knob := Vector2.ZERO
	var active := false
	func _draw() -> void:
		if not active:
			return
		draw_circle(center, 95.0, Color(1, 1, 1, 0.07))
		draw_arc(center, 95.0, 0.0, TAU, 64, Color(0.02, 0.85, 0.95, 0.7), 4.0, true)
		draw_circle(center + knob, 40.0, Color(0.02, 0.85, 0.95, 0.55))


class DashButton extends Control:
	var ready_ratio := 1.0
	var c := Vector2.ZERO
	func _draw() -> void:
		draw_circle(c, 80.0, Color(1, 0.1, 0.35, 0.18 + 0.25 * ready_ratio))
		draw_arc(c, 80.0, -PI / 2, -PI / 2 + TAU * ready_ratio, 64, Color(1, 0.3, 0.5, 0.95), 6.0, true)
		var f := ThemeDB.fallback_font
		var s := "РЫВОК"
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(f, c + Vector2(-w / 2, 9), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)


# ------------------------------------------------------------------ запуск
func _ready() -> void:
	randomize()
	autotest = DisplayServer.get_name() == "headless"
	bolt_mesh = flatten(load("res://models/bolt.glb") as PackedScene)
	bug_mesh = flatten(load("res://models/bug.glb") as PackedScene)
	core_mesh = flatten(load("res://models/core.glb") as PackedScene)
	spark_mesh = flatten(load("res://models/spark.glb") as PackedScene)
	bullet_mesh = SphereMesh.new()
	bullet_mesh.radius = 0.13
	bullet_mesh.height = 0.26
	bullet_mesh.radial_segments = 10
	bullet_mesh.rings = 6
	bullet_mat = glow_mat(CYAN, 6.0)
	build_world()
	build_ui()
	show_menu()
	if autotest:
		print("AUTOTEST: start")
		start_game()


func flatten(scene: PackedScene) -> ArrayMesh:
	# склеиваем все детали модели в один меш (по материалам) — так быстрее на телефоне
	var am := ArrayMesh.new()
	if scene == null:
		push_error("model not loaded")
		var bm := BoxMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
		return am
	var root := scene.instantiate()
	var groups := {}
	_collect(root, Transform3D.IDENTITY, groups)
	for key in groups.keys():
		var st: SurfaceTool = groups[key]["st"]
		st.commit(am)
		var mat = groups[key]["mat"]
		if mat != null:
			am.surface_set_material(am.get_surface_count() - 1, mat)
	root.free()
	return am


func _collect(n: Node, xf: Transform3D, groups: Dictionary) -> void:
	var tr := xf
	if n is Node3D:
		tr = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat: Material = mi.get_surface_override_material(s)
				if mat == null:
					mat = mi.mesh.surface_get_material(s)
				var key: String = str(mat.get_instance_id()) if mat != null else "none"
				if not groups.has(key):
					var st := SurfaceTool.new()
					groups[key] = {"st": st, "mat": mat}
				(groups[key]["st"] as SurfaceTool).append_from(mi.mesh, s, tr)
	for c in n.get_children():
		_collect(c, tr, groups)


func glow_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func add_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.01, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.55)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.03, 0.12)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	for p in [[Vector3(-12, 4, -12), PINK], [Vector3(12, 4, 12), CYAN], [Vector3(12, 4, -12), CYAN], [Vector3(-12, 4, 12), PINK]]:
		var ol := OmniLight3D.new()
		ol.position = p[0]
		ol.light_color = p[1]
		ol.light_energy = 3.0
		ol.omni_range = 16.0
		add_child(ol)

	# пол
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.04, 0.035, 0.08)
	floor_mat.metallic = 0.6
	floor_mat.roughness = 0.35
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ARENA * 2 + 6, ARENA * 2 + 6)
	fl.mesh = pm
	fl.material_override = floor_mat
	add_child(fl)
	# неоновая сетка
	var grid_mat := glow_mat(Color(0.25, 0.1, 0.6), 1.5)
	var i := -ARENA
	while i <= ARENA + 0.01:
		add_box(Vector3(0.05, 0.02, ARENA * 2), Vector3(i, 0.01, 0), grid_mat)
		add_box(Vector3(ARENA * 2, 0.02, 0.05), Vector3(0, 0.01, i), grid_mat)
		i += 3.4
	# стены-бортики
	var wall_c := glow_mat(CYAN, 3.0)
	var wall_p := glow_mat(PINK, 3.0)
	add_box(Vector3(ARENA * 2 + 1, 0.5, 0.3), Vector3(0, 0.25, -ARENA - 0.6), wall_c)
	add_box(Vector3(ARENA * 2 + 1, 0.5, 0.3), Vector3(0, 0.25, ARENA + 0.6), wall_c)
	add_box(Vector3(0.3, 0.5, ARENA * 2 + 1), Vector3(-ARENA - 0.6, 0.25, 0), wall_p)
	add_box(Vector3(0.3, 0.5, ARENA * 2 + 1), Vector3(ARENA + 0.6, 0.25, 0), wall_p)
	# декор: ховербайк «Искра» в углу и колонны
	var bike := MeshInstance3D.new()
	bike.mesh = spark_mesh
	bike.scale = Vector3.ONE * 0.9
	bike.position = Vector3(-ARENA + 2.5, 0, -ARENA + 2.5)
	bike.rotation.y = deg_to_rad(40)
	add_child(bike)
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.12, 0.12, 0.18)
	pillar_mat.metallic = 0.8
	pillar_mat.roughness = 0.3
	for pp in [Vector3(ARENA - 1.5, 0, ARENA - 1.5), Vector3(ARENA - 1.5, 0, -ARENA + 1.5), Vector3(-ARENA + 1.5, 0, ARENA - 1.5)]:
		add_box(Vector3(1.2, 4, 1.2), pp + Vector3(0, 2, 0), pillar_mat)
		add_box(Vector3(1.25, 0.12, 1.25), pp + Vector3(0, 3.2, 0), glow_mat(GOLD, 4.0))

	player = Node3D.new()
	add_child(player)
	player_model = MeshInstance3D.new()
	player_model.mesh = bolt_mesh
	player_model.scale = Vector3.ONE * 0.55
	player.add_child(player_model)

	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.position = Vector3(0, 14, 9)
	cam.look_at(Vector3.ZERO)


# ------------------------------------------------------------------ интерфейс
func make_label(text: String, size: int, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 96)
	b.add_theme_font_size_override("font_size", 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.3, 0.0)
	sb.set_corner_radius_all(18)
	sb.shadow_color = Color(1, 0.4, 0, 0.5)
	sb.shadow_size = 16
	var sb2: StyleBoxFlat = sb.duplicate()
	sb2.bg_color = Color(1, 0.45, 0.1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("focus", sb2)
	return b


func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	joy = Joy.new()
	full_rect(joy)
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(joy)

	dash_btn = DashButton.new()
	full_rect(dash_btn)
	dash_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(dash_btn)

	var top := MarginContainer.new()
	full_rect(top)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + side, 48)
	ui.add_child(top)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)

	var hp_box := Control.new()
	hp_box.custom_minimum_size = Vector2(320, 34)
	hp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hp_box)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.6)
	hp_bg.size = Vector2(320, 34)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_box.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.color = LIME
	hp_fill.position = Vector2(4, 4)
	hp_fill.size = Vector2(312, 26)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_box.add_child(hp_fill)
	hp_label = make_label("100", 22)
	hp_label.position = Vector2(12, 2)
	hp_box.add_child(hp_label)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	wave_label = make_label("ВОЛНА 1", 34, CYAN)
	row.add_child(wave_label)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp2)
	score_label = make_label("0", 34, GOLD)
	row.add_child(score_label)

	toast = make_label("", 52, GOLD)
	full_rect(toast)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.modulate.a = 0.0
	ui.add_child(toast)

	menu_panel = make_overlay("НЕОН-РЕЙД", "Рой захватил город. Зачисти арену!\nЛевая сторона экрана — движение, РЫВОК — уклонение.\nСтрельба автоматическая.", "ИГРАТЬ")
	var res := make_overlay("ИГРА ОКОНЧЕНА", "", "ЕЩЁ РАЗ")
	over_panel = res
	over_label = res.get_meta("sub")


func make_overlay(title: String, sub: String, btn_text: String) -> Control:
	var root := ColorRect.new()
	root.color = Color(0.01, 0.0, 0.04, 0.78)
	full_rect(root)
	ui.add_child(root)
	var cc := CenterContainer.new()
	full_rect(cc)
	root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 26)
	cc.add_child(vb)
	var tl := make_label(title, 96, Color(1, 0.4, 0.05))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_outline_color", Color(1, 0.1, 0.35))
	tl.add_theme_constant_override("outline_size", 14)
	vb.add_child(tl)
	var sl := make_label(sub, 28, Color(0.8, 0.85, 1))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sl)
	var bc := CenterContainer.new()
	vb.add_child(bc)
	var b := make_button(btn_text)
	b.pressed.connect(start_game)
	bc.add_child(b)
	root.set_meta("sub", sl)
	return root


func show_menu() -> void:
	state = State.MENU
	menu_panel.visible = true
	over_panel.visible = false


func show_toast(text: String, col: Color = GOLD) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", col)
	toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)


# ------------------------------------------------------------------ игра
func start_game() -> void:
	for e in enemies:
		e["node"].queue_free()
	enemies.clear()
	for b in bullets:
		b["node"].queue_free()
	bullets.clear()
	if loot != null:
		loot.queue_free()
		loot = null
	hp = 100.0
	max_hp = 100.0
	damage = 34.0
	fire_delay = 0.32
	shots = 1
	speed = 7.0
	score = 0
	kills = 0
	wave = 0
	dash_cd = 0.0
	invuln = 0.0
	player.position = Vector3.ZERO
	player.visible = true
	menu_panel.visible = false
	over_panel.visible = false
	next_wave()


func next_wave() -> void:
	wave += 1
	to_spawn = 4 + wave * 3
	spawn_cd = 0.5
	state = State.PLAYING
	wave_label.text = "ВОЛНА %d" % wave
	show_toast("ВОЛНА %d" % wave, CYAN)


func spawn_enemy() -> void:
	var a := randf() * TAU
	var pos := Vector3(cos(a), 0, sin(a)) * (ARENA - 0.5)
	pos.x = clamp(pos.x, -ARENA + 0.5, ARENA - 0.5)
	pos.z = clamp(pos.z, -ARENA + 0.5, ARENA - 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = bug_mesh
	var big := wave >= 3 and randf() < 0.18
	var sc := 0.62 if big else 0.42
	mi.scale = Vector3.ONE * sc
	mi.position = pos
	add_child(mi)
	var base_hp := 50.0 + wave * 12.0
	enemies.append({
		"node": mi,
		"hp": base_hp * (3.0 if big else 1.0),
		"speed": (2.6 + wave * 0.25) * (0.7 if big else 1.0) * randf_range(0.85, 1.15),
		"phase": randf() * TAU,
		"radius": 0.9 if big else 0.6,
		"dmg": 26.0 if big else 14.0,
		"points": 30 if big else 10,
	})


func _process(delta: float) -> void:
	t += delta
	if autotest:
		run_autotest(delta)
	if state == State.PLAYING or state == State.BETWEEN:
		update_game(delta)
	update_camera(delta)
	update_hud()


func read_move() -> Vector2:
	var v := move_input
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		k.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		k.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		k.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		k.y += 1
	if k != Vector2.ZERO:
		v = k.normalized()
	return v


func update_game(delta: float) -> void:
	# движение
	var mv := read_move()
	var dir := Vector3(mv.x, 0, mv.y)
	var sp := speed
	if dash_time > 0.0:
		dash_time -= delta
		sp = speed * 3.2
		if dir.length() < 0.1:
			dir = facing
		else:
			dir = dir.normalized()
	player.position += dir * sp * delta
	player.position.x = clamp(player.position.x, -ARENA, ARENA)
	player.position.z = clamp(player.position.z, -ARENA, ARENA)
	dash_cd = max(dash_cd - delta, 0.0)
	invuln = max(invuln - delta, 0.0)
	player_model.position.y = abs(sin(t * 10.0)) * 0.08 if dir.length() > 0.1 else 0.0
	player_model.visible = invuln <= 0.0 or int(t * 20.0) % 2 == 0 or dash_time > 0.0

	# цель
	var target = null
	var best_d := 13.0
	for e in enemies:
		var d: float = (e["node"].position - player.position).length()
		if d < best_d:
			best_d = d
			target = e
	if target != null:
		var to: Vector3 = target["node"].position - player.position
		to.y = 0
		facing = to.normalized()
	elif dir.length() > 0.1:
		facing = dir.normalized()
	player.rotation.y = lerp_angle(player.rotation.y, atan2(facing.x, facing.z), min(delta * 14.0, 1.0))

	# стрельба
	fire_cd -= delta
	if target != null and fire_cd <= 0.0:
		fire_cd = fire_delay
		for i in shots:
			var spread := (i - (shots - 1) / 2.0) * 0.16
			shoot(facing.rotated(Vector3.UP, spread))

	# пули
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		b["node"].position += b["vel"] * delta
		b["life"] -= delta
		var hit := false
		for e in enemies:
			var ep: Vector3 = e["node"].position
			var bp: Vector3 = b["node"].position
			if Vector2(ep.x - bp.x, ep.z - bp.z).length() < e["radius"]:
				e["hp"] -= damage
				hit = true
				spark(bp, CYAN, 0.5)
				break
		if hit or b["life"] <= 0.0:
			b["node"].queue_free()
			bullets.remove_at(i)

	# враги
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		var n: Node3D = e["node"]
		if e["hp"] <= 0.0:
			spark(n.position + Vector3(0, 0.5, 0), PINK, 2.2)
			score += e["points"]
			kills += 1
			n.queue_free()
			enemies.remove_at(i)
			continue
		var to: Vector3 = player.position - n.position
		to.y = 0
		var d := to.length()
		var mvdir := to.normalized() if d > 0.01 else Vector3.ZERO
		# не толпиться
		for o in enemies:
			if o["node"] != n:
				var aw: Vector3 = n.position - o["node"].position
				aw.y = 0
				var ad := aw.length()
				if ad > 0.001 and ad < 1.1:
					mvdir += aw / ad * (1.1 - ad) * 1.5
		n.position += mvdir.normalized() * e["speed"] * delta if mvdir.length() > 0.01 else Vector3.ZERO
		n.position.y = 0.12 + sin(t * 6.0 + e["phase"]) * 0.08
		n.rotation.y = atan2(to.x, to.z)
		if d < e["radius"] + 0.45 and invuln <= 0.0 and dash_time <= 0.0:
			hp -= e["dmg"]
			invuln = 0.8
			n.position -= mvdir.normalized() * 1.2
			spark(player.position + Vector3(0, 0.8, 0), Color(1, 0.3, 0.1), 1.5)
			if hp <= 0.0:
				game_over()
				return

	# волны
	if state == State.PLAYING:
		if to_spawn > 0:
			spawn_cd -= delta
			if spawn_cd <= 0.0:
				spawn_enemy()
				to_spawn -= 1
				spawn_cd = max(1.1 - wave * 0.07, 0.35)
		elif enemies.is_empty():
			state = State.BETWEEN
			between_t = 0.0
			score += wave * 50
			show_toast("ВОЛНА ЗАЧИЩЕНА!  +%d" % (wave * 50), LIME)
			drop_loot()
	elif state == State.BETWEEN:
		between_t += delta
		if loot != null:
			loot.rotation.y += delta * 2.0
			loot.position.y = 0.2 + sin(t * 3.0) * 0.15
			var ld := Vector2(loot.position.x - player.position.x, loot.position.z - player.position.z).length()
			if ld < 1.4:
				take_loot()
		if loot == null and between_t > 1.2:
			next_wave()
		elif between_t > 12.0:
			if loot != null:
				loot.queue_free()
				loot = null
			next_wave()


func shoot(dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = bullet_mesh
	mi.material_override = bullet_mat
	mi.position = player.position + Vector3(0, 0.75, 0) + dir * 0.7
	add_child(mi)
	bullets.append({"node": mi, "vel": dir * 22.0, "life": 0.9})


func spark(pos: Vector3, col: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 0.9)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 5.0
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 2.0, 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(mi.queue_free)


func drop_loot() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = core_mesh
	mi.scale = Vector3.ONE * 0.75
	var p := Vector3(randf_range(-8, 8), 0.2, randf_range(-8, 8))
	if Vector2(p.x - player.position.x, p.z - player.position.z).length() < 4.0:
		p = -p
	mi.position = p
	add_child(mi)
	loot = mi


func take_loot() -> void:
	spark(loot.position + Vector3(0, 0.7, 0), LIME, 3.0)
	loot.queue_free()
	loot = null
	hp = min(max_hp, hp + 30.0)
	var r := randi() % 4
	match r:
		0:
			damage += 12.0
			show_toast("УРОН +12", GOLD)
		1:
			fire_delay = max(fire_delay * 0.82, 0.08)
			show_toast("СКОРОСТРЕЛЬНОСТЬ +", GOLD)
		2:
			shots = min(shots + 1, 5)
			show_toast("ДОП. СТВОЛ: %d" % shots, GOLD)
		3:
			max_hp += 25.0
			hp = max_hp
			speed += 0.4
			show_toast("БРОНЯ + СКОРОСТЬ", GOLD)
	between_t = 0.0


func game_over() -> void:
	state = State.OVER
	hp = 0.0
	best = max(best, score)
	spark(player.position + Vector3(0, 1, 0), Color(1, 0.4, 0), 4.0)
	player.visible = false
	over_label.text = "Волна: %d    Убито жуков: %d\nОчки: %d    Рекорд: %d" % [wave, kills, score, best]
	over_panel.visible = true
	joy.active = false
	joy_index = -1
	move_input = Vector2.ZERO


func try_dash() -> void:
	if state != State.PLAYING and state != State.BETWEEN:
		return
	if dash_cd > 0.0:
		return
	dash_cd = 1.6
	dash_time = 0.2
	invuln = max(invuln, 0.3)
	spark(player.position + Vector3(0, 0.6, 0), PINK, 1.2)


func update_camera(delta: float) -> void:
	var target_pos := player.position + Vector3(0, 13.5, 8.5)
	cam.position = cam.position.lerp(target_pos, min(delta * 5.0, 1.0))
	cam.look_at(cam.position - Vector3(0, 13.5, 8.5))


func update_hud() -> void:
	var r: float = clamp(hp / max_hp, 0.0, 1.0)
	hp_fill.size.x = 312.0 * r
	hp_fill.color = LIME.lerp(Color(1, 0.15, 0.2), 1.0 - r)
	hp_label.text = "HP %d / %d" % [int(ceil(hp)), int(max_hp)]
	score_label.text = "ОЧКИ %d" % score
	var vs := get_viewport().get_visible_rect().size
	dash_center = Vector2(vs.x - 150, vs.y - 150)
	dash_btn.c = dash_center
	dash_btn.ready_ratio = 1.0 - dash_cd / 1.6
	dash_btn.visible = state == State.PLAYING or state == State.BETWEEN
	dash_btn.queue_redraw()


# ------------------------------------------------------------------ ввод
func _input(event: InputEvent) -> void:
	if state != State.PLAYING and state != State.BETWEEN:
		return
	var vs := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			if te.position.distance_to(dash_center) < DASH_R + 30:
				try_dash()
			elif te.position.x < vs.x * 0.6 and joy_index == -1:
				joy_index = te.index
				joy.center = te.position
				joy.knob = Vector2.ZERO
				joy.active = true
		elif te.index == joy_index:
			joy_index = -1
			joy.active = false
			move_input = Vector2.ZERO
		joy.queue_redraw()
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == joy_index:
			var d := de.position - joy.center
			if d.length() > 95.0:
				d = d.normalized() * 95.0
			joy.knob = d
			move_input = d / 95.0
			joy.queue_redraw()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_SPACE:
			try_dash()


# ------------------------------------------------------------------ автотест (только в CI)
func run_autotest(delta: float) -> void:
	autotest_t += delta
	move_input = Vector2(cos(autotest_t * 0.7), sin(autotest_t * 0.7))
	if int(autotest_t * 10) % 25 == 0:
		try_dash()
	if state == State.BETWEEN and loot != null:
		player.position = loot.position
	if state == State.OVER:
		print("AUTOTEST: game over at wave %d, restarting" % wave)
		start_game()
	if int(autotest_t) != int(autotest_t - delta):
		print("AUTOTEST t=%d wave=%d enemies=%d bullets=%d hp=%d score=%d" % [int(autotest_t), wave, enemies.size(), bullets.size(), int(hp), score])
	if autotest_t > 40.0:
		print("AUTOTEST OK")
		get_tree().quit(0)
