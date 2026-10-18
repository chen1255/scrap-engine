extends Control
## 阶段一：黑市。卖的是「未知」，乐趣在于开箱前的期待与开箱后的落差。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _crate_box: VBoxContainer
var _result_box: VBoxContainer
var _last: Dictionary = {}

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_crates()
	_rebuild_result()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(12)
	m.add_child(root)
	root.add_child(UIKit.label("黑市 · 未知盲盒", 20, UIKit.TEXT))
	root.add_child(UIKit.muted("消耗信用点与体力购入未鉴定的货柜。开箱产出会被记录进图鉴——没见过的会显示成未收录。", 12))
	root.add_child(UIKit.hsep(2))

	var body := UIKit.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var scroll := UIKit.scroll()
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(left)
	body.add_child(scroll)
	_crate_box = left

	var right := UIKit.vbox(10)
	right.custom_minimum_size.x = 320
	body.add_child(right)
	right.add_child(UIKit.label("开箱结果", 16, UIKit.TEXT))
	_result_box = UIKit.vbox(8)
	right.add_child(_result_box)

# ---------------- 盲盒列表 ----------------

func _rebuild_crates() -> void:
	for c in _crate_box.get_children():
		c.queue_free()
	for crate in GameData.crates:
		_crate_box.add_child(_crate_card(crate))

func _crate_card(crate: Dictionary) -> Control:
	var cid := str(crate["id"])
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	p.add_child(m)
	var v := UIKit.vbox(8)
	m.add_child(v)

	var head := UIKit.hbox(10)
	head.add_child(UIKit.label(str(crate["name"]), 17, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label("₡ %d" % int(crate["cost"]), 15, UIKit.WARN))
	head.add_child(UIKit.chip("⚡ %d" % int(crate.get("energy", 0)), UIKit.ACCENT))
	v.add_child(head)
	v.add_child(UIKit.muted(str(crate.get("desc", "")), 12))

	var rolls: Dictionary = crate.get("rolls", {})
	v.add_child(UIKit.label("每次开箱抽取 %d ~ %d 次" % [int(rolls.get("min", 1)), int(rolls.get("max", 1))], 11, UIKit.MUTED))

	v.add_child(UIKit.label("抽签占比（按阶位）", 11, UIKit.MUTED))
	v.add_child(UIKit.ratio_bar(_tier_dist(cid), 380, 14))
	var legend := UIKit.hbox(12)
	for t in range(1, GameData.max_tier() + 1):
		var lg := UIKit.label("■ T%d %s" % [t, GameData.tier_name(t)], 10, GameData.tier_color(t))
		legend.add_child(lg)
	v.add_child(legend)

	var foot := UIKit.hbox(8)
	var open_btn := UIKit.btn("开箱", true, 110)
	open_btn.pressed.connect(func(): _open(cid))
	var open10 := UIKit.btn("连开 ×5", false, 100)
	open10.tooltip_text = "连续开 5 次，结果合并显示"
	open10.pressed.connect(func(): _open_multi(cid, 5))
	foot.add_child(open_btn)
	foot.add_child(open10)
	foot.add_child(UIKit.spacer())
	var detail := UIKit.btn("查看产出池")
	detail.pressed.connect(func(): _show_pool(cid))
	foot.add_child(detail)
	v.add_child(foot)
	return p

func _tier_dist(crate_id: String) -> Array:
	var odds: Dictionary = LootSystem.crate_odds(crate_id)
	var by_tier: Dictionary = {}
	for id in odds:
		var t := int(GameData.get_item(id).get("tier", 1))
		by_tier[t] = float(by_tier.get(t, 0.0)) + float(odds[id])
	var segs: Array = []
	for t in range(1, GameData.max_tier() + 1):
		segs.append({
			"label": "T%d" % t, "value": float(by_tier.get(t, 0.0)),
			"color": str(GameData.tier_info(t).get("color", "#FFFFFF")),
		})
	return segs

# ---------------- 开箱 ----------------

func _open(cid: String) -> void:
	var res: Dictionary = LootSystem.open_crate(cid)
	if not res.get("ok", false):
		toast_requested.emit(str(res.get("reason", "开箱失败")))
		return
	_last = res
	_rebuild_result()
	var names := PackedStringArray()
	for id in res["order"]:
		names.append("%s ×%d" % [GameData.item_name(str(id)), int(res["results"][id])])
	toast_requested.emit("开箱完成：" + "、".join(names))

func _open_multi(cid: String, times: int) -> void:
	var merged: Dictionary = {}
	var order: Array = []
	var spent := 0
	var rolls := 0
	for _i in range(times):
		var res: Dictionary = LootSystem.open_crate(cid)
		if not res.get("ok", false):
			if merged.is_empty():
				toast_requested.emit(str(res.get("reason", "开箱失败")))
				return
			break
		spent += int(res["cost"])
		rolls += int(res["rolls"])
		for id in res["order"]:
			if not merged.has(id):
				order.append(id)
				merged[id] = 0
			merged[id] = int(merged[id]) + int(res["results"][id])
	_last = { "results": merged, "order": order, "cost": spent, "energy": 0, "rolls": rolls }
	_rebuild_result()
	toast_requested.emit("连开 %d 箱完成，共消耗 ₡%d" % [times, spent])

func _rebuild_result() -> void:
	for c in _result_box.get_children():
		c.queue_free()
	if _last.is_empty():
		_result_box.add_child(UIKit.muted("还没有开过箱。左侧任意盲盒点「开箱」即可。", 12))
		return
	_result_box.add_child(UIKit.label("共消耗 ₡%d · 抽取 %d 次" % [int(_last.get("cost", 0)), int(_last.get("rolls", 0))], 11, UIKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for id in _last["order"]:
		var tile := UIKit.item_tile(str(id), int(_last["results"][id]), 280)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.gui_input.connect(_on_tile_input.bind(str(id)))
		grid.add_child(tile)
	_result_box.add_child(grid)

func _on_tile_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		inspect_requested.emit(item_id)

func _show_pool(cid: String) -> void:
	var odds: Dictionary = LootSystem.crate_odds(cid)
	var ids: Array = odds.keys()
	ids.sort_custom(func(a, b): return float(odds[a]) > float(odds[b]))
	var top := PackedStringArray()
	for i in range(mini(3, ids.size())):
		var id: String = str(ids[i])
		top.append("%s %.1f%%" % [GameData.item_name(id), float(odds[id]) * 100.0])
	toast_requested.emit("产出池共 %d 种 · 最高占比：%s" % [ids.size(), "、".join(top)])
