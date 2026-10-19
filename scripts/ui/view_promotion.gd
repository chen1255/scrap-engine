extends Control
## 阶段三：熔炉。整款游戏的爆率核心——消耗 5 个同族同阶材料，抽一次签决定结果。
## 玩家可以用消耗品和概率校准器去改这张签，也可以用保底熬过去。

signal inspect_requested(item_id: String)
signal toast_requested(text: String)

var main: Node
var _family := "mech"
var _from_tier := 1
var _use_stab := false
var _use_boost := false
var _catalyst := ""          # 本次晋升选用的核心催化剂 id（空 = 不投入）
var _last: Dictionary = {}
var _spin_layer: Control
var _spin_title: Label
var _spin_skip := false

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_all()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	_holder = UIKit.vbox(10)
	m.add_child(_holder)
	_build_spin_layer()

var _holder: VBoxContainer

func _rebuild_all() -> void:
	for c in _holder.get_children():
		c.queue_free()
	var head := UIKit.hbox(10)
	head.add_child(UIKit.label("概率熔炉", 20, UIKit.TEXT))
	var top_step := GameData.max_tier()
	var sub := UIKit.muted("5 个同族同阶材料 → 抽一次签 → 决定成功 / 稳定 / 损伤 / 崩解。最高可晋升到 T%d %s。" % [top_step, GameData.tier_name(top_step)], 12)
	# 自动换行的 Label 最小宽度是 1，若不撑开会被挤成 1px 宽、进而把最小高度撑爆
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	_holder.add_child(head)

	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.add_child(body)

	var left := UIKit.vbox(10)
	left.custom_minimum_size.x = 430
	body.add_child(left)
	left.add_child(_family_panel())
	left.add_child(_step_panel())
	left.add_child(_odds_panel())
	left.add_child(_catalyst_panel())
	left.add_child(_action_panel())

	var right := UIKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_result_panel())
	right.add_child(_calibrator_panel())
	right.add_child(_stats_panel())

func _family_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("① 选择族系", 13, UIKit.MUTED))
	var row := UIKit.hbox(8)
	for f in GameData.families:
		var fid := str(f["id"])
		var b := UIKit.btn(str(f["name"]))
		if fid == _family:
			b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.ACCENT2, 8, Color("#9C8CFF")))
			b.add_theme_color_override("font_color", Color("#0B0E14"))
		b.pressed.connect(func():
			_family = fid
			_ensure_tier()
			refresh())
		row.add_child(b)
	v.add_child(row)
	return p

func _available(family: String, tier: int) -> int:
	var n := 0
	for id in GameData.items_matching({ "kind": "material", "family": family, "tier": tier }):
		n += GameState.count_of(id)
	return n

func _ensure_tier() -> void:
	# 优先停在玩家能做的那一阶
	for t in range(GameData.max_tier() - 1, 0, -1):
		if _available(_family, t) >= int(GameData.recipes.get("consume", 5)):
			_from_tier = t
			return
	_from_tier = maxi(1, mini(_from_tier, GameData.max_tier() - 1))

func _step_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("② 选择晋升阶位", 13, UIKit.MUTED))
	var need := int(GameData.recipes.get("consume", 5))
	for t in range(1, GameData.max_tier()):
		var have := _available(_family, t)
		var row := UIKit.hbox(8)
		var b := UIKit.btn("T%d → T%d %s" % [t, t + 1, GameData.tier_name(t + 1)], false, 170)
		if t == _from_tier:
			b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.PANEL_HI, 8, UIKit.ACCENT))
		b.disabled = have < need
		b.pressed.connect(func():
			_from_tier = t
			refresh())
		row.add_child(b)
		row.add_child(UIKit.tier_badge(t))
		var step := GameData.promotion_step(t)
		row.add_child(UIKit.label("费用 ₡%d" % int(step.get("cost", 0)), 12, UIKit.MUTED))
		row.add_child(UIKit.spacer())
		row.add_child(UIKit.label("可用 %d / %d" % [have, need], 12, UIKit.ACCENT if have >= need else UIKit.BAD))
		v.add_child(row)
	return p

## 本次晋升的选项集合：消耗品开关 + 选用的催化核心。
func _opts() -> Dictionary:
	return { "use_stabilizer": _use_stab, "use_booster": _use_boost, "catalyst": _catalyst }

func _odds_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("③ 本次抽签表（受校准器 / 消耗品 / 核心催化 / 保底影响）", 13, UIKit.MUTED))

	var weights: Dictionary = CraftSystem.preview_odds(_family, _from_tier, _opts())
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		total = 1.0
	var segs: Array = []
	for key in ["success", "hold", "damage", "breakdown"]:
		var oc: Dictionary = GameData.outcomes.get(key, {})
		segs.append({ "label": str(oc.get("name", key)), "value": float(weights.get(key, 0.0)), "color": str(oc.get("color", "#FFFFFF")) })
	v.add_child(UIKit.ratio_bar(segs, 400, 18))

	var legend := UIKit.hbox(14)
	for key in ["success", "hold", "damage", "breakdown"]:
		var oc: Dictionary = GameData.outcomes.get(key, {})
		var pct := float(weights.get(key, 0.0)) / total * 100.0
		var col := UIKit.map_color_html(str(oc.get("color", "#FFFFFF")))
		var item := UIKit.vbox(1)
		var l1 := UIKit.label(str(oc.get("name", key)), 11, col)
		var l2 := UIKit.label("%.1f%%" % pct, 14, UIKit.TEXT)
		item.add_child(l1)
		item.add_child(l2)
		legend.add_child(item)
	v.add_child(legend)

	var fails := GameState.pity_count(_family, _from_tier)
	var step := GameData.promotion_step(_from_tier)
	var pity: Dictionary = step.get("pity", {})
	var thr := int(pity.get("threshold", 999))
	v.add_child(UIKit.label("保底进度：连续失败 %d 次 / 阈值 %d（超过后每次失败给「成功」加权 +%.1f）"
		% [fails, thr, float(pity.get("per_fail", 0))], 11, UIKit.WARN if fails > 0 else UIKit.MUTED))
	return p

func _catalyst_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("④ 核心催化（可选 · 每次晋升最多 %d 个）" % GameData.catalyst_max_per_promotion(), 13, UIKit.MUTED))

	# 选中的核心可能已被上一次晋升消耗，先兜底清除
	if _catalyst != "" and not CraftSystem.can_use_catalyst(_catalyst):
		_catalyst = ""

	var opts: Array = CraftSystem.catalyst_options()
	if opts.is_empty():
		v.add_child(UIKit.muted("仓库里没有核心。核心由高级盲盒低概率掉落；投入熔炉可把它写明在档案里的成功率加成真正兑现，但该核心会被消耗。", 12))
		return p

	for id in opts:
		var row := UIKit.hbox(8)
		var b := UIKit.btn("%s  +%d 成功率" % [GameData.item_name(id), int(CraftSystem.catalyst_points(id))], false, 250)
		b.tooltip_text = str(GameData.get_item(id).get("desc", ""))
		if id == _catalyst:
			b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.WARN, 8, Color("#FFD79A")))
			b.add_theme_color_override("font_color", Color("#0B0E14"))
		b.pressed.connect(func():
			_catalyst = "" if _catalyst == id else id
			refresh())
		row.add_child(b)
		row.add_child(UIKit.chip("持有 ×%d" % GameState.count_of(id),
			GameData.family_color(str(GameData.get_item(id).get("family", ""))), 11))
		row.add_child(UIKit.spacer())
		v.add_child(row)

	var foot := UIKit.hbox(8)
	var clear := UIKit.btn("不投入", false, 90)
	clear.disabled = _catalyst == ""
	clear.pressed.connect(func():
		_catalyst = ""
		refresh())
	foot.add_child(clear)
	foot.add_child(UIKit.spacer())
	v.add_child(foot)

	if _catalyst == "":
		v.add_child(UIKit.muted("当前未投入核心，抽签表保持原样。", 12))
	else:
		var w := UIKit.label("本次投入 %s：成功权重 +%d（从损伤 / 崩解扣除），该核心将被消耗。"
			% [GameData.item_name(_catalyst), int(CraftSystem.catalyst_points(_catalyst))], 12, UIKit.WARN)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(w)
	return p

func _action_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("⑤ 执行晋升", 13, UIKit.MUTED))

	var toggles := UIKit.hbox(10)
	for pair in [["stabilizer", "稳定剂", "_use_stab"], ["booster", "过载催化剂", "_use_boost"]]:
		var key := str(pair[0])
		var cfg: Dictionary = GameData.consumables.get(key, {})
		var b := UIKit.btn("%s（₡%d）" % [str(pair[1]), int(cfg.get("price", 0))])
		var on := _use_stab if key == "stabilizer" else _use_boost
		if on:
			b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.WARN, 8, Color("#FFD79A")))
			b.add_theme_color_override("font_color", Color("#0B0E14"))
		b.tooltip_text = str(cfg.get("desc", ""))
		b.pressed.connect(func():
			if key == "stabilizer":
				_use_stab = not _use_stab
			else:
				_use_boost = not _use_boost
			refresh())
		toggles.add_child(b)
	v.add_child(toggles)

	var step2 := GameData.promotion_step(_from_tier)
	var cost := int(step2.get("cost", 0))
	if _use_stab:
		cost += int(GameData.consumables.get("stabilizer", {}).get("price", 0))
	if _use_boost:
		cost += int(GameData.consumables.get("booster", {}).get("price", 0))

	var row := UIKit.hbox(12)
	row.add_child(UIKit.label("本次总花费 ₡%d" % cost, 13, UIKit.WARN))
	row.add_child(UIKit.spacer())
	var have := _available(_family, _from_tier)
	var need := int(GameData.recipes.get("consume", 5))
	var go := UIKit.btn("晋升 ▸", true, 150)
	go.disabled = have < need or GameState.credits < cost
	go.pressed.connect(_do_promote)
	row.add_child(go)
	v.add_child(row)

	if go.disabled:
		v.add_child(UIKit.label("材料不足（%d/%d）或信用点不够，暂时无法晋升。" % [have, need], 11, UIKit.BAD))
	return p

func _do_promote() -> void:
	var res: Dictionary = CraftSystem.promote(_family, _from_tier, [], _opts())
	if not res.get("ok", false):
		Sfx.play_error()
		toast_requested.emit(str(res.get("reason", "晋升失败")))
		return
	_last = res
	# 先播完抽签演出，再刷新界面——否则结果会在演出结束前就露出来
	await _play_spin(str(res["outcome"]))
	# 材料被大量消耗后可能已经做不了这一阶，自动落回可做的阶位
	_ensure_tier()
	refresh()
	var oc: Dictionary = GameData.outcomes.get(str(res["outcome"]), {})
	var tail := ""
	match str(res["outcome"]):
		"success":
			tail = "获得 %s" % GameData.item_name(str(res["gained"]))
		"hold":
			tail = "材料原样退回，可立刻重试"
		"damage":
			tail = "损失 %d 个材料" % (res["lost"] as Array).size()
		"breakdown":
			tail = "材料全部崩解"
	var cat_id := str(res.get("catalyst", ""))
	if cat_id != "":
		tail += " · 催化核心 %s 已被熔炉吞噬" % GameData.item_name(cat_id)
	toast_requested.emit("%s —— %s" % [str(oc.get("name", "")), tail])

# ---------------- 抽签演出 ----------------

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

	var cap := UIKit.label("熔炉抽签", 13, UIKit.MUTED)
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
	var keys := ["success", "hold", "damage", "breakdown"]
	_spin_skip = false
	_spin_layer.visible = true
	_spin_layer.modulate.a = 1.0
	_spin_title.rotation = 0.0
	_spin_title.scale = Vector2.ONE
	_spin_title.add_theme_color_override("font_color", UIKit.MUTED)
	_spin_title.text = "…"

	# 滚动阶段
	var step := 0.07
	var elapsed := 0.0
	var i := 0
	while elapsed < 0.8 and not _spin_skip:
		var k: String = str(keys[i % keys.size()])
		_spin_title.text = str(GameData.outcomes.get(k, {}).get("name", k))
		UIKit.pop(_spin_title, 1.07, 0.12)
		Sfx.play("promote_spin", randf_range(0.95, 1.3))
		await get_tree().create_timer(step, true, false, true).timeout
		elapsed += step
		i += 1

	# 定格
	var oc: Dictionary = GameData.outcomes.get(outcome, {})
	_spin_title.text = str(oc.get("name", outcome))
	_spin_title.add_theme_color_override("font_color", UIKit.map_color_html(str(oc.get("color", "#FFFFFF"))))
	UIKit.pop(_spin_title, 1.45, 0.34)
	UIKit.wobble(_spin_title, 3.0, 0.4)
	Sfx.play_outcome(outcome)
	await get_tree().create_timer(0.55 if not _spin_skip else 0.22, true, false, true).timeout

	var tw := _spin_layer.create_tween()
	tw.tween_property(_spin_layer, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): _spin_layer.visible = false)

func _result_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("上一次熔炼结果", 13, UIKit.MUTED))
	if _last.is_empty():
		v.add_child(UIKit.muted("还没有进行过晋升。选好族系与阶位，点「晋升」试试手气。", 12))
		return p
	var oc: Dictionary = GameData.outcomes.get(str(_last["outcome"]), {})
	var col := UIKit.map_color_html(str(oc.get("color", "#FFFFFF")))
	v.add_child(UIKit.label(str(oc.get("name", "")), 26, col))
	v.add_child(UIKit.muted(str(oc.get("desc", "")), 12))
	if str(_last.get("gained", "")) != "":
		var tile := UIKit.item_tile(str(_last["gained"]), GameState.count_of(str(_last["gained"])), 280)
		tile.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
				inspect_requested.emit(str(_last["gained"])))
		v.add_child(tile)
	if (_last.get("lost", []) as Array).size() > 0:
		v.add_child(UIKit.label("损毁 %d 个材料" % (_last["lost"] as Array).size(), 12, UIKit.BAD))
	return p

func _calibrator_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE_HI)
	var m := _margin(p, 12)
	var v := UIKit.vbox(8)
	m.add_child(v)
	v.add_child(UIKit.label("概率校准器（永久元升级）", 13, UIKit.ACCENT2))
	var mx := int(GameData.calibrator.get("max_level", 5))
	var lv := GameState.calibrator_level
	v.add_child(UIKit.label("等级 %d / %d · 每级把「崩解」权重 -%d 转给「成功」"
		% [lv, mx, int(GameData.calibrator.get("breakdown_reduction_per_level", 2))], 12, UIKit.TEXT))
	if CraftSystem.calibrator_maxed():
		v.add_child(UIKit.label("已满级，崩解已被完全压制。", 12, UIKit.OK))
	else:
		var row := UIKit.hbox(10)
		row.add_child(UIKit.label("升级费用 ₡%d" % CraftSystem.calibrator_price(), 13, UIKit.WARN))
		row.add_child(UIKit.spacer())
		var b := UIKit.btn("升级校准器", true, 140)
		b.pressed.connect(func():
			if CraftSystem.upgrade_calibrator():
				toast_requested.emit("校准器升级到 %d 级" % GameState.calibrator_level)
				refresh()
			else:
				toast_requested.emit("信用点不足"))
		row.add_child(b)
		v.add_child(row)
	return p

func _stats_panel() -> Control:
	var p := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	var m := _margin(p, 12)
	var v := UIKit.vbox(6)
	m.add_child(v)
	v.add_child(UIKit.label("熔炼统计", 13, UIKit.MUTED))
	var att := int(GameState.stats.get("promote_attempts", 0))
	var suc := int(GameState.stats.get("success", 0))
	var rate := (float(suc) / float(att) * 100.0) if att > 0 else 0.0
	v.add_child(UIKit.label("尝试 %d 次 · 成功 %d 次 · 实际成功率 %.1f%%" % [att, suc, rate], 12, UIKit.TEXT))
	v.add_child(UIKit.label("稳定 %d · 损伤 %d · 崩解 %d"
		% [int(GameState.stats.get("hold", 0)), int(GameState.stats.get("damage", 0)), int(GameState.stats.get("breakdown", 0))], 12, UIKit.MUTED))
	v.add_child(UIKit.label("开箱 %d 次 · 成交 %d 笔 · 累计收入 ₡%d · 累计支出 ₡%d"
		% [int(GameState.stats.get("opens", 0)), int(GameState.stats.get("sold", 0)) + int(GameState.stats.get("bought", 0)),
		   int(GameState.stats.get("earned", 0)), int(GameState.stats.get("spent", 0))], 11, UIKit.MUTED))
	v.add_child(UIKit.label("核心催化 %d 次 · 精修 %d 次 · 翻新 %d 次（徒劳 %d）"
		% [int(GameState.stats.get("catalyst_used", 0)), int(GameState.stats.get("repairs", 0)),
		   int(GameState.stats.get("refurbish", 0)), int(GameState.stats.get("refurbish_fail", 0))], 11, UIKit.MUTED))
	return p

func _margin(parent: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	parent.add_child(m)
	return m
