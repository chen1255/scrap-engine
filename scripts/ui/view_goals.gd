extends Control
## 目标视图：有序目标清单 —— 每个目标一张卡，带进度条、奖励预览与「领取」按钮。
## 首条未完成目标标记为「推荐下一步」；已达成未领取的卡高亮为「可领取」。
## 目标数据来自 data/goals.json（Objectives 单例），本视图只读不写判定逻辑。

signal toast_requested(text: String)

var main: Node
var _list: VBoxContainer
var _summary: Label

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild()

# ---------------- 构建 ----------------

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(10)
	m.add_child(root)

	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("目标 · 作业清单", 20, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	_summary = UIKit.label("", 13, UIKit.MUTED)
	head.add_child(_summary)
	root.add_child(head)

	root.add_child(UIKit.muted("完成目标后点「领取」发放奖励（信用点 / 体力 / 物品）。目标只判定进度，不改动任何掉落与配方数值。", 12))

	var scroll := UIKit.scroll()
	root.add_child(scroll)
	_list = UIKit.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

# ---------------- 列表 ----------------

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cts: Array = Objectives.counts()
	_summary.text = "已完成 %d / %d · 可领取 %d" % [int(cts[0]), int(cts[1]), Objectives.claimable_count()]

	if Objectives.defs.is_empty():
		_list.add_child(UIKit.muted("暂无目标定义（data/goals.json）。", 13))
		return

	var next_id := Objectives.next_id()
	var claim_id := Objectives.first_claimable()
	for g in Objectives.defs:
		_list.add_child(_goal_card(g, next_id, claim_id))

func _goal_card(g: Dictionary, next_id: String, claim_id: String) -> Control:
	var id := str(g.get("id", ""))
	var done := Objectives.is_done(id)
	var claimed := Objectives.is_claimed(id)
	var claimable := done and not claimed
	var is_next := (id == next_id) and not done
	var is_claim := (id == claim_id) and claimable

	var border := UIKit.LINE
	var bg := UIKit.PANEL
	if claimable:
		border = UIKit.OK
		bg = UIKit.PANEL_HI
	elif is_next:
		border = UIKit.LINE_HI

	var p := UIKit.panel(bg, 10, border)
	var m := _margin(p, 12)

	var v := UIKit.vbox(6)
	m.add_child(v)

	var top := UIKit.hbox(8)
	var title_col := UIKit.ACCENT if is_next else (UIKit.TEXT)
	if claimed:
		title_col = UIKit.MUTED
	top.add_child(UIKit.label(str(g.get("name", id)), 15, title_col))
	if claimable:
		top.add_child(UIKit.chip("可领取", UIKit.OK, 11))
	elif claimed:
		top.add_child(UIKit.chip("已完成", UIKit.MUTED, 11))
	elif is_next:
		top.add_child(UIKit.chip("推荐下一步", UIKit.ACCENT2, 11))
	else:
		top.add_child(UIKit.chip("进行中", UIKit.LINE_HI, 11))
	top.add_child(UIKit.spacer())

	var rew := Objectives.reward_of(id)
	if not rew.is_empty():
		top.add_child(UIKit.label("奖励", 11, UIKit.MUTED))
		top.add_child(UIKit.chip(Objectives.reward_text(rew), UIKit.WARN, 11))
	v.add_child(top)

	var desc := UIKit.muted(str(g.get("desc", "")), 12)
	if claimed:
		desc.modulate = Color(1, 1, 1, 0.55)
	v.add_child(desc)

	# 进度条 + 数值
	var pr: Array = Objectives.progress(id)
	var cur := int(pr[0]) if pr.size() > 0 else 0
	var tgt := int(pr[1]) if pr.size() > 1 else 0
	var ph := UIKit.hbox(8)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = maxf(1.0, float(tgt))
	bar.value = float(mini(cur, maxi(1, tgt)))
	var fill := UIKit.OK if done else (UIKit.ACCENT2 if is_next else UIKit.ACCENT)
	bar.add_theme_stylebox_override("fill", UIKit.sb(fill, 5))
	ph.add_child(bar)
	var ptxt := "%d / %d" % [cur, tgt] if tgt > 0 else "—"
	ph.add_child(UIKit.label(ptxt, 11, UIKit.MUTED))
	v.add_child(ph)

	# 领取行
	var bottom := UIKit.hbox(8)
	bottom.add_child(UIKit.spacer())
	var btn := UIKit.btn("领取奖励" if claimable else ("已领取" if claimed else "未达成"), false, 120)
	btn.disabled = not claimable
	if is_claim:
		btn.add_theme_stylebox_override("normal", UIKit.sb(UIKit.OK, 8, UIKit.OK))
		btn.add_theme_color_override("font_color", Color("#0B0E14"))
	btn.pressed.connect(func(): _claim(id))
	bottom.add_child(btn)
	v.add_child(bottom)
	return p

func _claim(id: String) -> void:
	var r: Dictionary = Objectives.claim(id)
	if bool(r.get("ok", false)):
		Sfx.play("trade")
		# 播报「实发」而非「声明」数额：体力有上限，满体力时可能一分没到账
		var got: Dictionary = r.get("got", {})
		var rew := Objectives.reward_of(id)
		var got_txt: String = Objectives.reward_text(got)
		if got_txt == "" and not rew.is_empty():
			got_txt = "未到账（体力已满）"
		elif int(rew.get("energy", 0)) > int(got.get("energy", 0)):
			got_txt += "（体力已满，⚡未到账）"
		toast_requested.emit("已领取奖励：" + got_txt)
		refresh()
	else:
		Sfx.play_error()
		toast_requested.emit(str(r.get("reason", "无法领取")))

# ---------------- 小工具 ----------------

func _margin(parent: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	parent.add_child(m)
	return m
