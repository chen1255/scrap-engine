extends Control
## 仓库：库存总览，可按族系与类型筛选。所有卡片可点击进入全息检视。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _grid: GridContainer
var _summary: Label
var _filter_row: HBoxContainer
var _family := ""
var _kind := ""

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_filter()
	_rebuild_grid()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(10)
	m.add_child(root)

	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("仓库", 20, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	_summary = UIKit.label("", 13, UIKit.MUTED)
	head.add_child(_summary)
	root.add_child(head)

	_filter_row = UIKit.hbox(8)
	root.add_child(_filter_row)

	var scroll := UIKit.scroll()
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

func _rebuild_filter() -> void:
	for c in _filter_row.get_children():
		c.queue_free()
	_filter_row.add_child(_filter_btn("全部族系", "", _family == "", "family", ""))
	for f in GameData.families:
		var fid := str(f["id"])
		_filter_row.add_child(_filter_btn(str(f["name"]), fid, _family == fid, "family", fid))
	_filter_row.add_child(UIKit.hsep(0))
	_filter_row.add_child(_filter_btn("全部类型", "", _kind == "", "kind", ""))
	for pair in [["材料", "material"], ["残骸", "wreck"], ["核心", "core"]]:
		_filter_row.add_child(_filter_btn(str(pair[0]), str(pair[1]), _kind == str(pair[1]), "kind", str(pair[1])))

func _filter_btn(text: String, _v: String, on: bool, group: String, val: String) -> Button:
	var b := UIKit.btn(text)
	if on:
		b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT2, 8, Color("#9C8CFF")))
		b.add_theme_color_override("font_color", Color("#0B0E14"))
	b.pressed.connect(func():
		if group == "family":
			_family = val
		else:
			_kind = val
		refresh())
	return b

func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var owned: Array = []
	var total := 0
	var value := 0.0
	for id in GameData.item_order:
		var it: Dictionary = GameData.items[id]
		if str(it.get("kind", "")) == "wreck" and false:
			continue
		var n := GameState.count_of(id)
		if _family != "" and str(it.get("family", "")) != _family:
			continue
		if _kind != "" and str(it.get("kind", "")) != _kind:
			continue
		owned.append(id)
		total += n
		value += float(MarketSystem.price_of(id)) * float(n)

	_summary.text = "物品种类 %d · 总件数 %d · 总估值 ₡%d" % [owned.size(), total, int(value)]

	var shown := 0
	for id in owned:
		var n := GameState.count_of(id)
		if n <= 0:
			continue
		var tile := UIKit.item_tile(str(id), n, 200)
		tile.gui_input.connect(_on_tile_input.bind(str(id)))
		_grid.add_child(tile)
		shown += 1
	if shown == 0:
		var tip := UIKit.muted("这个筛选条件下仓库是空的。去黑市开箱，或去拆解台把残骸提纯成材料。", 13)
		tip.custom_minimum_size = Vector2(420, 60)
		_grid.add_child(tip)

func _on_tile_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		inspect_requested.emit(item_id)
