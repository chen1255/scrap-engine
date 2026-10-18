# 废料引擎 · Scrap Engine

> 赛博废料回收 · 全息拆解 · 概率晋升

一款以「爆率」为核心的单机收集类小型游戏：在轨道坟场的黑市开盲盒、拆解残骸提纯材料、把同族同阶的 5 件材料投进熔炉赌一次晋升，最后在图鉴里补齐 42 件收集品。

Godot 4.7.2 · GDScript · 零外部依赖 · 可离线单机运行

**中文** | [English](#english)

---

## 中文

### 玩法循环

```
黑市开盲盒 ──> 拆解台拆残骸 ──> 熔炉概率晋升 ──> 交易所变现
     │                │                │
     └──────────── 图鉴收集 + 全息检视 ────────────┘
```

1. **黑市 · 未知盲盒**：消耗信用点与体力购入未鉴定盲盒，开箱按掉落表（relative weight）抽 2~4 次。出货会写入图鉴，没见过的物品显示为「未知」占位图标。
2. **拆解台**：把残骸（wreck）拆成同族的低级材料（material），拆解结果**继承原物品的品相**。
3. **熔炉 · 概率晋升**：消耗 5 个同族同阶材料 + 信用点，抽一次签决定 `成功 / 稳定 / 损伤 / 崩解`；连续失败触发保底（pity），权重逐步向成功倾斜。最高可晋升到 T5。另有稳定剂与过载催化剂两种一次性道具、以及永久性的「概率校准器」元升级。
4. **交易所**：模拟市场行情，价格随波动率浮动、按周期刷新，含手续费、买入溢价、抛售冲击与恢复，以及随机市场事件。
5. **图鉴 + 全息检视**：42 件收集品的收集进度；点开任意物品进入全息检视面板，查看保养度、检视属性与词条。

### 系统一览

| 系统 | 说明 |
|---|---|
| 稀有度分层 | T1 废料级 → T2 标准级 → T3 精炼级 → T4 军工级 → T5 原型级，晋升只在相邻层级间进行 |
| 族系 | 机械 mech / 生物 bio / 数据 data，各有一套专属检视属性维度（4 维） |
| 品相（保养度） | 0~100 分档：崭新 / 良好 / 一般 / 磨损 / 报废；影响出售价系数，开箱时随机生成，拆解继承、晋升失败退还时保留 |
| 词条 | 每族系 8 条，由物品 id 确定性抽取 —— 同一件物品的词条永远一致，不同存档可复现 |
| 检视属性 | 每件物品 4 个数值，维度名由族系决定，数值取自 `data/items.json` |

### 数据规模

| 项 | 数量 |
|---|---|
| 收集品 | 42（材料 30 / 残骸 9 / 核心 3） |
| 族系 × 阶次 | 3 × 5，每族每阶 2~3 件 |
| 黑市盲盒 | 4（未鉴定赛博废料 30c、加密数据盘 120c、军用级密封箱 450c、深渊打捞舱 1200c） |
| 词条 | 24（3 族系 × 8 条） |
| 晋升配方 | 4 段（T1→T2 至 T4→T5），各带独立概率与保底参数 |
| 品相档位 | 5 |

所有数值均为纯数据驱动，改 JSON 即改玩法，无需碰代码。

### 目录结构

```
scrap-engine/
├── project.godot            # Godot 项目配置（自动加载、显示、渲染）
├── export_presets.cfg       # Windows 导出预设（图标 / 版本号 / 单文件打包）
├── data/                    # ★ 全部数值配置，纯 JSON
│   ├── items.json           #   42 件收集品：族系、阶次、价格、检视属性
│   ├── rarities.json        #   阶次、族系、品相档位与开箱品相区间
│   ├── loot_tables.json     #   黑市盲盒掉落表
│   ├── recipes.json         #   晋升配方、道具、校准器
│   ├── traits.json          #   词条池
│   └── market.json          #   行情波动、费率、市场事件
├── scenes/
│   └── main.tscn            # 唯一主场景
├── scripts/
│   ├── autoload/            # GameData / GameState / LootSystem / CraftSystem / MarketSystem
│   └── ui/                  # 主界面、6 个视图、全息检视面板、UI 组件库
├── shaders/                 # 全息卡片与全息图标着色器
├── assets/
│   ├── icons/               # 43 张 512×512 透明物品图标（含「未知」占位）
│   └── branding/            # 应用图标（png + 多尺寸 ico）
├── tests/                   # headless 概率自测
└── tools/                   # 开发期工具：图标烘焙、视图截图
```

### 运行

需要 **Godot 4.7.2-stable**。

- 编辑器：打开工程后按 `F5`
- 命令行：
  ```powershell
  Godot_v4.7.2-stable_win64.exe --path . res://scenes/main.tscn
  ```

### 数值自测

验证「黑市爆率」与「晋升抽签」的实际分布是否与配置一致（4 个盲盒 × 20000 次开箱、12 组晋升 × 1500 次抽签），通过时打印 `[PASS]` 并以退出码 0 结束：

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_rates.tscn
```

### 打包 Windows 构建

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build\windows\ScrapEngine.exe
```

需要先装好 4.7.2 的导出模板。产物为**单文件 exe**（资源包内嵌，`binary_format/embed_pck=true`），直接作为 Steam depot 目录内容即可。

开发期截图工具（需要渲染设备，不能 `--headless`）：

```powershell
Godot_v4.7.2-stable_win64.exe --path . res://tools/shot.tscn -- --view=inventory --seed
```

`--view=` 可选 `market / inventory / disassembly / promotion / exchange / codex`，`--inspect=<item_id>` 可直接打开全息检视面板。

### 许可

MIT License，见 [LICENSE](LICENSE)。

---

## English

**Scrap Engine** is a small, single-player collection game built around drop-rate gambling. Open unidentified crates at the orbital graveyard black market, disassemble wrecks into materials, feed five same-family same-tier materials into the furnace for a single probability-driven promotion roll, and complete all 42 collectibles in the codex.

Built with Godot 4.7.2 / GDScript. No external dependencies, runs fully offline.

### Core loop

```
Black market crates ──> Disassembly bench ──> Furnace promotion ──> Exchange
        │                      │                     │
        └─────────── Codex collection + holographic inspection ───────────┘
```

1. **Black market** — Spend credits and energy on unidentified crates; each open rolls 2–4 drops from a weighted loot table. New drops are recorded in the codex; unseen items render with an "unknown" placeholder icon.
2. **Disassembly bench** — Break wrecks down into lower-tier materials of the same family. The resulting condition (wear) is inherited from the source item.
3. **Furnace · probability promotion** — Consume 5 same-family same-tier materials plus credits for one draw: `success / hold / damage / breakdown`. Consecutive failures feed a pity system that shifts weight toward success. T5 is the ceiling. Also includes single-use items (stabilizer, overload catalyst) and a permanent "probability calibrator" meta-upgrade.
4. **Exchange** — A simulated player market: volatile prices with periodic refresh, sell fees, buy markup, dump impact and recovery, plus random market events.
5. **Codex + holographic inspection** — Track collection progress across 42 items and open any item to inspect its condition, stat bars, and traits.

### At a glance

| System | Detail |
|---|---|
| Rarity tiers | T1 SCRAP → T2 STANDARD → T3 REFINED → T4 MIL-SPEC → T5 PROTOTYPE; promotion only between adjacent tiers |
| Families | mech / bio / data, each with its own 4 inspection-stat dimensions |
| Condition | 0–100 graded as pristine / good / fair / worn / scrap; scales sell price. Rolled on unboxing, inherited on disassembly, preserved when a promotion fails |
| Traits | 8 per family, deterministically derived from the item id — the same item always rolls the same traits, so saves are reproducible |
| Inspection stats | 4 numeric values per item; dimension names come from the family, values from `data/items.json` |

| Content | Count |
|---|---|
| Collectibles | 42 (30 materials / 9 wrecks / 3 cores) |
| Families × tiers | 3 × 5, with 2–3 items per family-tier |
| Crates | 4 |
| Traits | 24 (3 families × 8) |
| Promotion recipes | 4 (T1→T2 … T4→T5), each with its own odds and pity parameters |
| Condition grades | 5 |

Everything is data-driven: change the JSON, change the game — no code edits needed.

### Running

Requires **Godot 4.7.2-stable**.

- Editor: open the project and press `F5`
- CLI: `Godot_v4.7.2-stable_win64.exe --path . res://scenes/main.tscn`

### Drop-rate self-test

Verifies that the actual distributions match the configured drop rates (4 crates × 20,000 opens, 12 promotion groups × 1,500 draws). Prints `[PASS]` and exits with code 0 on success:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_rates.tscn
```

### Building for Windows

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build\windows\ScrapEngine.exe
```

Requires the 4.7.2 export templates to be installed. The output is a **single self-contained exe** (the resource pack is embedded), ready to be used as a Steam depot's contents.

### License

MIT License — see [LICENSE](LICENSE).
