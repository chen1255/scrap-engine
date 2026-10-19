extends Control
## 阶段四：维修台。品相（保养度）会随开箱随机生成、被拆解继承，却没有回补手段。
## 这里提供两条路：精修（确定性，按档 +品相）与翻新（一次性概率回补，可能徒劳）。
## 两者都消耗同族 T1 材料 + 信用点，于是「攒材料 → 修品相 → 卖高价 / 拆出好料」的闭环成立。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _list: VBoxContainer
var _holo: HoloInspector
var _info: VBoxContainer
var _selected: String = ""
var _spin_layer: Control
var _spin_title: Label
var _spin_skip := false

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_list()
	if _selected == "" or GameState.count_of(_selected) <= 0 or not _repairable(_selected):
		_selected = _first_repairable()
	_show_selected()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(12)
	m.add_child(root)
	root.add_child(UIKit.label("维修台", 20, UIKit.TEXT))
	var sub := UIKit.muted("精修按档确定性提升品相；翻新是一次性概率回补，可能投入了材料却徒劳无功。品相越高，卖价系数越高；修复残骸后再拆解，产出的材料也会继承更高的品相。", 12)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(sub)

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

	_build_spin_layer()

# ---------------- 左侧列表 ----------------

func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var found := false
	for id in GameData.item_order:
		if not _repairable(id):
			continue
		found = true
		var tile := UIKit.item_tile(id, GameState.count_of(id), 300)
		if id == _selected:
			tile.add_theme_stylebox_override("panel", UIKit.sb(UIKit.PANEL_HI, 8, UIKit.ACCENT))
		tile.gui_input.connect(_on_pick.bind(id))
		_list.add_child(tile)
	if not found:
		_list.add_child(UIKit.muted("仓库里没有需要维修的物品（只有品相未满的才会上架）。去黑市开几箱吧。", 12))

func _on_pick(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_selected = id
		refresh()

func _repairable(id: String) -> bool:
	return GameState.count_of(id) > 0 and GameState.condition_of(id) < GameData.repair_max()

func _first_repairable() -> String:
	for id in GameData.item_order:
		if _repairable(id):
			return id
	return ""

# ---------------- 右侧详情 ----------------

func _show_selected() -> void:
	for c in _info.get_children():
		c.queue_free()
	if _selected == "":
		_info.add_child(UIKit.muted("左侧选择一件品相未满的物品开始维修。", 13))
		_holo.clear_item()
		return
	var item: Dictionary = GameData.get_item(_selected)
	_holo.show_item(_selected)

	_info.add_child(UIKit.label(str(item.get("name", _selected)), 19, UIKit.TEXT))
	var badges := UIKit.hbox(6)
	badges.add_child(UIKit.tier_badge(int(item.get("tier", 1))))
	badges.add_child(UIKit.chip(GameData.family_name(str(item.get("family", ""))), GameData.family_color(str(item.get("family", "")))))
	badges.add_child(UIKit.chip(_kind_name(str(item.get("kind", ""))), UIKit.ACCENT2))
	_info.add_child(badges)
	_info.add_child(UIKit.muted(str(item.get("desc", "")), 12))
	_info.add_child(UIKit.hsep(2))
	_info.add_child(_condition_row(GameState.condition_of(_selected)))
	_info.add_child(UIKit.hsep(2))

	_info.add_child(_repair_panel())
	_info.add_child(_refurbish_panel())
	_info.add_child(_stats_panel())

	var btns := UIKit.hbox(8)
	var view := UIKit.btn("查看详情")
	view.pressed.connect(func(): inspect_requested.emit(_selected))
	btns.add_child(view)
	_info.add_child(btns)

## 当前品相一览：分档 chip + 数值 + 卖价系数
func _condition_row(cond: float) -> Control:
	var g: Dictionary = GameData.condition_grade(cond)
	var col := Color(str(g.get("color", "#FFFFFF")))
	var v := UIKit.vbox(4)
	var h := UIKit.hbox(8)
	h.add_child(UIKit.chip(str(g.get("name", "?")), col, 11))
	h.add_child(UIKit.label("保养度 %d / 100" % int(round(cond)), 13, UIKit.TEXT))
	h.add_child(UIKit.spacer())
	h.add_child(UIKit.label("卖价 ×%.2f" % MarketSystem.condition_factor(_selected), 11, UIKit.MUTED))
	v.add_child(h)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = clampf(cond, 0.0, 100.0)
	bar.add_theme_stylebox_override("fill", UIKit.sb(col, 4))
	v.add_child(bar)
	return v

# ---------------- 精修（确定性） ----------------

func _repair_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("精修（确定性，每档 +%d 品相）" % int(GameData.repair_step()), 13, UIKit.ACCENT))

	var maxs := CraftSystem.repair_max_steps(_selected)
	var one := CraftSystem.repair_plan(_selected, 1)
	var full := CraftSystem.repair_plan(_selected, maxs)
	var need_per := int(GameData.repair_cfg.get("material_per_step", 1))
	v.add_child(UIKit.label("当前还能精修 %d 档 · 单档费用 ₡%d + 同族 T1 材料 ×%d"
		% [maxs, int(one["credits"]), need_per], 12, UIKit.TEXT))
	v.add_child(UIKit.label("同族 T1 材料持有 ×%d" % int(full["materials_have"]), 12, UIKit.MUTED))

	if maxs > 0:
		var tbon := float(one.get("trait_repair", 0.0))
		if tbon != 0.0:
			v.add_child(UIKit.label("词条加成：该物品精修额外 %s%d 品相"
				% ["+" if tbon > 0.0 else "-", int(round(absf(tbon)))], 12, UIKit.OK if tbon > 0.0 else UIKit.BAD))
		var row := UIKit.hbox(10)
		var b1 := UIKit.btn("精修 ×1", true, 110)
		b1.disabled = int(one["materials_have"]) < int(one["materials_need"]) or GameState.credits < int(one["credits"])
		b1.pressed.connect(func(): _do_repair(1))
		var b2 := UIKit.btn("精修到满（%d 档）" % maxs, false, 150)
		b2.disabled = int(full["materials_have"]) < int(full["materials_need"]) or GameState.credits < int(full["credits"])
		b2.pressed.connect(func(): _do_repair(maxs))
		row.add_child(b1)
		row.add_child(b2)
		v.add_child(row)
		var full_after := float(full["after"])
		v.add_child(UIKit.label("修满后品相 %d → %s（卖价 ×%.2f）"
			% [int(round(full_after)), str(GameData.condition_grade(full_after).get("name", "?")), _factor_at(full_after)], 11, UIKit.OK))
		if b2.disabled and b1.disabled:
			v.add_child(UIKit.label("信用点或同族材料不足，暂时无法精修。", 11, UIKit.BAD))
	else:
		v.add_child(UIKit.label("品相已满。", 12, UIKit.OK))
	return p

## 给定保养度下的卖价系数（用于预览，不依赖当前库存）
func _factor_at(cond: float) -> float:
	return lerpf(0.55, 1.15, clampf(cond, 0.0, 100.0) / 100.0)

func _do_repair(steps: int) -> void:
	var res: Dictionary = CraftSystem.repair(_selected, steps)
	if not res.get("ok", false):
		Sfx.play_error()
		toast_requested.emit(str(res.get("reason", "精修失败")))
		return
	Sfx.play("repair")
	toast_requested.emit("精修完成：%s 品相 %d → %d，花费 ₡%d + 同族材料 ×%d"
		% [GameData.item_name(_selected), int(round(float(res["before"]))), int(round(float(res["after"]))),
		   int(res["credits"]), int(res["materials"])])
	refresh()

# ---------------- 翻新（概率） ----------------

func _refurbish_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE_HI)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("翻新（一次性概率回补，可能徒劳）", 13, UIKit.WARN))

	var cost := CraftSystem.refurbish_cost(_selected)
	var preview := CraftSystem.refurbish_preview(_selected)
	var weights: Dictionary = preview["weights"]
	var outcomes: Dictionary = preview["outcomes"]
	var targets: Dictionary = preview["targets"]

	v.add_child(UIKit.label("费用 ₡%d + 同族 T1 材料 ×%d（无论成败都消耗）"
		% [int(cost["credits"]), int(cost["materials_need"])], 12, UIKit.TEXT))
	v.add_child(UIKit.label("同族 T1 材料持有 ×%d" % int(cost["materials_have"]), 12, UIKit.MUTED))

	var trb := float(preview.get("trait_refurbish", 0.0))
	if trb != 0.0:
		v.add_child(UIKit.label("词条加成：「焕新」权重 %s%d（与「徒劳」之间转移）"
			% ["+" if trb > 0.0 else "-", int(round(absf(trb)))], 12, UIKit.OK if trb > 0.0 else UIKit.BAD))

	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		total = 1.0
	var segs: Array = []
	for key in ["pristine", "good", "fail"]:
		var oc: Dictionary = outcomes.get(key, {})
		segs.append({ "label": str(oc.get("name", key)), "value": float(weights.get(key, 0.0)),
			"color": str(oc.get("color", "#FFFFFF")) })
	v.add_child(UIKit.ratio_bar(segs, 400, 16))

	var legend := UIKit.hbox(14)
	for key in ["pristine", "good", "fail"]:
		var oc: Dictionary = outcomes.get(key, {})
		var col := UIKit.map_color_html(str(oc.get("color", "#FFFFFF")))
		var cell := UIKit.vbox(1)
		cell.add_child(UIKit.label(str(oc.get("name", key)), 11, col))
		var pct := float(weights.get(key, 0.0)) / total * 100.0
		var detail := "%.0f%%" % pct
		if targets.has(key):
			detail += " → %d" % int(targets[key])
		cell.add_child(UIKit.label(detail, 13, UIKit.TEXT))
		legend.add_child(cell)
	v.add_child(legend)

	var check := CraftSystem.can_refurbish(_selected)
	var row := UIKit.hbox(10)
	var go := UIKit.btn("翻新 ▸", true, 150)
	go.disabled = not check["ok"]
	go.pressed.connect(_do_refurbish)
	row.add_child(go)
	if not check["ok"]:
		row.add_child(UIKit.label(str(check.get("reason", "")), 11, UIKit.BAD))
	v.add_child(row)
	return p

func _do_refurbish() -> void:
	var res: Dictionary = CraftSystem.refurbish(_selected)
	if not res.get("ok", false):
		Sfx.play_error()
		toast_requested.emit(str(res.get("reason", "翻新失败")))
		return
	var outcome := str(res["outcome"])
	await _play_spin(outcome)
	Sfx.play_outcome(_outcome_sound(outcome))
	toast_requested.emit("%s —— %s" % [
		str(GameData.refurbish_outcomes().get(outcome, {}).get("name", outcome)), _outcome_tail(res)])
	refresh()

## 翻新结果映射到既有音效（焕新用成功音、良修用稳定音、徒劳用损伤音）
func _outcome_sound(outcome: String) -> String:
	match outcome:
		"pristine": return "success"
		"good": return "hold"
		_: return "damage"

func _outcome_tail(res: Dictionary) -> String:
	match str(res["outcome"]):
		"pristine": return "品相回满到 %d" % int(round(float(res["after"])))
		"good": return "品相回升到 %d" % int(round(float(res["after"])))
		_: return "材料白耗，品相停在 %d" % int(round(float(res["before"])))

# ---------------- 翻新抽签演出 ----------------

## 抽签浮层：遮住整个视图，滚动结果名后定格。点击任意处可跳过。
func _build_spin_layer() -> void:
	_spin_layer = Control.new()
	_spin_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spin_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_spin_layer.visible = false
	add_child(_spin_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_spin_skip = true)
	_spin_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spin_layer.add_child(center)

	var v := UIKit.vbox(8)
	center.add_child(v)

	var cap := UIKit.label("翻新抽签", 13, UIKit.MUTED)
	cap.custom_minimum_size.x = 620
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)

	_spin_title = UIKit.label("", 56, UIKit.TEXT)
	_spin_title.custom_minimum_size = Vector2(620, 96)
	_spin_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_spin_title)

	var hint := UIKit.label("点击任意处跳过", 11, UIKit.MUTED)
	hint.custom_minimum_size.x = 620
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)

func _play_spin(outcome: String) -> void:
	var keys := ["pristine", "good", "fail"]
	var outcomes: Dictionary = GameData.refurbish_outcomes()
	_spin_skip = false
	_spin_layer.visible = true
	_spin_layer.modulate.a = 1.0
	_spin_title.rotation = 0.0
	_spin_title.scale = Vector2.ONE
	_spin_title.add_theme_color_override("font_color", UIKit.MUTED)
	_spin_title.text = "…"

	var step := 0.07
	var elapsed := 0.0
	var i := 0
	while elapsed < 0.8 and not _spin_skip:
		var k: String = str(keys[i % keys.size()])
		_spin_title.text = str(outcomes.get(k, {}).get("name", k))
		UIKit.pop(_spin_title, 1.07, 0.12)
		Sfx.play("promote_spin", randf_range(0.95, 1.3))
		await get_tree().create_timer(step, true, false, true).timeout
		elapsed += step
		i += 1

	var oc: Dictionary = outcomes.get(outcome, {})
	_spin_title.text = str(oc.get("name", outcome))
	_spin_title.add_theme_color_override("font_color", UIKit.map_color_html(str(oc.get("color", "#FFFFFF"))))
	UIKit.pop(_spin_title, 1.45, 0.34)
	UIKit.wobble(_spin_title, 3.0, 0.4)
	await get_tree().create_timer(0.55 if not _spin_skip else 0.22, true, false, true).timeout

	var tw := _spin_layer.create_tween()
	tw.tween_property(_spin_layer, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): _spin_layer.visible = false)

# ---------------- 统计 ----------------

func _stats_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(6)
	m.add_child(v)
	v.add_child(UIKit.label("维修统计", 13, UIKit.MUTED))
	v.add_child(UIKit.label("精修 %d 次 · 翻新 %d 次（徒劳 %d 次）"
		% [int(GameState.stats.get("repairs", 0)), int(GameState.stats.get("refurbish", 0)),
		   int(GameState.stats.get("refurbish_fail", 0))], 12, UIKit.TEXT))
	return p

func _kind_name(kind: String) -> String:
	match kind:
		"wreck": return "残骸"
		"material": return "材料"
		"core": return "核心"
	return kind

func _margin(parent: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	parent.add_child(m)
	return m
