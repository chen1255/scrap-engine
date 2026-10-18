class_name HoloInspector
extends Control
## 全息检视台：没有外部美术素材，所有物品模型都由程序化图元拼出来，
## 再套一层全息着色器统一质感。支持拖拽旋转、滚轮缩放、自动旋转、线框模式。
## 后续要换成真模型时，只要替换 _build_model 即可，接口不用动。

const SHADER_PATH := "res://shaders/hologram.gdshader"
const ICON_SHADER_PATH := "res://shaders/hologram_icon.gdshader"

var _svc: SubViewportContainer
var _sv: SubViewport
var _cam: Camera3D
var _root: Node3D
var _model: Node3D
var _mesh_nodes: Array = []
var _base_colors: Array = []
var _spin := true
var _wire := false
var _icon_mode := false
var _dragging := false
var _yaw := 0.4
var _pitch := -0.22
var _dist := 3.1
var _focus := Vector3.ZERO
var _output_tint: Array = []

func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(260, 260)
	_build_viewport()
	_update_camera()

func _build_viewport() -> void:
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_svc)

	_sv = SubViewport.new()
	_sv.transparent_bg = true
	_sv.size = Vector2i(640, 640)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.msaa_3d = Viewport.MSAA_4X
	_svc.add_child(_sv)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0

	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.05
	_cam.far = 100.0
	_cam.environment = env
	_sv.add_child(_cam)

	_root = Node3D.new()
	_sv.add_child(_root)

# ---------------- 对外接口 ----------------

func show_item(item_id: String) -> void:
	_output_tint.clear()
	_focus = Vector3.ZERO
	_clear_model()
	var item: Dictionary = GameData.get_item(item_id)
	if item.is_empty():
		return
	_model = _build_model(item)
	_root.add_child(_model)
	_apply_colors()
	_update_camera()

## 图鉴未收录卡专用：生成一个「未知」占位模型（一个问号）。
## 不是真实物品，只用于离线烘焙出 _unknown.png 给锁定卡当图标。
func show_placeholder() -> void:
	_output_tint.clear()
	_focus = Vector3.ZERO
	_clear_model()
	_model = _build_placeholder()
	_root.add_child(_model)
	_update_camera()

func _build_placeholder() -> Node3D:
	var holder := Node3D.new()
	var col := Color("#A8B6CC")
	var c := Vector3(0, 0.22, 0)
	var r := 0.28
	var a0 := deg_to_rad(170.0)
	var a1 := deg_to_rad(-40.0)
	var seg := 11
	# 问号的头部圆弧：沿圆周摆一串小方块，方块朝向切线
	for i in range(seg):
		var a: float = lerp(a0, a1, float(i) / float(seg - 1))
		var pos := c + Vector3(cos(a) * r, sin(a) * r, 0.0)
		_mesh_nodes.append(_mesh(holder, "box", col, pos, Vector3(0, 0, a + PI * 0.5), Vector3(0.14, 0.13, 0.20)))
		_base_colors.append(col)
	# 尾部斜杆：从圆弧末端连到中下部
	var head_end := c + Vector3(cos(a1) * r, sin(a1) * r, 0.0)
	var tail_end := Vector3(0.02, -0.08, 0.0)
	var d := tail_end - head_end
	_mesh_nodes.append(_mesh(holder, "box", col, (head_end + tail_end) * 0.5,
		Vector3(0, 0, atan2(-d.x, d.y)), Vector3(0.14, d.length() + 0.10, 0.20)))
	_base_colors.append(col)
	# 底部圆点
	_mesh_nodes.append(_mesh(holder, "sphere", col, Vector3(0.02, -0.30, 0.0), Vector3.ZERO, Vector3(0.28, 0.28, 0.28)))
	_base_colors.append(col)
	return holder

func clear_item() -> void:
	_output_tint.clear()
	_clear_model()

## 拆解台用：把模型部件按「即将产出的材料」着色，直观看到能拆出什么
func set_output_tint(out_ids: Array) -> void:
	_output_tint = out_ids
	_apply_colors()

func set_spin(v: bool) -> void:
	_spin = v

func is_spinning() -> bool:
	return _spin

func set_wire(v: bool) -> void:
	_wire = v
	if _icon_mode:
		return
	for m in _mesh_nodes:
		var mat := (m as MeshInstance3D).material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("wire_amount", 1.0 if _wire else 0.0)

## 切到「实体图标」材质（正常混合、实心、假光照），只在离线烘焙图标时用。
## 必须在 show_item 之前调用，材质才会按新模式创建。
func set_icon_mode(on: bool) -> void:
	_icon_mode = on

## 固定观察角度。离线烘焙图标时用，保证所有物品用同一视角出图。
func set_view(new_yaw: float, new_pitch: float, new_dist: float) -> void:
	_yaw = new_yaw
	_pitch = new_pitch
	_dist = new_dist
	_update_camera()

## 按当前模型的包围盒自动取景，让 42 件物品出图大小一致（离线烘焙图标用）。
## 不同形状的图元尺寸差别很大，固定距离会导致有的占满画面、有的只有一半。
func fit_view(margin := 1.35) -> void:
	if _mesh_nodes.is_empty():
		return
	var box := AABB()
	var first := true
	for m in _mesh_nodes:
		var mi := m as MeshInstance3D
		var a: AABB = mi.get_aabb()
		var t := mi.transform
		for i in range(8):
			var wp := t * a.get_endpoint(i)
			if first:
				box = AABB(wp, Vector3.ZERO)
				first = false
			else:
				box = box.expand(wp)
	_focus = box.get_center()
	var half := maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.5
	var fov_half := deg_to_rad(_cam.fov * 0.5)
	_dist = clampf(half * margin / tan(fov_half), 1.3, 8.0)
	_update_camera()

## 抓取当前 SubViewport 的这一帧，供离线烘焙图标使用。
## 调用前需保证节点已在场景树中、且已渲染过至少一帧（有渲染设备时才有图像）。
func capture_image() -> Image:
	if _sv == null:
		return null
	var tex := _sv.get_texture()
	if tex == null:
		return null
	return tex.get_image()

func _clear_model() -> void:
	_mesh_nodes.clear()
	_base_colors.clear()
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = null

# ---------------- 模型构建 ----------------

func _build_model(item: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var shape := str(item.get("shape", "cube"))
	var base := GameData.tier_color(int(item.get("tier", 1)))
	var fam := GameData.family_color(str(item.get("family", "mech")))
	for spec in _part_specs(shape):
		var col: Color = fam if bool(spec.get("accent", false)) else base
		var mi := _mesh(
			holder, str(spec["prim"]), col,
			spec.get("pos", Vector3.ZERO), spec.get("rot", Vector3.ZERO),
			spec.get("scale", Vector3.ONE)
		)
		_mesh_nodes.append(mi)
		_base_colors.append(col)
	return holder

func _mesh(parent: Node3D, prim: String, color: Color, pos: Vector3, rot: Vector3, scl: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _make_prim(prim)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	var mat := ShaderMaterial.new()
	mat.shader = load(ICON_SHADER_PATH if _icon_mode else SHADER_PATH)
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("intensity", 1.0 if _icon_mode else 1.15)
	if not _icon_mode:
		mat.set_shader_parameter("wire_amount", 1.0 if _wire else 0.0)
		mat.set_shader_parameter("time_offset", randf() * 12.0)
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _make_prim(kind: String) -> Mesh:
	match kind:
		"sphere":
			var s := SphereMesh.new()
			s.radial_segments = 24
			s.rings = 12
			return s
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.radial_segments = 24
			return c
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = 0.3
			t.outer_radius = 0.5
			t.rings = 28
			t.ring_segments = 12
			return t
		"prism":
			return PrismMesh.new()
		"capsule":
			var cp := CapsuleMesh.new()
			cp.radius = 0.25
			cp.height = 0.9
			return cp
		_:
			return BoxMesh.new()

## 每种形状用一组图元描述。accent=true 的部件用族系色，其余用稀有度色。
func _part_specs(shape: String) -> Array:
	var specs: Array = []
	match shape:
		"coil":
			for i in range(5):
				specs.append({ "prim": "torus", "pos": Vector3(0, -0.22 + i * 0.11, 0), "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.8, 0.8, 0.5) })
		"chip":
			specs.append({ "prim": "box", "scale": Vector3(0.62, 0.07, 0.46) })
			for i in range(6):
				specs.append({ "prim": "box", "accent": true, "pos": Vector3(-0.36, 0, -0.16 + i * 0.064), "scale": Vector3(0.14, 0.03, 0.022) })
			for i in range(6):
				specs.append({ "prim": "box", "accent": true, "pos": Vector3(0.36, 0, -0.16 + i * 0.064), "scale": Vector3(0.14, 0.03, 0.022) })
		"valve":
			specs.append({ "prim": "cyl", "scale": Vector3(0.52, 0.5, 0.52) })
			specs.append({ "prim": "cyl", "accent": true, "pos": Vector3(0, 0.42, 0), "scale": Vector3(0.2, 0.34, 0.2) })
			specs.append({ "prim": "torus", "pos": Vector3(0, 0.16, 0), "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.62, 0.62, 0.62) })
		"ring":
			specs.append({ "prim": "torus", "scale": Vector3(1.0, 1.0, 0.42) })
			specs.append({ "prim": "cyl", "accent": true, "scale": Vector3(0.3, 0.2, 0.3) })
		"shaft":
			specs.append({ "prim": "cyl", "rot": Vector3(0, 0, PI * 0.5), "scale": Vector3(0.16, 0.62, 0.16) })
			specs.append({ "prim": "torus", "accent": true, "pos": Vector3(-0.3, 0, 0), "rot": Vector3(0, PI * 0.5, 0), "scale": Vector3(0.42, 0.42, 0.42) })
			specs.append({ "prim": "torus", "accent": true, "pos": Vector3(0.3, 0, 0), "rot": Vector3(0, PI * 0.5, 0), "scale": Vector3(0.42, 0.42, 0.42) })
		"gear":
			specs.append({ "prim": "cyl", "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.52, 0.2, 0.52) })
			for i in range(8):
				var a := TAU * float(i) / 8.0
				specs.append({ "prim": "box", "accent": true, "pos": Vector3(cos(a) * 0.54, sin(a) * 0.54, 0), "rot": Vector3(0, 0, a), "scale": Vector3(0.15, 0.1, 0.16) })
			specs.append({ "prim": "cyl", "pos": Vector3(0, 0, 0), "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.18, 0.28, 0.18) })
		"prism":
			specs.append({ "prim": "prism", "scale": Vector3(0.9, 0.9, 0.9) })
			specs.append({ "prim": "torus", "accent": true, "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.7, 0.7, 0.35) })
		"plate":
			specs.append({ "prim": "box", "scale": Vector3(0.95, 0.09, 0.62) })
			specs.append({ "prim": "box", "accent": true, "pos": Vector3(0, 0.08, 0), "scale": Vector3(0.5, 0.04, 0.3) })
		"orb":
			specs.append({ "prim": "sphere", "scale": Vector3(0.72, 0.72, 0.72) })
			specs.append({ "prim": "torus", "accent": true, "rot": Vector3(PI * 0.42, 0.3, 0), "scale": Vector3(1.05, 1.05, 1.05) })
		"torus":
			specs.append({ "prim": "torus", "scale": Vector3(1.1, 1.1, 0.9) })
			specs.append({ "prim": "sphere", "accent": true, "scale": Vector3(0.3, 0.3, 0.3) })
		"cluster":
			var pts := [Vector3(0, 0, 0), Vector3(0.34, 0.2, 0.1), Vector3(-0.3, 0.12, -0.14), Vector3(0.1, -0.28, 0.18), Vector3(-0.18, -0.22, -0.2)]
			for i in range(pts.size()):
				specs.append({ "prim": "box", "pos": pts[i], "rot": Vector3(a_rand(i), a_rand(i + 3), a_rand(i + 7)), "scale": Vector3(0.3, 0.22, 0.26), "accent": i % 2 == 1 })
		"fiber":
			for i in range(5):
				var a := TAU * float(i) / 5.0
				specs.append({ "prim": "capsule", "pos": Vector3(cos(a) * 0.12, 0, sin(a) * 0.12), "rot": Vector3(0, 0, a_rand(i) * 0.4), "scale": Vector3(0.5, 1.1, 0.5), "accent": i % 2 == 0 })
		"gel":
			specs.append({ "prim": "sphere", "scale": Vector3(0.78, 0.6, 0.78) })
			specs.append({ "prim": "sphere", "accent": true, "pos": Vector3(0.3, 0.24, -0.1), "scale": Vector3(0.24, 0.24, 0.24) })
		"blob":
			specs.append({ "prim": "sphere", "scale": Vector3(0.6, 0.6, 0.6) })
			specs.append({ "prim": "sphere", "pos": Vector3(0.3, 0.18, 0), "scale": Vector3(0.42, 0.42, 0.42) })
			specs.append({ "prim": "sphere", "accent": true, "pos": Vector3(-0.26, -0.16, 0.1), "scale": Vector3(0.34, 0.34, 0.34) })
		"cube":
			specs.append({ "prim": "box", "scale": Vector3(0.6, 0.6, 0.6) })
			specs.append({ "prim": "box", "accent": true, "pos": Vector3(0.28, 0.28, 0.28), "scale": Vector3(0.22, 0.22, 0.22) })
		"disk":
			specs.append({ "prim": "cyl", "rot": Vector3(0, 0, 0), "scale": Vector3(0.82, 0.08, 0.82) })
			specs.append({ "prim": "torus", "accent": true, "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.8, 0.8, 0.4) })
		"key":
			specs.append({ "prim": "box", "scale": Vector3(0.5, 0.16, 0.16) })
			specs.append({ "prim": "cyl", "accent": true, "pos": Vector3(0.36, 0, 0), "rot": Vector3(0, 0, PI * 0.5), "scale": Vector3(0.1, 0.42, 0.1) })
		"engine":
			specs.append({ "prim": "cyl", "scale": Vector3(0.44, 0.6, 0.44) })
			for i in range(3):
				specs.append({ "prim": "box", "accent": true, "pos": Vector3(0, -0.2 + i * 0.2, 0.38), "scale": Vector3(0.3, 0.12, 0.24) })
			specs.append({ "prim": "torus", "pos": Vector3(0, 0.38, 0), "rot": Vector3(PI * 0.5, 0, 0), "scale": Vector3(0.5, 0.5, 0.5) })
		_:
			specs.append({ "prim": "box", "scale": Vector3(0.6, 0.6, 0.6) })
	return specs

func a_rand(seed_i: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_i)
	return r.randf_range(-0.5, 0.5)

# ---------------- 着色 / 相机 / 输入 ----------------

func _apply_colors() -> void:
	for i in range(_mesh_nodes.size()):
		var mi := _mesh_nodes[i] as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		if _output_tint.is_empty():
			mat.set_shader_parameter("base_color", _base_colors[i])
		else:
			var oid: String = str(_output_tint[i % _output_tint.size()])
			var it: Dictionary = GameData.get_item(oid)
			mat.set_shader_parameter("base_color", GameData.tier_color(int(it.get("tier", 1))))

func _update_camera() -> void:
	if _cam == null:
		return
	var dir := Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, 1)
	_cam.position = _focus + dir * _dist
	_cam.look_at(_focus, Vector3.UP)

func _process(delta: float) -> void:
	if _spin and not _dragging and _cam:
		_yaw += delta * 0.5
		_update_camera()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist - 0.25, 1.3, 8.0)
			_update_camera()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist + 0.25, 1.3, 8.0)
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch - mm.relative.y * 0.01, -1.45, 1.45)
		_update_camera()
		accept_event()
