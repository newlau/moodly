# iOS 商品候选池汇总

状态：current summary

Owner topic：iOS payment / App Store Product ID / pricing experiment

更新时间：2026-06-27

> 本文是给业务决策使用的候选池汇总，不替代源文档。源头仍以 `moodly-ios/APP_STORE_CONNECT_SETUP.md`、`docs/ios_server_payment_linkage.md`、`moodly-ios/Bubbly/Products.storekit` 和线上接口返回为准。

## 1. 当前结论

- 当前 iOS 线上会员实验已按安全版恢复，`ios_vip_price_catalog_20260625_v2` 为 `running`，旧实验 `ios_vip_price_catalog_20260625` 保持 `paused`。
- 当前线上默认会员目录与本地 StoreKit 价格已对齐。
- 现有 iOS 商品候选池没有 55 元 Apple Product ID。
- 连续订阅商品已删除 App Store Connect 推介优惠；会员页展示价按基础月价对齐 Apple sheet。
- `bubbly.membership.pro.monthly.first` 当前 App Store 基础价按 ¥45/月处理，会员页可展示为 SVIP 连续包月 ¥45。
- iOS 价格实验已改为不使用 55 元档；SVIP 连续包月涨价组使用独立 65 元商品。
- 如要测试 55 元，必须先新增独立 Apple Product ID，并同步 iOS、服务端、StoreKit 和支付文档。

## 2. 当前线上实际下发目录

### 2.1 VIP / SVIP

| tier | plan_code | 卡位 | Apple Product ID | 类型 | 线上展示价 | StoreKit 价 |
|---|---|---|---|---|---:|---:|
| VIP | `month_auto_first` | 连续包月 | `bubbly.membership.monthly.first` | Auto-Renewable | ¥25/月 | ¥25 |
| VIP | `week` | 周卡 | `bubbly.membership.weekly` | Auto-Renewable | ¥25/周 | ¥25 |
| VIP | `month` | 月卡 | `bubbly.membership.monthly` | Auto-Renewable | ¥35/月 | ¥35 |
| SVIP | `svip_month_auto_first` | 连续包月 | `bubbly.membership.pro.monthly.first` | Auto-Renewable | ¥45/月 | ¥45 |
| SVIP | `svip_week` | 周卡 | `bubbly.membership.pro.weekly` | Non-Renewing | ¥45/周 | ¥45 |
| SVIP | `svip_month` | 月卡 | `bubbly.membership.pro.monthly` | Non-Renewing | ¥65/月 | ¥65 |

### 2.2 糖果

| package_id | Apple Product ID | 价格 | 当前是否下发 |
|---|---|---:|---|
| `candy_600` | `bubbly.candy.600` | ¥6 | 是 |
| `candy_1800` | `bubbly.candy.1800` | ¥18 | 是 |
| `candy_3800` | `bubbly.candy.3800` | ¥38 | 是 |
| `candy_12800` | `bubbly.candy.12800` | ¥128 | 是 |

### 2.3 音色卡

| package_id | Apple Product ID | 价格 | 当前是否下发 |
|---|---|---:|---|
| `voice_card_1` | `bubbly.voice_card.price_6` | ¥6 | 是 |

### 2.4 语音通话时长卡

| package_id | Apple Product ID | 时长 | 价格 | 当前是否下发 |
|---|---|---:|---:|---|
| `voice_call_minutes_10` | `bubbly.voice_call.minutes_10` | 10 分钟 | ¥18 | 是 |
| `voice_call_minutes_30` | `bubbly.voice_call.minutes_30` | 30 分钟 | ¥38.10 | 是 |
| `voice_call_minutes_90` | `bubbly.voice_call.minutes_90` | 90 分钟 | ¥48 | 是 |

注意：语音通话时长卡已在线上下发，iOS `IAPManager` 白名单也包含这 3 个 Product ID，但当前 `Products.storekit` 尚未包含它们。本地 StoreKit 调试会加载不到；App Store Connect 也需要逐项确认已创建且价格一致。

## 3. VIP / SVIP 候选池

### 3.1 VIP 周卡候选

| plan_code | Apple Product ID | 类型 | 价格 |
|---|---|---|---:|
| `week` | `bubbly.membership.weekly` | Auto-Renewable | ¥25/周 |
| `week_28` | `bubbly.membership.weekly.28` | Auto-Renewable | ¥28/周 |
| `week_35` | `bubbly.membership.weekly.35` | Auto-Renewable | ¥35/周 |
| `week_38` | `bubbly.membership.weekly.38` | Auto-Renewable | ¥38/周 |
| `week_45` | `bubbly.membership.weekly.45` | Auto-Renewable | ¥45/周 |

### 3.2 VIP 连续包月候选

| plan_code | Apple Product ID | 类型 | 价格 |
|---|---|---|---:|
| `month_auto_first` | `bubbly.membership.monthly.first` | Auto-Renewable | ¥25/月 |
| `month_auto_25` | `bubbly.membership.monthly.25` | Auto-Renewable | ¥25/月 |
| `month_auto_28` | `bubbly.membership.monthly.28` | Auto-Renewable | ¥28/月 |
| `month_auto_35` | `bubbly.membership.monthly.35` | Auto-Renewable | ¥35/月 |
| `month_auto_38` | `bubbly.membership.monthly.38` | Auto-Renewable | ¥38/月 |
| `month_auto_45` | `bubbly.membership.monthly.45` | Auto-Renewable | ¥45/月 |

### 3.3 VIP 月卡 / 年卡候选

| plan_code | Apple Product ID | 类型 | 价格 |
|---|---|---|---:|
| `month` | `bubbly.membership.monthly` | Auto-Renewable | ¥35/月 |
| `year_auto_128` | `bubbly.membership.yearly.128` | Auto-Renewable | ¥128/年 |
| `year_auto_168` | `bubbly.membership.yearly.168` | Auto-Renewable | ¥168/年 |
| `year_auto_198` | `bubbly.membership.yearly.198` | Auto-Renewable | ¥198/年 |

### 3.4 SVIP 候选

| plan_code | Apple Product ID | 类型 | 价格 |
|---|---|---|---:|
| `svip_month_auto_first` | `bubbly.membership.pro.monthly.first` | Auto-Renewable | ¥45/月 |
| `svip_month_auto_65` | `bubbly.membership.pro.monthly.65` | Auto-Renewable | ¥65/月 |
| `svip_week` | `bubbly.membership.pro.weekly` | Non-Renewing | ¥45/周 |
| `svip_month` | `bubbly.membership.pro.monthly` | Non-Renewing | ¥65/月 |

## 4. 糖果候选池

| package_id | Apple Product ID | 类型 | 价格 | 当前是否下发 |
|---|---|---|---:|---|
| `candy_100` | `bubbly.candy.100` | Consumable | ¥1 | 否，候选 |
| `candy_600` | `bubbly.candy.600` | Consumable | ¥6 | 是 |
| `candy_800` | `bubbly.candy.800` | Consumable | ¥8 | 否，候选 |
| `candy_1800` | `bubbly.candy.1800` | Consumable | ¥18 | 是 |
| `candy_3800` | `bubbly.candy.3800` | Consumable | ¥38 | 是 |
| `candy_9800` | `bubbly.candy.9800` | Consumable | ¥98 | 否，候选 |
| `candy_12800` | `bubbly.candy.12800` | Consumable | ¥128 | 是 |
| `candy_19800` | `bubbly.candy.19800` | Consumable | ¥198 | 否，候选 |

## 5. 音色卡候选池

| package_id | Apple Product ID | 类型 | 价格 | 当前是否下发 |
|---|---|---|---:|---|
| `voice_card_1_price_3` | `bubbly.voice_card.price_3` | Consumable | ¥3 | 否，候选 |
| `voice_card_1` | `bubbly.voice_card.price_6` | Consumable | ¥6 | 是 |
| `voice_card_1_price_9` | `bubbly.voice_card.price_9` | Consumable | ¥9 | 否，候选 |
| `voice_card_1_price_12` | `bubbly.voice_card.price_12` | Consumable | ¥12 | 否，候选 |
| `voice_card_1_price_15` | `bubbly.voice_card.price_15` | Consumable | ¥15 | 否，候选 |
| `voice_card_1_price_18` | `bubbly.voice_card.price_18` | Consumable | ¥18 | 否，候选 |

## 6. 语音通话时长卡目录

| package_id | Apple Product ID | 类型 | 时长 | 价格 | StoreKit 本地配置 |
|---|---|---|---:|---:|---|
| `voice_call_minutes_10` | `bubbly.voice_call.minutes_10` | Consumable | 10 分钟 | ¥18 | 缺失 |
| `voice_call_minutes_30` | `bubbly.voice_call.minutes_30` | Consumable | 30 分钟 | ¥38.10 | 缺失 |
| `voice_call_minutes_90` | `bubbly.voice_call.minutes_90` | Consumable | 90 分钟 | ¥48 | 缺失 |

## 7. 与 iOS 价格实验的匹配情况

当前 iOS 价格实验状态：

- `ios_vip_price_catalog_20260625`
- `ios_vip_price_catalog_20260625_v2`

已调整为无 55 元方案：

| variant | plan_codes | 说明 |
|---|---|---|
| `control` | `month_auto_first / week / month / svip_month_auto_first / svip_week / svip_month` | 当前线上目录；SVIP 连续包月为 ¥45 |
| `treatment_1` | `month_auto_35 / week_45 / month_auto_45 / svip_month_auto_65 / svip_week / svip_month` | 使用真实 Apple Product ID 价格；SVIP 连续包月使用 65 的独立商品 |
| `treatment_2` | 同 `treatment_1` | 权重 0，仅兼容旧 assignment，不再新分配 |

当前实验 SKU 与 StoreKit 对账为 0 mismatch；旧实验继续 `paused`，v2 已恢复为 `running`。

建议恢复后将实验数据分析窗口从恢复时间重新截断，排除 45/35 错配排查期间的数据。

## 8. 领导决策点

### 方案 A：不测 55，最快恢复实验

只使用现有候选池中的真实价格：

- VIP 可选：25 / 28 / 35 / 38 / 45 / 128 / 168 / 198
- SVIP 可选：45 / 65
- 不再通过 `price_overrides` 把已有 Product ID 展示成 55
- 服务端只需要调整实验 variants，iOS 不需要新增 Product ID

### 方案 B：坚持测试 55

必须先新增独立 Apple Product ID，并同步：

| 建议新增 Product ID | 用途 | 价格 |
|---|---|---:|
| `bubbly.membership.monthly.55` | VIP 月卡 55 | ¥55/月 |
| `bubbly.membership.pro.weekly.55` | SVIP 周卡 55 | ¥55/周 |
| `bubbly.membership.pro.monthly.55` 或新的 SVIP 连续包月 ID | SVIP 连续月 55 | ¥55/月 |

新增后还需要同步：

1. App Store Connect 商品创建与审核元数据
2. `Products.storekit`
3. `IAPManager` 商品白名单
4. `MembershipViewModel.planProductMap`
5. 服务端 `vip_plans`
6. iOS 价格实验 variants
7. 支付文档

在这些步骤完成前，不建议恢复包含 55 元档的 iOS 实验。
