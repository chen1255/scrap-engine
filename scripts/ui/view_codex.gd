extends Control
## 图鉴：收录进度总览 + 各族系进度 + 全物品网格。
## 未收录的物品以「???」锁定卡显示，点击只会提示尚未收录；已收录的卡片可进入全息检视。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _grid: GridContainer
var _summary: Label
var _family_bars: HBoxContainer
var _filter_row: HBoxContainer
var _family := ""
var _only_found := false

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_filter()
	_rebuild_progress()
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
	head.add_child(UIKit.label("图鉴 · 回收档案", 20, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	_summary = UIKit.label("", 13, UIKit.MUTED)
	head.add_child(_summary)
	root.add_child(head)

	_family_bars = UIKit.hbox(14)
	root.add_child(_family_bars)

	_filter_row = UIKit.hbox(8)
	root.add_child(_filter_row)

	var scroll := UIKit.scroll()
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

# ---------------- 进度 ----------------

func _rebuild_progress() -> void:
	for c in _family_bars.get_children():
		c.queue_free()
	var prog: Array = GameState.codex_progress()
	var found := int(prog[0])
	var total := int(prog[1])
	var pct := 0.0 if total <= 0 else float(found) / float(total) * 100.0

	var total_v := UIKit.vbox(4)
	total_v.custom_minimum_size.x = 240
	var th := UIKit.hbox(8)
	th.add_child(UIKit.label("总收录", 12, UIKit.MUTED))
	th.add_child(UIKit.label("%d / %d · %.0f%%" % [found, total, pct], 13, UIKit.TEXT))
	total_v.add_child(th)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240, 10)
	bar.show_percentage = false
	bar.max_value = maxf(1.0, float(total))
	bar.value = float(found)
	total_v.add_child(bar)
	_family_bars.add_child(total_v)

	for f in GameData.families:
		var fid := str(f["id"])
		var fp: Array = GameState.codex_progress_of(fid)
		var ff := int(fp[0])
		var ft := int(fp[1])
		var fcol := GameData.family_color(fid)
		var v := UIKit.vbox(4)
		v.custom_minimum_size.x = 150
		var hh := UIKit.hbox(6)
		hh.add_child(UIKit.chip(str(f["name"]), fcol))
		hh.add_child(UIKit.label("%d / %d" % [ff, ft], 12, UIKit.MUTED))
		v.add_child(hh)
		var fb := ProgressBar.new()
		fb.custom_minimum_size = Vector2(150, 10)
		fb.show_percentage = false
		fb.max_value = maxf(1.0, float(ft))
		fb.value = float(ff)
		fb.add_theme_stylebox_override("fill", UIKit.sb(fcol, 5))
		v.add_child(fb)
		_family_bars.add_child(v)

# ---------------- 筛选 ----------------

func _rebuild_filter() -> void:
	for c in _filter_row.get_children():
		c.queue_free()
	_filter_row.add_child(_chip_btn("全部族系", "", _family == "", "family", ""))
	for f in GameData.families:
		var fid := str(f["id"])
		_filter_row.add_child(_chip_btn(str(f["name"]), fid, _family == fid, "family", fid))
	_filter_row.add_child(UIKit.hsep(0))
	_filter_row.add_child(_chip_btn("只看已收录", "", _only_found, "found", ""))

func _chip_btn(text: String, val: String, on: bool, group: String, _val: String) -> Button:
	var b := UIKit.btn(text)
	if on:
		b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT2, 8, Color("#9C8CFF")))
		b.add_theme_color_override("font_color", Color("#0B0E14"))
	b.pressed.connect(func():
		if group == "family":
			_family = val
		else:
			_only_found = not _only_found
		refresh())
	return b

# ---------------- 网格 ----------------

func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var shown := 0
	for id in GameData.item_order:
		var it: Dictionary = GameData.items[id]
		if _family != "" and str(it.get("family", "")) != _family:
			continue
		var found := GameState.is_discovered(id)
		if _only_found and not found:
			continue
		_grid.add_child(_tile(str(id), found))
		shown += 1
	if shown == 0:
		var tip := UIKit.muted("这个筛选条件下没有条目。", 13)
		tip.custom_minimum_size = Vector2(420, 60)
		_grid.add_child(tip)

func _tile(id: String, found: bool) -> Control:
	if found:
		var count := GameState.count_of(id)
		var tile := UIKit.item_tile(id, count, 200)
		tile.gui_input.connect(_on_tile_input.bind(id))
		return tile
	# 未收录：锁定卡，用「未知」占位图，布局与正常卡片保持一致
	var it: Dictionary = GameData.get_item(id)
	var p := UIKit.panel(UIKit.BG_SOFT, 8, Color(UIKit.MUTED.r, UIKit.MUTED.g, UIKit.MUTED.b, 0.35))
	p.custom_minimum_size.x = 200
	p.tooltip_text = "尚未收录"
	var row := UIKit.hbox(8)
	var tr := UIKit.icon_rect(UIKit.unknown_icon())
	if tr != null:
		row.add_child(tr)
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label("???", 13, UIKit.MUTED))
	var meta := UIKit.hbox(5)
	meta.add_child(UIKit.chip("T? 未知", UIKit.MUTED))
	var fcol := GameData.family_color(str(it.get("family", "")))
	meta.add_child(UIKit.chip(GameData.family_name(str(it.get("family", ""))), Color(fcol.r, fcol.g, fcol.b, 0.6)))
	v.add_child(meta)
	v.add_child(UIKit.label("未收录", 11, UIKit.MUTED))
	row.add_child(v)
	p.add_child(row)
	p.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			toast_requested.emit("尚未收录：通过开箱或晋升解锁这一条目"))
	return p

func _on_tile_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		inspect_requested.emit(item_id)
