# Android 支付宝订阅接入执行与排错文档

Status: current runbook, updated 2026-05-31

## 一、当前业务目标

Android 会员页重新开始新用户价格实验，并保持 iOS 与糖果业务不受影响：

- 旧实验 `android_vip_plan_catalog_v1` 已下线，服务端 fallback 为默认目录/价格
- 新实验 key：`android_vip_price_new_user_v3`
- 分组维度：`user`
- 人群：Android 新用户，`created_at >= 2026-05-31T00:00:00.000+08:00`
- `control`：展示 VIP/SVIP 连续包月、周卡、月卡
- `candidate`：展示同一套商品，只调整价格

- `month_auto_first`
  - control：VIP 连续包月 `25/月`
  - candidate：VIP 连续包月 `35/月`
- `week`
  - control：VIP 周卡 `15`
  - candidate：VIP 周卡 `15`
- `month`
  - control：VIP 月卡 `30`
  - candidate：VIP 月卡 `30`
- `svip_month_auto_first`
  - control：SVIP 连续包月 `45/月`
  - candidate：SVIP 连续包月 `45/月`
- `svip_week`
  - control：SVIP 周卡 `25`
  - candidate：SVIP 周卡 `25`
- `svip_month`
  - control：SVIP 月卡 `45`
  - candidate：SVIP 月卡 `45`

说明：

- 连续包月商品展示名统一为“连续包月”
- 连续包月下方小字统一为“可随时取消，次月仍¥xx”
- VIP 连续包月 `month_auto_first` 做 `25/月` vs `35/月` 新用户实验；SVIP 连续包月 `svip_month_auto_first` 维持 `45/月`；实验外默认兜底仍为 VIP `25/月`、SVIP `45/月`
- Android 支付宝连续包月的 `renewal_price`、`period_rule_params.single_amount`、后续自动代扣金额都按当前用户实验分组价格覆盖
- 为避免影响 iOS StoreKit，Android 实验内价格由 payload 的 `price_overrides` 控制；实验外 Android 兜底价由服务端 Android/非 Apple 支付逻辑控制，不直接修改共享 `month.price_cny`
- 实验定义执行 `prisma/upsert_android_vip_plan_catalog_experiment.sql` 幂等写入；该脚本会下线旧实验并写入新实验

## 二、不会影响的业务

本次改动按渠道和模块做了隔离：

- iOS Apple 订阅链路保持原样
- 糖果支付宝购买保持原样
- Android 会员普通展示接口继续使用 `/v1/vip/plans`
- Android 会员页不再补本地 SVIP fallback，实际展示完全以服务端分组下发为准

## 三、当前服务端实现

### 0. 新用户价格分组与追踪

实验 key：

- `android_vip_price_new_user_v3`

分组来源：

- 服务端读取 `experiments`
- 按 Redis round-robin 分配 variant
- 写入 `experiment_assignments` 锁定用户分组

追踪来源：

- `GET /v1/vip/plans` 实际下发套餐时写入 `experiment_exposures`
- `exposure_type`: `vip_plan_catalog_served`
- `surface`: `vip.plans`
- `payload_snapshot`: 实际 variant payload
- `metadata.visible_plan_codes`: 本次下发的商品列表
- `metadata.price_overrides`: 本次价格覆盖

接口返回：

- `data.experiment.experiment_key`
- `data.experiment.assignment_id`
- `data.experiment.variant_key`
- `data.experiment.version`
- `data.experiment.reason`
- `data.experiment.exposure_key`

### 1. 连续包月首次支付并签约

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
- `svip_month`
- `svip_week`

服务端重新读取同一用户的 `android_vip_price_new_user_v3` 分组，并按 payload 价格生成支付宝订单：

- control：`week=15`、`month=30`、`svip_week=25`、`svip_month=45`
- candidate：`week=15`、`month=30`、`svip_week=25`、`svip_month=45`

### 5. 后续自动续费

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

- control：`month_auto_first` 首扣/续扣 `25`，`svip_month_auto_first` 首扣/续扣 `45`
- candidate：`month_auto_first` 首扣/续扣 `35`，`svip_month_auto_first` 首扣/续扣 `45`
- 实验外 Android/非 Apple 支付兜底：`month_auto_first` 首扣/续扣 `25`，`svip_month_auto_first` 首扣/续扣 `45`
- 签约参数 `period_rule_params.single_amount`、后续自动续费代扣金额、会员页 `renewal_note` 必须一致
- 会员页 `renewal_note` 展示为“可随时取消，次月仍¥xx”

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

### Phase 1：首次支付并签约

1. Android 会员页确认接口返回 `experiment.variant_key`
2. 确认 control/candidate 都展示 `month_auto_first/week/month/svip_month_auto_first/svip_week/svip_month`
3. 确认连续包月卡片标题为“连续包月”，小字为“可随时取消，次月仍¥xx”
4. 分别在 control 和 candidate 验证连续包月签约金额
5. 勾选自动续费协议
6. 选择 `month_auto_first` 点击购买
7. 应拉起支付宝支付并签约
8. 支付完成后：
   - `vip_orders` 应新增一条 `subscription_initial`
   - `vip_subscriptions` 应有 `pending_sign/active`

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

实验分组与曝光 SQL：

```sql
SELECT experiment_key, unit_id, variant_key, experiment_version, reason, assigned_at, last_seen_at
FROM experiment_assignments
WHERE experiment_key = 'android_vip_price_new_user_v3'
ORDER BY updated_at DESC
LIMIT 20;
```

```sql
SELECT exposure_key, user_id, variant_key, exposure_type, surface, platform, app_version, request_id, created_at
FROM experiment_exposures
WHERE experiment_key = 'android_vip_price_new_user_v3'
ORDER BY created_at DESC
LIMIT 20;
```

### Phase 2：签约成功

预期：

- `vip_subscriptions.status = active`
- `vip_subscriptions.auto_renew = 1`
- `agreement_no` 已回填

### Phase 2.5：单独购买

1. Android 会员页分别命中 `control` 和 `candidate`
2. 选择 `week/month/svip_week/svip_month`
3. 勾选充值协议
4. 点击购买
5. 应拉起普通支付宝支付，不创建 `vip_subscriptions`
6. control 的 `vip_orders.amount` 应分别为 `15/30/25/45`
7. candidate 的 `vip_orders.amount` 应分别为 `15/30/25/45`

### Phase 3：后续续费

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

### 2. 首扣/续扣金额不对

当前首扣/续扣和单品价格都不完全依赖数据库共享价格：

- Android 金额来自 `android_vip_price_new_user_v3.payload.price_overrides`
- 展示顺序来自 `payload.plan_codes`
- VIP 连续包月 `month_auto_first` 当前为 control 25、candidate 35；SVIP 连续包月 `svip_month_auto_first` 维持 45；旧用户或不命中人群走 Android/非 Apple 支付兜底目标价
- 其他实验价仍要求用户命中新实验人群；旧用户或不命中人群会按默认目录/价格 fallback
- 首扣、签约 `single_amount`、续扣订单 `amount` 都应与同一用户分组一致

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

1. 执行 `prisma/upsert_android_vip_plan_catalog_experiment.sql`：下线旧实验，写入新实验，补齐连续包月展示文案
2. 测试环境确认 `/v1/vip/plans?platform=android`、单独购买、支付并签约、后续续费链路闭环
3. 小流量时可把新实验 `candidate.weight` 调低，例如 control `95` / candidate `5`
4. 观察 `experiment_assignments`、`experiment_exposures`、`vip_orders`、`vip_subscriptions`、`vip_status`
5. 稳定后再逐步放量

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
