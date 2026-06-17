# Android 支付宝订阅接入执行与排错文档

Status: current runbook, updated 2026-06-17

## 一、当前业务目标

Android 会员页不再做新用户会员目录实验，改为服务端直接全量下发固定时长套餐，并保持 iOS 与糖果业务不受影响：

- 普通会员下发：`month`、`week`、`year`
  - 月卡 `25`
  - 周卡 `25`
  - 年卡 `168`
- Pro 会员下发：`svip_month`、`svip_week`、`svip_year`
  - Pro 月卡 `45`
  - Pro 周卡 `45`
  - Pro 年卡 `298`

说明：

- 连续包月 `month_auto_first` / `svip_month_auto_first` 不再出现在 Android 会员页下发目录。
- 自动续费相关字段对新下发目录隐藏：`is_subscription=false`、`purchase_type=single_purchase`、`agreement_text=null`、`renewal_note=null`。
- 月卡价格对齐原连续包月：普通会员月卡 `25`，Pro 月卡 `45`。
- 原月卡卡位替换为年卡：普通会员年卡 `year=168`，Pro 年卡 `svip_year=298`。
- 历史签约、取消、自动续费对账能力保留给已签约用户兼容；新购买入口走普通会员订单。

## 二、不会影响的业务

本次改动按渠道和模块做了隔离：

- iOS Apple 订阅链路保持原样
- iOS Apple 订阅和糖果 IAP 链路保持原样
- Android 糖果钱包新增支付宝 / 微信支付方式选择，不影响会员价格实验分组
- Android 会员普通展示接口继续使用 `/v1/vip/plans`
- Android 会员页不再补本地 SVIP fallback，实际展示完全以服务端下发为准

## 三、当前服务端实现

### 0. 会员目录直接下发

- `GET /v1/vip/plans?platform=android` 直接返回固定时长目录，不读取会员目录实验。
- `experiment` 字段返回 `null`。
- 旧实验 assignment/exposure 仅保留用于历史分析。

### 1. 历史连续包月首次支付并签约

当前新下发目录不会触达该流程；以下仅用于排查历史已签约或旧缓存请求。

Android 调用：

- `POST /v1/vip/subscriptions/alipay/pay-and-sign`

服务端动作：

1. 创建 `vip_subscriptions`
2. 创建 `vip_orders`
3. 调支付宝 `alipay.trade.app.pay`
4. 在支付参数中附带 `agreement_sign_params`
5. 返回 `pay_params` 给 Android

Android 使用：

- `PayTask.payV2(...)`

### 2. 支付回调

支付宝支付成功回调：

- `/v1/vip/pay/notify/alipay`

服务端动作：

1. 校验支付成功
2. 查询订单状态
3. 更新 `vip_orders.pay_status=paid`
4. 开通会员
5. 若该订单绑定订阅，则记为 `subscription_initial`

### 3. 签约回调

同一路由处理签约状态：

- `/v1/vip/pay/notify/alipay`

服务端动作：

1. 更新 `agreement_no`
2. 更新 `vip_subscriptions.status=active`
3. 更新 `auto_renew=true`
4. 计算 `next_deduct_at`

### 4. 单独购买

Android 调用：

- `POST /v1/vip/orders`

适用套餐：

- `month`
- `week`
- `year`
- `svip_month`
- `svip_week`
- `svip_year`

服务端按固定下发口径生成支付宝/微信普通订单：

- 普通会员：`month=25`、`week=25`、`year=168`
- Pro 会员：`svip_month=45`、`svip_week=45`、`svip_year=298`

### 4.1 微信单次购买（1.1.0）

状态：implementation record，2026-06-07。

Android 会员页从 1.1.0 开始支持在底部栏选择支付方式：

- 默认支付方式仍为支付宝。
- 当前服务端不再下发连续包月套餐，支付宝/微信均走普通订单 `POST /v1/vip/orders`。
- 普通订单只做当次扣款，不创建/处理 `vip_subscriptions`，不展示《自动续费服务协议》。
- 微信订单仍用 `GET /v1/vip/orders/:order_id` 轮询确认支付结果。
- Android 客户端新增 `WXPayEntryActivity` 作为微信支付 SDK 回调入口。

当前普通会员月卡订单金额为 `25`，Pro 月卡订单金额为 `45`；服务端实际金额以 `getOrderChargeAmount(plan, pay_channel, priceOverrides)` 为准。

微信支付上线前必须确认：

- Android `WECHAT_APP_ID` 与微信开放平台应用 AppID 一致。
- 服务端 `WECHAT_PAY_APP_ID`、`WECHAT_PAY_MCH_ID`、`WECHAT_PAY_NOTIFY_URL`、`WECHAT_PAY_PUBLIC_KEY_PATH`、`WECHAT_PAY_PRIVATE_KEY_PATH` 已配置。
- 微信商户平台 App 支付已开通，应用包名和签名已登记。
- `WECHAT_PAY_NOTIFY_URL` 指向可公网访问的 `/v1/vip/pay/notify/wechat`。
- `vip_plans.pay_channels` 包含 `wechat`，当前 seed 已包含。

### 4.2 Android 糖果钱包微信支付（1.1.0）

状态：implementation record，2026-06-08。

Android 糖果钱包底部购买栏新增支付方式选项卡：

- 默认支付方式仍为支付宝。
- 选择支付宝时，糖果充值继续走 `POST /v1/candy/orders`，请求体 `pay_channel=alipay`。
- 选择微信时，糖果充值走同一接口，请求体 `pay_channel=wechat`，客户端拉起微信 App 支付。
- 音色卡 tab 使用 `POST /v1/candy/voice-cards/orders`，同样按所选方式传 `pay_channel=alipay/wechat`。
- 糖果订单仍用 `GET /v1/candy/orders/:order_id` 轮询确认支付结果；音色卡订单用 `GET /v1/candy/voice-cards/orders/:order_id` 轮询确认。
- 音色卡商品 `voice_card_1` 固定到账 1 张，定价 ¥6，非会员也可单独购买；Android 客户端本地 fallback、iOS StoreKit 和服务端订单常量需保持一致。
- 如果音色卡下单返回 `403 / VIP_REQUIRED / 仅会员可购买音色卡`，说明服务端仍是旧版本会员门槛逻辑，需要发布新服务端或确认实例已重启。
- 聊天内快捷糖果充值当前仍保持原支付宝链路，未纳入本次钱包选项卡改造。

微信支付上线前必须确认：

- Android `WECHAT_APP_ID` 与微信开放平台应用 AppID 一致。
- 微信商户平台 App 支付已开通，应用包名和签名已登记。
- 服务端微信支付配置可生成糖果和音色卡订单的 `pay_params`。
- 糖果/音色卡微信支付结果以客户端轮询订单状态为主；服务端在轮询接口里主动查询微信订单状态并幂等入账。

### 5. 历史订阅后续自动续费

当前已补服务端维护任务：

- 每 10 分钟扫描一次
- 任务名：`vip-subscription-maintenance`

处理逻辑：

1. 同步待签约/活跃协议状态
2. 扫描到期订阅
3. 对 `agreement_no` 发起商家扣款
4. 成功则新增/更新续费订单并延长会员
5. 失败则标记 `past_due`，12 小时后重试

价格口径：

- 新下发普通会员：月卡/周卡/年卡 `25/25/168`
- 新下发 Pro 会员：月卡/周卡/年卡 `45/45/298`
- 历史签约用户：`month_auto_first` 续扣 `25`，`svip_month_auto_first` 续扣 `45`
- 新下发会员页不展示 `renewal_note`，不展示《自动续费服务协议》

## 四、关键文件

### 服务端

- `/Users/liuyingying/Desktop/moodly_server/src/modules/vip/vip.service.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/modules/vip/vip.routes.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/modules/vip/vip.subscription.scheduler.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/vendor/pay/alipay.ts`
- `/Users/liuyingying/Desktop/moodly_server/src/vendor/pay/interface.ts`

### Android

- `/Users/liuyingying/Desktop/moodly/moodly_android/app/src/main/java/com/yuewei/moodly/data/network/VipApiService.kt`
- `/Users/liuyingying/Desktop/moodly/moodly_android/app/src/main/java/com/yuewei/moodly/ui/membership/MembershipViewModel.kt`
- `/Users/liuyingying/Desktop/moodly/moodly_android/app/src/main/java/com/yuewei/moodly/ui/screens/SubscriptionScreen.kt`

## 五、数据库表重点

### 1. `vip_subscriptions`

重点字段：

- `external_agreement_no`
- `agreement_no`
- `status`
- `auto_renew`
- `signed_at`
- `next_deduct_at`
- `last_deduct_at`
- `deduct_fail_count`

### 2. `vip_orders`

重点字段：

- `order_id`
- `pay_status`
- `order_type`
  - `normal`
  - `subscription_initial`
  - `subscription_renewal`
- `subscription_id`

### 3. `vip_status`

重点字段：

- `is_active`
- `expire_date`
- `auto_renew`
- `original_transaction_id`

## 六、联调验证步骤

### Phase 1：普通订单首次支付

1. Android 会员页确认接口不返回实验分组，`experiment=null`
2. 确认普通会员展示 `month/week/year`，Pro 展示 `svip_month/svip_week/svip_year`
3. 确认页面不展示“连续包月”、`renewal_note` 或《自动续费服务协议》
4. 选择 `month` 点击购买，应拉起支付宝普通支付
5. 支付完成后：
   - `vip_orders` 应新增一条 `normal`
   - 不应新建 `vip_subscriptions`
   - `vip_status.auto_renew=false`

查库 SQL：

```sql
SELECT order_id, plan_code, pay_status, order_type, subscription_id, transaction_id
FROM vip_orders
ORDER BY created_at DESC
LIMIT 20;
```

```sql
SELECT id, user_id, plan_id, external_agreement_no, agreement_no, status, auto_renew, next_deduct_at, last_deduct_at, deduct_fail_count
FROM vip_subscriptions
ORDER BY created_at DESC
LIMIT 20;
```

历史实验分组与曝光 SQL（仅查旧数据）：

```sql
SELECT experiment_key, unit_id, variant_key, experiment_version, reason, assigned_at, last_seen_at
FROM experiment_assignments
WHERE experiment_key IN ('android_vip_price_new_user_v3', 'android_vip_catalog_copy_year_anchor_v1')
ORDER BY updated_at DESC
LIMIT 20;
```

```sql
SELECT exposure_key, user_id, variant_key, exposure_type, surface, platform, app_version, request_id, created_at
FROM experiment_exposures
WHERE experiment_key IN ('android_vip_price_new_user_v3', 'android_vip_catalog_copy_year_anchor_v1')
ORDER BY created_at DESC
LIMIT 20;
```

### Phase 2：历史签约成功

预期：

- `vip_subscriptions.status = active`
- `vip_subscriptions.auto_renew = 1`
- `agreement_no` 已回填

### Phase 2.5：单独购买

1. Android 会员页不返回实验分组，`experiment=null`
2. 选择 `month/week/year/svip_month/svip_week/svip_year`
3. 勾选充值协议
4. 点击购买
5. 应拉起普通支付宝支付，不创建 `vip_subscriptions`
6. `vip_orders.amount` 应分别为 `25/25/168/45/45/298`

### Phase 3：历史订阅后续续费

可临时把某条订阅的 `next_deduct_at` 改到当前时间前：

```sql
UPDATE vip_subscriptions
SET next_deduct_at = DATE_SUB(NOW(), INTERVAL 5 MINUTE)
WHERE id = '你的订阅ID';
```

等待任务执行后检查：

- `vip_orders` 出现 `subscription_renewal`
- `vip_status.expire_date` 延长
- `vip_subscriptions.last_deduct_at` 更新
- `vip_subscriptions.next_deduct_at` 更新

## 七、常见问题排查

### 1. 支付宝报“交易订单处理失败”

优先排查：

- 是否使用了旧 AppID
- 支付串是否为 `alipay.trade.app.pay`
- 是否仍在走纯签约接口
- 支付宝后台是否已绑定包名与 SHA1

### 2. 金额不对

当前 Android 新下发套餐按固定价格生成普通订单：

- 展示顺序来自服务端固定目录：`month/week/year/svip_month/svip_week/svip_year`
- 普通会员月卡/周卡/年卡 `25/25/168`
- Pro 月卡/周卡/年卡 `45/45/298`
- 历史订阅续扣：`month_auto_first=25`，`svip_month_auto_first=45`
- 若新购买仍出现 `subscription_initial` 或《自动续费服务协议》，优先确认客户端是否还在使用旧缓存计划。

### 3. 支付成功但没开会员

排查顺序：

1. `/v1/vip/pay/notify/alipay` 是否收到回调
2. `vip_orders.pay_status` 是否变成 `paid`
3. `users.vip_expire_at` 是否更新
4. `vip_status.is_active` 是否为 `1`

### 4. 已签约但没有自动续费

排查顺序：

1. `agreement_no` 是否已写入
2. `vip_subscriptions.status` 是否为 `active`
3. `auto_renew` 是否为 `1`
4. `next_deduct_at` 是否有值
5. 服务端定时任务日志是否报错

### 5. 续费失败

当前处理：

- 订阅转为 `past_due`
- `deduct_fail_count + 1`
- 12 小时后自动重试

## 八、上线建议

建议顺序：

1. 执行 `prisma/upsert_android_vip_experiment_plans.sql`，确认 `year/svip_year` 存在。
2. 执行 `prisma/update_vip_plans_price.sql`，确认月卡价格为 `25/45`。
3. 如历史实验仍为 running，执行 `prisma/upsert_android_vip_plan_catalog_experiment.sql` 将其写为 `draft`。
4. 测试环境确认 `/v1/vip/plans?platform=android` 返回 `month/week/year/svip_month/svip_week/svip_year`，且无 `renewal_note` / `agreement_text`。
5. 验证支付宝普通订单、微信普通订单、历史订阅取消/续费对账。

确认旧实验下线 SQL：

```sql
UPDATE experiments
SET status = 'draft', updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key = 'android_vip_plan_catalog_v1';
```

## 九、后续可继续优化

- 补专门的续费任务管理日志表
- 增加失败重试上限与告警
- 增加手动触发某条订阅续费的后台接口
- 增加订阅详情接口，返回更完整的 `expire_at`
