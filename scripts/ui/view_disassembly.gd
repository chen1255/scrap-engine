extends Control
## 阶段二：全息拆解台。把不可直接使用的残骸，提纯成可参与晋升的材料。
## 右侧检视台会把「即将产出的材料」按族系/阶位着色到模型部件上。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _list: VBoxContainer
var _holo: HoloInspector
var _info: VBoxContainer
var _selected: String = ""

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_list()
	if _selected == "" or GameState.count_of(_selected) <= 0 or not _is_wreck(_selected):
		_selected = _first_wreck()
	_show_selected()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(12)
	m.add_child(root)
	root.add_child(UIKit.label("全息拆解台", 20, UIKit.TEXT))
	root.add_child(UIKit.muted("残骸无法直接用于晋升，必须在这里做热解提纯与相变剥离，得到可用的材料。", 12))

	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var scroll := UIKit.scroll()
	scroll.custom_minimum_size.x = 320
	var left := UIKit.vbox(8)
	scroll.add_child(left)
	body.add_child(scroll)
	_list = left

	var right := UIKit.hbox(16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_holo = HoloInspector.new()
	_holo.custom_minimum_size = Vector2(400, 400)
	right.add_child(_holo)

	var rv := UIKit.vbox(10)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(rv)
	_info = rv

func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var found := false
	for id in GameData.item_order:
		if not _is_wreck(id):
			continue
		var n := GameState.count_of(id)
		if n <= 0:
			continue
		found = true
		var tile := UIKit.item_tile(id, n, 300)
		if id == _selected:
			tile.add_theme_stylebox_override("panel", UIKit.sb(UIKit.PANEL_HI, 8, UIKit.ACCENT))
		tile.gui_input.connect(_on_pick.bind(id))
		_list.add_child(tile)
	if not found:
		_list.add_child(UIKit.muted("仓库里没有可拆解的残骸。去黑市开几箱吧。", 12))

func _on_pick(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_selected = id
		refresh()

func _first_wreck() -> String:
	for id in GameData.item_order:
		if _is_wreck(id) and GameState.count_of(id) > 0:
			return id
	return ""

func _is_wreck(id: String) -> bool:
	return str(GameData.get_item(id).get("kind", "")) == "wreck"

func _show_selected() -> void:
	for c in _info.get_children():
		c.queue_free()
	if _selected == "":
		_info.add_child(UIKit.muted("左侧选择一件残骸开始拆解。", 13))
		_holo.clear_item()
		return
	var item: Dictionary = GameData.get_item(_selected)
	_holo.show_item(_selected)
	var spec: Dictionary = item.get("disassemble", {})
	var out_ids: Array = []
	for o in spec.get("outputs", []):
		out_ids.append(str(o.get("id", "")))
	_holo.set_output_tint(out_ids)

	_info.add_child(UIKit.label(str(item["name"]), 19, UIKit.TEXT))
	var badges := UIKit.hbox(6)
	badges.add_child(UIKit.tier_badge(int(item.get("tier", 1))))
	badges.add_child(UIKit.chip(GameData.family_name(str(item.get("family", ""))), GameData.family_color(str(item.get("family", "")))))
	badges.add_child(UIKit.chip("残骸", UIKit.WARN))
	_info.add_child(badges)
	_info.add_child(UIKit.muted(str(item.get("desc", "")), 12))
	_info.add_child(UIKit.hsep(2))

	_info.add_child(UIKit.label("提纯产出（模型上已按颜色标出对应部件）", 13, UIKit.TEXT))
	for o in spec.get("outputs", []):
		var oid := str(o.get("id", ""))
		var row := UIKit.hbox(8)
		row.add_child(UIKit.tier_badge(int(GameData.get_item(oid).get("tier", 1))))
		row.add_child(UIKit.label(GameData.item_name(oid), 13, UIKit.TEXT))
		row.add_child(UIKit.spacer())
		row.add_child(UIKit.label("×%d ~ %d" % [int(o.get("min", 1)), int(o.get("max", 1))], 12, UIKit.MUTED))
		_info.add_child(row)

	_info.add_child(UIKit.hsep(2))
	_info.add_child(UIKit.label("持有 ×%d" % GameState.count_of(_selected), 12, UIKit.MUTED))
	var btns := UIKit.hbox(8)
	var b1 := UIKit.btn("拆解 ×1", true, 110)
	b1.pressed.connect(func(): _do(_selected, 1))
	var b2 := UIKit.btn("全部拆解", false, 110)
	b2.pressed.connect(func(): _do(_selected, GameState.count_of(_selected)))
	var b3 := UIKit.btn("查看详情")
	b3.pressed.connect(func(): inspect_requested.emit(_selected))
	btns.add_child(b1)
	btns.add_child(b2)
	btns.add_child(b3)
	_info.add_child(btns)

func _do(wreck_id: String, count: int) -> void:
	if count <= 0:
		toast_requested.emit("没有可拆解的残骸")
		return
	var res: Dictionary = CraftSystem.disassemble(wreck_id, count)
	if not res.get("ok", false):
		toast_requested.emit(str(res.get("reason", "拆解失败")))
		return
	var names := PackedStringArray()
	for id in res["order"]:
		names.append("%s ×%d" % [GameData.item_name(str(id)), int(res["outputs"][id])])
	toast_requested.emit("提纯完成：" + "、".join(names))
	refresh()
