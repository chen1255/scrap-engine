extends Node
## 单机模拟交易所：价格随 tick 波动，随机事件按族系/阶位定向拉抬或打压，
## 玩家大量抛售会压低该类物品价格（抛压），随后逐步回弹。

signal prices_changed()
signal market_event(ev: Dictionary)

var tick: int = 0
var price_mult: Dictionary = {}     # item_id -> 本次刷新周期内的随机倍数
var dump: Dictionary = {}           # item_id -> 玩家抛售造成的累积压价
var active_event: Dictionary = {}
var event_ticks_left: int = 0
var history: Dictionary = {}        # item_id -> Array[float]，供行情折线使用

const HISTORY_LEN := 24

func _ready() -> void:
	randomize()
	for id in GameData.item_order:
		price_mult[id] = 1.0
		dump[id] = 0.0
		history[id] = []
	_roll_event()
	_refresh_prices()

# ---------------- 价格 ----------------

func event_factor(id: String) -> float:
	if active_event.is_empty():
		return 1.0
	var f: Dictionary = active_event.get("filter", {})
	var it: Dictionary = GameData.get_item(id)
	if f.has("family") and str(it.get("family", "")) != str(f["family"]):
		return 1.0
	if f.has("tier") and int(it.get("tier", 0)) != int(f["tier"]):
		return 1.0
	return float(active_event.get("factor", 1.0))

func price_of(id: String) -> int:
	var base := int(GameData.get_item(id).get("base_price", 1))
	var m := float(price_mult.get(id, 1.0))
	var d := float(dump.get(id, 0.0))
	return maxi(1, int(round(float(base) * m * event_factor(id) * maxf(0.35, 1.0 - d))))

## 品相系数：保养度越高卖得越贵（报废 0.55× ~ 崭新 1.15×）
func condition_factor(id: String) -> float:
	if GameState.count_of(id) <= 0:
		return 1.0
	return lerpf(0.55, 1.15, GameState.condition_of(id) / 100.0)

func sell_price(id: String) -> int:
	var fee := float(GameData.market_cfg.get("sell_fee", 0.05))
	return maxi(1, int(round(float(price_of(id)) * (1.0 - fee) * condition_factor(id))))

func buy_price(id: String) -> int:
	var markup := float(GameData.market_cfg.get("buy_markup", 0.2))
	return maxi(1, int(round(float(price_of(id)) * (1.0 + markup))))

func trend_of(id: String) -> float:
	## 相对上一次刷新的涨跌幅，用于 UI 显示 ↑↓
	var h: Array = history.get(id, [])
	if h.size() < 2:
		return 0.0
	var prev: float = float(h[-2])
	if prev <= 0.0:
		return 0.0
	return (float(price_of(id)) - prev) / prev

# ---------------- 买卖 ----------------

func max_sellable(id: String) -> int:
	return GameState.count_of(id)

func sell(id: String, count: int) -> Dictionary:
	if count <= 0 or GameState.count_of(id) < count:
		return { "ok": false, "reason": "数量不足" }
	var unit := sell_price(id)
	GameState.remove_item(id, count)
	GameState.add_credits(unit * count)
	var d := float(dump.get(id, 0.0)) + float(GameData.market_cfg.get("dump_impact", 0.015)) * float(count)
	dump[id] = minf(d, 0.75)
	GameState.stats["sold"] = int(GameState.stats.get("sold", 0)) + count
	GameState.stats["earned"] = int(GameState.stats.get("earned", 0)) + unit * count
	prices_changed.emit()
	GameState.save_game()
	return { "ok": true, "unit": unit, "total": unit * count }

func buy(id: String, count: int) -> Dictionary:
	if count <= 0:
		return { "ok": false, "reason": "数量无效" }
	var unit := buy_price(id)
	var total := unit * count
	if not GameState.spend_credits(total):
		return { "ok": false, "reason": "信用点不足（需要 %d）" % total }
	GameState.add_item(id, count)
	var d := float(dump.get(id, 0.0)) - float(GameData.market_cfg.get("dump_impact", 0.015)) * float(count) * 0.5
	dump[id] = maxf(0.0, d)
	GameState.stats["bought"] = int(GameState.stats.get("bought", 0)) + count
	GameState.stats["spent"] = int(GameState.stats.get("spent", 0)) + total
	prices_changed.emit()
	GameState.save_game()
	return { "ok": true, "unit": unit, "total": total }

# ---------------- 时间推进 ----------------

func advance_tick() -> void:
	tick += 1
	var vol := float(GameData.market_cfg.get("volatility", 0.14))
	var recover := float(GameData.market_cfg.get("dump_recover", 0.3))
	for id in GameData.item_order:
		price_mult[id] = randf_range(1.0 - vol, 1.0 + vol)
		var d := float(dump.get(id, 0.0))
		if d > 0.0:
			dump[id] = maxf(0.0, d * (1.0 - recover))
	_history_push()

	if event_ticks_left > 0:
		event_ticks_left -= 1
		if event_ticks_left <= 0:
			active_event = {}
			_roll_event()
	else:
		_roll_event()

	GameState.add_energy(GameState.ENERGY_REFILL_PER_TICK)
	GameState.market_tick.emit(tick)
	GameState.save_game()

func _refresh_prices() -> void:
	_history_push()
	prices_changed.emit()

func _history_push() -> void:
	for id in GameData.item_order:
		var h: Array = history.get(id, [])
		h.append(float(price_of(id)))
		while h.size() > HISTORY_LEN:
			h.pop_front()
		history[id] = h

func _roll_event() -> void:
	var events: Array = GameData.market_cfg.get("events", [])
	if events.is_empty():
		return
	var total := 0.0
	for e in events:
		total += float(e.get("weight", 1.0))
	var r := randf() * total
	var acc := 0.0
	for e in events:
		acc += float(e.get("weight", 1.0))
		if r <= acc:
			active_event = e
			event_ticks_left = int((e as Dictionary).get("ticks", 8))
			market_event.emit(e)
			return

func event_ticks() -> int:
	return event_ticks_left
