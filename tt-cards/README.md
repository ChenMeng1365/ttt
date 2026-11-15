# TT Cards · FF8 九宫幻卡完整卡池资源库

《最终幻想 VIII》内嵌卡牌游戏「九宫幻卡 / Triple Triad」的**完整 110 张卡数据集**与**官方高清重制素材库**，供 `tt.rb` / `tt.html` 扩容卡池及后续玩法开发使用。

## 目录结构

```
tt-cards/
├── README.md               本说明
├── dataset/                数据集（数字版）
│   ├── cards.json           110 张卡结构化数据
│   ├── cards.csv            同内容平铺表（Excel 可直接开）
│   └── cards-stat.txt       卡池统计摘要
└── assets/                  素材库（图片版）
    ├── cards/               110 张卡面图案层 card-001.png ~ card-110.png
    ├── elements/            8 种元素图标 fire/ice/thunder/water/earth/poison/wind/holy
    └── card-back.png        卡背图
```

## 数据集口径

| 字段 | 说明 |
|---|---|
| `id` | 原作图鉴编号 1–110，与素材文件名一一对应（`card-001.png` = id 1） |
| `name` | 英文卡名（原作命名，如 `Wedge, Biggs`、`Fastitocalon-F`） |
| `type` | 图鉴分段：`monster` 1–44 怪物 / `boss` 45–77 首领 / `gf` 78–99 召唤兽 / `player` 100–110 角色 |
| `level` | 卡牌等级 1–10，每级恰好 11 张（110 = 10 × 11，与原作图鉴分布吻合） |
| `element` | 元素属性 8 种：earth / fire / holy / ice / poison / thunder / water / wind，`null` 为无属性 |
| `top` `right` `bottom` `left` | 四向数值 1–10，10 即 A |
| `ranks` | 四值速写串，按 **上右下左** 序，A 记 10（如 Squall = `A469`） |
| `image` | 对应素材文件名 |

## 卡池统计（抓取时校验）

- 总数 **110 张**，id 连续无缺失；
- 等级分布：lv1–lv10 每级 **11 张**；
- 类型分布：怪物 44 / Boss 33 / 召唤兽 22 / 角色 11；
- 带元素属性 **36 张**，覆盖全部 8 种元素；
- 双 A 面卡 **3 张**：Eden `44AA`、Doomtrain `11AA`、Rinoa `4A2A`（与原作一致）。

## 素材说明（重要）

`cards/card-NNN.png` 为 **200×200 图案层**，非成品卡面：白底 + 金色装饰边框 + 立绘，**不含数值文字**。
原渲染方案为分层叠加（参照 djzmo/triple-triad 的 `CardObject.ts`）：

```
图案层 (cards/N.png) + 数值位图 (rank-text) + 元素图标 (elements/*.png) + 拥有者底色渐变
```

即蓝方/红方由程序绘制底色，数值与元素在运行时叠加——与本项目 `tt.html` 的自绘数值方案天然兼容，图案层可直接用作卡面背景。

## 已知勘误：旧 48 张卡池数值有误

本库数据与原 `tt.rb` 的 48 张对照，发现多张数值错位/杜撰，例如：

| 卡名 | 旧值（上右下左） | 正确值 |
|---|---|---|
| Squall | 4 9 6 A | **A 4 6 9** |
| Ifrit | 6 2 7 A | **9 6 2 8** |
| Cactuar | 6 2 6 A | **6 2 6 3** |
| Carbuncle | 3 7 1 A | **8 4 A 4** |
| Bahamut | A 6 2 8 | **A 8 2 6** |

建议以本数据集为准回填游戏卡池。

## 来源与版权

- **数值数据**：[djzmo/triple-triad](https://github.com/djzmo/triple-triad)（GPL v3）`src/lib/Deck.ts`，其数据与 Final Fantasy Wiki 原作卡表逐张吻合；
- **图案素材**：来自 Qhimm 论坛 **Tripod: Remastered v1.1**（by Mcindus），经 djzmo/triple-triad 仓库分发；
- **元素图标 / 卡背**：同上仓库 `dist/assets/`；
- Final Fantasy、Triple Triad 及其素材版权归 **SQUARE ENIX** 所有。本资源库仅为个人学习研究用途收集整理，请勿商用或再分发。

抓取整理时间：2026-11-14
