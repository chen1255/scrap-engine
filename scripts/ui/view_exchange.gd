extends Control
## 交易所：单机模拟行情。价格随「推进时间」波动，市场事件定向拉抬或打压某些族系/阶位；
## 玩家大量抛售会压低该类价格（抛压），之后逐步回弹。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _list: VBoxContainer
var _banner_box: VBoxContainer
var _filter_row: HBoxContainer
var _summary: Label
var _only_owned := false
var _family := ""

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_banner()
	_rebuild_filter()
	_rebuild_list()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(10)
	m.add_child(root)

	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("交易所 · 单机模拟行情", 20, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	_summary = UIKit.label("", 13, UIKit.MUTED)
	head.add_child(_summary)
	root.add_child(head)

	_banner_box = UIKit.vbox(6)
	root.add_child(_banner_box)

	_filter_row = UIKit.hbox(8)
	root.add_child(_filter_row)

	var scroll := UIKit.scroll()
	root.add_child(scroll)
	_list = UIKit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

# ---------------- 事件横幅 ----------------

func _rebuild_banner() -> void:
	for c in _banner_box.get_children():
		c.queue_free()
	var ev: Dictionary = MarketSystem.active_event
	var left := MarketSystem.event_ticks()
	var p := UIKit.panel(UIKit.BG_SOFT, 8, UIKit.LINE)
	var mm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mm.add_theme_constant_override("margin_" + side, 12)
	p.add_child(mm)
	var v := UIKit.vbox(4)
	mm.add_child(v)

	if ev.is_empty() or str(ev.get("id", "quiet")) == "quiet":
		var h := UIKit.hbox(8)
		h.add_child(UIKit.chip("市场平静", UIKit.MUTED))
		h.add_child(UIKit.muted("没有特别的消息，价格按常规波动。推进时间可刷新行情。", 12))
		v.add_child(h)
	else:
		var factor := float(ev.get("factor", 1.0))
		var col := UIKit.OK if factor >= 1.0 else UIKit.BAD
		var h := UIKit.hbox(8)
		h.add_child(UIKit.chip(str(ev.get("name", "事件")), col))
		h.add_child(UIKit.label("价格 ×%.2f" % factor, 12, col))
		h.add_child(UIKit.label("剩余 %d 次推进" % left, 11, UIKit.MUTED))
		h.add_child(UIKit.spacer())
		var tb := UIKit.btn("推进时间 ▸")
		tb.pressed.connect(func(): MarketSystem.advance_tick())
		h.add_child(tb)
		v.add_child(h)
		v.add_child(UIKit.muted(str(ev.get("desc", "")), 12))

	# 市场活动造成的整体影响提示
	if not MarketSystem.active_event.is_empty():
		var segs: Array = []
		for t in range(1, GameData.max_tier() + 1):
			segs.append({ "label": "T%d" % t, "value": _event_tier_weight(t),
				"color": str(GameData.tier_info(t).get("color", "#FFFFFF")) })
		var legend := UIKit.hbox(10)
		legend.add_child(UIKit.label("事件影响覆盖到的物品占比（按阶位）", 11, UIKit.MUTED))
		legend.add_child(UIKit.ratio_bar(segs, 260, 12))
		v.add_child(legend)

func _event_tier_weight(t: int) -> float:
	if MarketSystem.active_event.is_empty():
		return 0.0
	var f: Dictionary = MarketSystem.active_event.get("filter", {})
	if f.has("tier") and int(f["tier"]) != t:
		return 0.0
	var n := 0
	for id in GameData.item_order:
		var it: Dictionary = GameData.items[id]
		if int(it.get("tier", 0)) != t:
			continue
		if f.has("family") and str(it.get("family", "")) != str(f["family"]):
			continue
		n += 1
	return float(n)

# ---------------- 筛选 ----------------

func _rebuild_filter() -> void:
	for c in _filter_row.get_children():
		c.queue_free()
	_filter_row.add_child(_chip_btn("全部族系", "", _family == "", "family", ""))
	for f in GameData.families:
		var fid := str(f["id"])
		_filter_row.add_child(_chip_btn(str(f["name"]), fid, _family == fid, "family", fid))
	_filter_row.add_child(UIKit.hsep(0))
	_filter_row.add_child(_chip_btn("只看持有", "1", _only_owned, "owned", "1"))

func _chip_btn(text: String, val: String, on: bool, group: String, _val: String) -> Button:
	var b := UIKit.btn(text)
	if on:
		b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT2, 8, Color("#9C8CFF")))
		b.add_theme_color_override("font_color", Color("#0B0E14"))
	b.pressed.connect(func():
		if group == "family":
			_family = val
		else:
			_only_owned = not _only_owned
		refresh())
	return b

# ---------------- 行情列表 ----------------

func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()

	var ids: Array = []
	var value := 0.0
	for id in GameData.item_order:
		var it: Dictionary = GameData.items[id]
		if _family != "" and str(it.get("family", "")) != _family:
			continue
		var n := GameState.count_of(id)
		if _only_owned and n <= 0:
			continue
		ids.append(id)
		value += float(MarketSystem.price_of(id)) * float(n)

	_summary.text = "信用点 ₡%d · 库存估值 ₡%d · 行情 T%d" % [
		GameState.credits, int(value), MarketSystem.tick]

	ids.sort_custom(func(a, b):
		var oa := GameState.count_of(a)
		var ob := GameState.count_of(b)
		if oa != ob:
			return oa > ob
		return int(GameData.items[a].get("tier", 0)) > int(GameData.items[b].get("tier", 0)))

	for id in ids:
		_list.add_child(_row(str(id)))

func _row(id: String) -> Control:
	var it: Dictionary = GameData.get_item(id)
	var tier := int(it.get("tier", 1))
	var col := GameData.tier_color(tier)
	var owned := GameState.count_of(id)
	var price := MarketSystem.price_of(id)
	var trend := MarketSystem.trend_of(id)
	var sell_p := MarketSystem.sell_price(id)
	var buy_p := MarketSystem.buy_price(id)
	var ev_mult := MarketSystem.event_factor(id)

	var p := UIKit.panel(UIKit.BG_SOFT, 8, Color(col.r, col.g, col.b, 0.35))
	var mm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mm.add_theme_constant_override("margin_" + side, 10)
	p.add_child(mm)
	var h := UIKit.hbox(10)
	mm.add_child(h)

	# 名称 + 徽章
	var name_v := UIKit.vbox(2)
	name_v.custom_minimum_size.x = 210
	name_v.add_child(UIKit.label(str(it.get("name", id)), 14, UIKit.TEXT))
	var meta := UIKit.hbox(5)
	meta.add_child(UIKit.tier_badge(tier))
	meta.add_child(UIKit.chip(GameData.family_name(str(it.get("family", ""))), GameData.family_color(str(it.get("family", "")))))
	if absf(ev_mult - 1.0) > 0.01:
		meta.add_child(UIKit.chip("事件 ×%.2f" % ev_mult, UIKit.OK if ev_mult >= 1.0 else UIKit.BAD))
	name_v.add_child(meta)
	h.add_child(name_v)

	# 价格与涨跌
	var price_v := UIKit.vbox(2)
	price_v.custom_minimum_size.x = 150
	var pl := UIKit.hbox(6)
	pl.add_child(UIKit.label("₡ %d" % price, 15, UIKit.WARN))
	pl.add_child(_trend_label(trend))
	price_v.add_child(pl)
	price_v.add_child(UIKit.label("买 ₡%d · 卖 ₡%d" % [buy_p, sell_p], 10, UIKit.MUTED))
	h.add_child(price_v)

	h.add_child(UIKit.spacer())

	var own := UIKit.label("持有 ×%d" % owned, 12, UIKit.ACCENT if owned > 0 else UIKit.MUTED)
	own.custom_minimum_size.x = 72
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(own)

	var buy1 := UIKit.btn("买 1")
	buy1.pressed.connect(func(): _buy(id, 1))
	var buy5 := UIKit.btn("买 5")
	buy5.pressed.connect(func(): _buy(id, 5))
	var sell1 := UIKit.btn("卖 1", owned > 0)
	sell1.disabled = owned <= 0
	sell1.pressed.connect(func(): _sell(id, 1))
	var sellall := UIKit.btn("全卖")
	sellall.disabled = owned <= 0
	sellall.pressed.connect(func(): _sell(id, owned))
	h.add_child(buy1)
	h.add_child(buy5)
	h.add_child(sell1)
	h.add_child(sellall)

	var inspect := UIKit.btn("检视")
	inspect.pressed.connect(func(): inspect_requested.emit(id))
	h.add_child(inspect)
	return p

func _trend_label(trend: float) -> Label:
	if absf(trend) < 0.0005:
		return UIKit.label("— 0.0%", 11, UIKit.MUTED)
	var up := trend > 0.0
	return UIKit.label("%s %.1f%%" % ["▲" if up else "▼", absf(trend) * 100.0], 11,
		UIKit.OK if up else UIKit.BAD)

# ---------------- 买卖动作 ----------------

func _buy(id: String, n: int) -> void:
	var res: Dictionary = MarketSystem.buy(id, n)
	if not res.get("ok", false):
		toast_requested.emit(str(res.get("reason", "买入失败")))
		return
	toast_requested.emit("买入 %s ×%d，花费 ₡%d" % [GameData.item_name(id), n, int(res.get("total", 0))])
	refresh()

func _sell(id: String, n: int) -> void:
	if n <= 0:
		return
	var res: Dictionary = MarketSystem.sell(id, n)
	if not res.get("ok", false):
		toast_requested.emit(str(res.get("reason", "卖出失败")))
		return
	toast_requested.emit("卖出 %s ×%d，获得 ₡%d（抛压已压低该类价格）" % [GameData.item_name(id), n, int(res.get("total", 0))])
	refresh()
