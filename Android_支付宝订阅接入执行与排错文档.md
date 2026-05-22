# Android 支付宝订阅接入执行与排错文档

## 一、当前业务目标

Android 会员页做商品目录分组实验，并保持 iOS 与糖果业务不受影响：

- `control`：旧 Android 会员目录，继续展示 VIP/SVIP 六档
- `candidate`：展示 VIP 4 档实验商品，并展示 SVIP 周卡/月卡/年卡三档非订阅；不展示 SVIP 连续包月

- `month_auto_first`
  - 首次支付：`15`
  - 后续续费：`25`
- `month`
  - 月卡，单独购买：`15`
- `week`
  - 周卡，单独购买：`15`
- `year`
  - 年卡，单独购买：`98`
- `svip_week`
  - SVIP 周卡，单独购买：`25`
- `svip_month`
  - SVIP 月卡，单独购买：`45`
- `svip_year`
  - SVIP 年卡，单独购买：`168`

说明：

- 当前数据库里的 `month_auto_first.priceCny` 仍可能是 `25`
- 为避免影响 iOS StoreKit 月卡，Android candidate 的 `month=15` 由实验 payload 的 `price_overrides` 控制
- Android candidate 不下发 `svip_month_auto_first`，因此没有 SVIP 连续包月
- `year` / `svip_year` 需要当前数据库执行 `prisma/upsert_android_vip_experiment_plans.sql` 做幂等补齐
- 实验定义需要执行 `prisma/upsert_android_vip_plan_catalog_experiment.sql` 做幂等补齐，默认 `draft`，确认后再改 `running`

## 二、不会影响的业务

本次改动按渠道和模块做了隔离：

- iOS Apple 订阅链路保持原样
- 糖果支付宝购买保持原样
- Android 会员普通展示接口继续使用 `/v1/vip/plans`
- Android 会员页不再补本地 SVIP fallback，实际展示完全以服务端分组下发为准

## 三、当前服务端实现

### 0. 商品目录分组与追踪

实验 key：

- `android_vip_plan_catalog_v1`

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
- `year`

服务端重新读取同一用户的 `android_vip_plan_catalog_v1` 分组，并按 candidate payload 价格生成支付宝订单：

- `month`: `15`
- `week`: `15`
- `year`: `98`
- `svip_week`: `25`
- `svip_month`: `45`
- `svip_year`: `168`

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
2. 如果是 `candidate`，确认 VIP 展示 `month_auto_first/month/week/year`，SVIP 展示 `svip_week/svip_month/svip_year`，且不展示 `svip_month_auto_first`
3. 如果是 `control`，确认展示旧 Android VIP/SVIP 六档
4. 勾选自动续费协议
5. 选择 `month_auto_first` 点击购买
6. 应拉起支付宝支付并签约
7. 支付完成后：
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
WHERE experiment_key = 'android_vip_plan_catalog_v1'
ORDER BY updated_at DESC
LIMIT 20;
```

```sql
SELECT exposure_key, user_id, variant_key, exposure_type, surface, platform, app_version, request_id, created_at
FROM experiment_exposures
WHERE experiment_key = 'android_vip_plan_catalog_v1'
ORDER BY created_at DESC
LIMIT 20;
```

### Phase 2：签约成功

预期：

- `vip_subscriptions.status = active`
- `vip_subscriptions.auto_renew = 1`
- `agreement_no` 已回填

### Phase 2.5：单独购买

1. Android 会员页命中 `candidate`
2. 选择 `month/week/year/svip_week/svip_month/svip_year`
3. 勾选充值协议
4. 点击购买
5. 应拉起普通支付宝支付，不创建 `vip_subscriptions`
6. `vip_orders.amount` 应分别为 `15/15/98/25/45/168`

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

### 2. 首月金额不对

当前首月 `15` 和 candidate 单品价格都不完全依赖数据库共享价格：

- `month_auto_first` 首付金额在订阅逻辑里固定按 `15`
- `month/week/year/svip_week/svip_month/svip_year` Android candidate 单独购买金额来自 `android_vip_plan_catalog_v1.payload.price_overrides`
- `year` / `svip_year` 需要当前数据库已执行 `prisma/upsert_android_vip_experiment_plans.sql`
- 用户必须先命中 `candidate`，否则 `control` 仍按旧目录和旧价格口径

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

1. 先执行 `prisma/upsert_android_vip_experiment_plans.sql` 补齐年卡
2. 再执行 `prisma/upsert_android_vip_plan_catalog_experiment.sql` 写入实验定义
3. 测试环境确认接口和支付链路闭环后，把实验改为 `running`
4. 小流量先把 `candidate.weight` 调低，例如 control `95` / candidate `5`
5. 观察 `experiment_assignments`、`experiment_exposures`、`vip_orders`、`vip_subscriptions`、`vip_status`
6. 稳定后再逐步放量

启用实验 SQL：

```sql
UPDATE experiments
SET status = 'running', updated_at = CURRENT_TIMESTAMP(3)
WHERE experiment_key = 'android_vip_plan_catalog_v1';
```

## 九、后续可继续优化

- 补专门的续费任务管理日志表
- 增加失败重试上限与告警
- 增加手动触发某条订阅续费的后台接口
- 增加订阅详情接口，返回更完整的 `expire_at`
