# Moodly iOS 与 moodly_server 支付链路梳理

状态：current

更新时间：2026-05-13

## 1. 目的

本文把以下几部分串起来：

1. iOS 端商品配置文档：`APP_STORE_CONNECT_SETUP`
2. 已完成的糖果实现总结：`CANDY_COMPLETION_SUMMARY`
3. 当前 iOS 实际会员订阅 / 糖果充值代码链路
4. 当前 `moodly_server` 中会员 / 糖果接口与数据落库方式

重点不是泛泛介绍，而是说明：

- iOS 发起了哪些接口
- App Store Product ID 如何映射到服务端
- 会员与糖果两条支付链路分别如何走
- 当前代码里有哪些实际行为、复用点和注意事项

---

## 2. 核心结论

### 2.1 商品配置来源

iOS 商品配置文档在：

- `moodly-ios/APP_STORE_CONNECT_SETUP.md`

该文档当前需要按最新实现理解为：

- 6 个会员商品（普通会员 3 个 + Pro 会员 3 个）
- 4 个 Moly 消耗品
- 4 个新版糖果消耗品

并且说明：

- 本地开发可用 `Products.storekit`
- Sandbox / TestFlight / 线上需在 App Store Connect 建真实商品
- 糖果的首充赠送、VIP 加赠不在 App Store Connect 配，而由服务端动态计算。当前新版首充策略：¥6 不送，¥18 送 50%，¥38 送 100%，¥128 送 120%；VIP 额外 20% 加赠仍按会员权益叠加。
- iOS 老版本不认识新 Apple Product ID，服务端需按 `x-app-version` 兜底：`1.0.5` 以下或未传版本继续下发旧 6 档，`1.0.5` 及以上下发新版 4 档。
- 旧 iOS 覆盖率足够前不要删除 App Store Connect 里的旧糖果商品；服务端 Apple 验证仍兼容旧档位订单发货。

### 2.2 当前会员链路的真实实现方式

当前 iOS 会员购买链路不是：

- `创建订单 -> StoreKit 支付 -> /vip/orders/:id/verify`

而是：

- `创建订单 -> StoreKit 支付 -> /vip/restore-purchase -> 轮询 /vip/orders/:id`

也就是说，**会员链路当前把“恢复购买接口”同时当成了 Apple IAP 验证与发会员的入口**。

### 2.3 当前糖果链路的真实实现方式

当前 iOS 糖果充值链路是标准两段式：

- `创建订单 -> StoreKit 支付 -> /candy/orders/:id/verify`

这条链路比会员链路更直接，也更接近常规的 IAP 订单核销设计。

### 2.4 两条链路共用的核心能力

会员与糖果目前共用同一套 Apple IAP 解析能力：

- `moodly_server/src/modules/membership/iap.service.ts`

这个服务当前做的是：

- 解析 `signedTransaction` 的 JWS payload
- 校验 `bundleId`
- 返回 `transactionId / productId / purchaseDate / expiresDate`

然后由上层业务模块分别判断：

- 会员：是不是 membership/vip 商品，并写会员状态
- 糖果：是不是订单对应的糖果商品，并给用户加糖果

### 2.5 App Store 3.1.1 审核合规

iOS Release 包在 App Review 期间不得展示 App 自定义的兑换码、邀请码、二维码或 H5 入口来解锁角色、糖果、会员或其他数字内容。当前生产包默认关闭这些入口，并通过 `GET /v1/app/startup-strategy` 的 `ext` 扩展字段接收服务端开关：

```json
{
  "ext": {
    "ios_feature_flags": {
      "code_redemption_entry_enabled": false
    }
  }
}
```

过审后如需恢复入口，服务端把 `src/modules/startup-strategy/startup-strategy.service.ts` 中的 `CODE_REDEMPTION_ENTRY_ENABLED` 常量改为 `true` 并重新发布服务端即可，iOS 不需要重新发版。客户端会把该开关应用到发现页兑换码、角色分享兑换、个人页邀请码、签到页邀请奖励入口。

如果需要给用户免费或折扣获取 IAP 商品，必须在 App Store Connect 中为对应 IAP 创建 Offer Codes，并使用 StoreKit / App Store 的官方兑换链路。不能使用 `/chat/v1/characters/redeem`、`/v1/invite-code/link` 等自有接口作为 iOS 生产包的促销解锁入口。

---

## 3. 商品配置与 Product ID 对照

### 3.1 iOS 侧统一商品池

iOS 统一通过 `IAPManager` 加载商品，配置在：

- `moodly-ios/Bubbly/Services/IAPManager.swift`

当前内置商品 ID：

#### 会员商品

- `bubbly.membership.monthly.first`
- `bubbly.membership.weekly`
- `bubbly.membership.monthly`
- `bubbly.membership.pro.monthly.first`
- `bubbly.membership.pro.weekly`
- `bubbly.membership.pro.monthly`

#### 糖果消耗品

- `bubbly.candy.600`
- `bubbly.candy.1800`
- `bubbly.candy.3800`
- `bubbly.candy.12800`

### 3.2 `APP_STORE_CONNECT_SETUP` 中的配置要求

商品文档中，会员与糖果配置规则分别是：

#### 会员商品

- Auto-Renewable Subscription：
  - `bubbly.membership.monthly.first`
  - `bubbly.membership.weekly`
  - `bubbly.membership.monthly`
  - `bubbly.membership.pro.monthly.first`
- Non-Renewing Subscription（固定时长单独购买，不自动续期）：
  - `bubbly.membership.pro.weekly`
  - `bubbly.membership.pro.monthly`

#### 糖果充值

- 商品类型：Consumable
- 商品：
  - `bubbly.candy.600`
  - `bubbly.candy.1800`
  - `bubbly.candy.3800`
  - `bubbly.candy.12800`

文档同时明确：

- 首充赠送由服务端控制：¥6 不送，¥18 送 50%，¥38 送 100%，¥128 送 120%
- VIP 额外 20% 加赠由服务端控制，并在 `bonus_candy` / `total_candy` 中与首充赠送叠加
- App Store Connect 只配置基础商品与基础价格

---

## 4. 会员订阅链路：iOS -> moodly_server

## 4.1 iOS 入口与商品映射

会员购买入口主要在：

- `moodly-ios/Bubbly/ViewModels/MembershipViewModel.swift`

plan 与 Apple Product ID 的映射写死在 iOS 里：

| iOS plan_id | Apple Product ID |
|---|---|
| `month_auto_first` | `bubbly.membership.monthly.first` |
| `week` | `bubbly.membership.weekly` |
| `month` | `bubbly.membership.monthly` |
| `svip_month_auto_first` | `bubbly.membership.pro.monthly.first` |
| `svip_week` | `bubbly.membership.pro.weekly` |
| `svip_month` | `bubbly.membership.pro.monthly` |

说明：

- iOS 先从服务端拿 `plan_id`
- 然后用本地 `planProductMap` 找到对应的 StoreKit 商品

### 4.2 iOS 会员接口

iOS 会员服务封装在：

- `moodly-ios/Bubbly/Services/MembershipService.swift`

实际调用接口如下：

| 方法 | 接口 | 作用 |
|---|---|---|
| `fetchPlans()` | `GET /vip/plans` | 会员页初始化，获取当前会员状态、套餐、权益 |
| `createOrder(planID:)` | `POST /vip/orders` | 创建会员订单 |
| `fetchOrderStatus(orderID:)` | `GET /vip/orders/:order_id` | 轮询订单状态 |
| `restorePurchase(receiptData:)` | `POST /vip/restore-purchase` | 恢复购买，同时也被用于支付后核销 |
| `cancelAutoRenew()` | `POST /vip/cancel-auto-renew` | 关闭自动续费标记 |

### 4.3 iOS 会员购买时序

当前 iOS 会员购买顺序是：

1. `loadData()`
   - 调 `GET /vip/plans`
   - 同时 `IAPManager.loadProducts()`
2. 用户选中套餐
   - 根据 `plan_id -> productId` 取本地 StoreKit 商品
3. 调 `POST /vip/orders`
   - 服务端先生成一笔 `pending` 会员订单
4. 调 `StoreKit product.purchase()`
5. 取 `transaction.jsonRepresentation.base64EncodedString()`
   - iOS 代码里命名为 `receiptData`
   - 但实际上传的是 **StoreKit Transaction JWS**
6. 调 `POST /vip/restore-purchase`
   - 服务端解析 Apple 交易内容
   - 激活会员并回填订单
7. 调 `GET /vip/orders/:order_id` 轮询订单状态
8. 若返回成功
   - 更新本地 `authVM.currentUser.isVip`
   - 更新 `vipExpireAt`

### 4.4 moodly_server 会员接口

服务端会员路由在：

- `moodly_server/src/modules/vip/vip.routes.ts`

当前暴露接口：

| 接口 | 作用 |
|---|---|
| `GET /v1/vip/plans` | 返回会员状态 + 套餐 + 权益 |
| `POST /v1/vip/orders` | 创建会员订单 |
| `GET /v1/vip/orders/:order_id` | 查询会员订单状态 |
| `POST /v1/vip/restore-purchase` | 恢复购买 / Apple IAP 核销 |
| `POST /v1/vip/cancel-auto-renew` | 设置 autoRenew=false |

### 4.5 moodly_server 会员订单与激活逻辑

服务端主逻辑在：

- `moodly_server/src/modules/vip/vip.service.ts`

链路拆开看：

#### A. `getPlans(userId)`

读取：

- `user.isVip`
- `user.vipExpireAt`
- `membership_plans`
- `vip_benefits`

返回给 iOS：

- `current_vip`
- `plans`
- `benefits`

#### B. `createOrder(userId, planCode, payChannel)`

做的事情：

1. 根据 `planCode` 查 `membership_plans`
2. 校验 `pay_channels` 是否支持 `apple_iap`
3. 生成 `VO_...` 订单号
4. 写入 `vip_orders`
   - `status = pending`
   - `payChannel = apple_iap`
   - `expireAt = 15 分钟后`

这里的关键映射是：

- `membership_plans.plan_code`：给 iOS 的 `plan_id`
- `membership_plans.apple_product_id`：和 Apple 商品 ID 对应

#### C. `restorePurchase(userId, receiptData)`

这是当前会员支付成功后的关键入口。

它做了这些事：

1. 调 `verifyMembershipReceipt(receiptData)`
2. 用 `IAPService.verifyReceipt()` 解析 JWS
3. 通过 `isMembershipProduct(productId)` 校验商品是否是会员商品
4. 优先找该用户最近一笔 `pending` 的 Apple 会员订单
5. 若无 pending 订单，再按 `apple_product_id = txPayload.productId` 找会员套餐
6. 计算 `vipExpireAt`
   - 优先用 Apple `expiresDate`
   - 没有就按套餐时长推算
7. 调 `applyVipActivation(...)`
   - upsert `membership_status`
   - 更新 `user.isVip / user.vipExpireAt`
   - 更新最近的 `vip_orders` 为 `paid`
   - 写入 `transactionId / receiptData / vipExpireAt / paidAt`

因此，**会员支付成功后的“发货”动作就在 `restorePurchase()`**。

#### D. `getOrder(userId, orderId)`

返回：

- `status`
- `plan_id`
- `paid_at`
- `vip_expire_at`

并且会把超时未支付订单改成 `expired`。

### 4.6 会员链路的数据库映射

相关表：

#### `membership_plans`

关键字段：

- `plan_code`
- `apple_product_id`
- `price_cny`
- `pay_channels`

#### `vip_orders`

关键字段：

- `order_id`
- `plan_code`
- `pay_channel`
- `status`
- `receipt_data`
- `transaction_id`
- `original_transaction_id`
- `vip_expire_at`

#### `membership_status`

关键字段：

- `user_id`
- `plan_id`
- `is_active`
- `expire_date`
- `auto_renew`

---

## 5. 糖果充值链路：iOS -> moodly_server

## 5.1 参考文档

糖果完成总结在：

- `CANDY_COMPLETION_SUMMARY.md`

它说明当前糖果模块已经覆盖：

- server Prisma 模型
- candy 路由与 service
- iOS `IAPManager`
- iOS `CandyService`
- iOS `WalletViewModel`

### 5.2 iOS 糖果接口

iOS 糖果服务封装在：

- `moodly-ios/Bubbly/Services/CandyService.swift`

实际调用接口如下：

| 方法 | 接口 | 作用 |
|---|---|---|
| `fetchBalance()` | `GET /candy/balance` | 获取余额 |
| `fetchPackages()` | `GET /candy/packages` | 获取套餐与动态赠送信息 |
| `createOrder(packageId:)` | `POST /candy/orders` | 创建糖果订单 |
| `verifyPurchase(orderId:signedTransaction:)` | `POST /candy/orders/:order_id/verify` | Apple IAP 验证并发糖 |
| `fetchOrderStatus(orderId:)` | `GET /candy/orders/:order_id` | 查询订单状态 |
| `fetchTransactions(...)` | `GET /candy/transactions` | 获取糖果流水 |

### 5.3 iOS 糖果购买时序

当前主要购买链路在：

- `moodly-ios/Bubbly/ViewModels/WalletViewModel.swift`

顺序是：

1. `loadData(userBalance:)`
   - `IAPManager.loadProducts()`
   - `GET /candy/packages`
2. 用户选择套餐
3. 通过 `candy_600 -> bubbly.candy.600` 规则映射到 Apple Product ID
4. 调 `POST /candy/orders`
5. 调 `StoreKit product.purchase()`
6. 取 `transaction.jsonRepresentation.base64EncodedString()`
7. 调 `POST /candy/orders/:order_id/verify`
8. 服务端发糖成功后，返回 `new_balance`
9. iOS 更新钱包余额

### 5.4 moodly_server 糖果接口

服务端糖果路由在：

- `moodly_server/src/modules/candy/candy.routes.ts`

当前暴露接口：

| 接口 | 作用 |
|---|---|
| `GET /v1/candy/balance` | 获取当前糖果余额 |
| `GET /v1/candy/packages` | 获取套餐列表与动态赠送信息 |
| `POST /v1/candy/orders` | 创建订单 |
| `GET /v1/candy/orders/:order_id` | 查询订单状态 |
| `POST /v1/candy/orders/:order_id/verify` | Apple IAP 验证并发糖 |
| `GET /v1/candy/transactions` | 获取流水 |

### 5.5 moodly_server 糖果订单与发货逻辑

服务端主逻辑在：

- `moodly_server/src/modules/candy/candy.service.ts`

#### A. `getPackages(userId)`

读取：

- `user.candyBalance`
- `user.isFirstCandyRecharge`
- `user.isVip`
- `candy_packages`

动态计算：

- `bonusCandy`
- `vipBonus`
- `totalCandy`
- 首充标签是否展示

其中：

- 新版首充：¥6 不送，¥18 送 50%，¥38 送 100%，¥128 送 120%
- iOS 老版本兜底：`x-app-version < 1.0.5` 或未传版本继续返回旧 6 档，避免老包收到新 Product ID 后无法购买
- VIP：额外 `20%`
- 两者可叠加

#### B. `createOrder(userId, packageId, payChannel)`

做的事情：

1. 查 `candy_packages`
2. 查用户是否首充 / 是否 VIP
3. 动态计算本次订单的：
   - `candy_amount`
   - `bonus_candy`
   - `total_candy`
4. 写入 `candy_orders`
   - `status = pending`
   - `expireAt = 30 分钟后`
5. 返回 `pay_params.product_id = pkg.appleProductId`

这说明糖果真实映射不是由 iOS 单独决定的，**服务端订单也保存了 package 与苹果商品的对应关系**。

#### C. `verifyAndFulfill(userId, orderId, signedTransaction)`

这是糖果发货核心入口。

它做的事情：

1. 校验订单存在
2. 若已支付则直接返回余额（幂等）
3. 校验订单未过期
4. 调 `IAPService.verifyReceipt(signedTransaction)`
5. 事务内执行：
   - 更新 `candy_orders.status = paid`
   - 写入 `transactionId / paidAt`
   - `user.candyBalance += order.totalCandy`
   - `user.isFirstCandyRecharge = false`
   - 写一条 `transactions` 流水

因此，**糖果真正的到账动作在 `/candy/orders/:order_id/verify`**。

#### D. `getTransactions(userId, params)`

读取 `transactions` 表，支持：

- `all`
- `income`
- `expense`

返回：

- `balance`
- `page / page_size / total`
- `list`

### 5.6 糖果链路的数据库映射

相关表：

#### `candy_packages`

关键字段：

- `package_id`
- `candy_amount`
- `price_cny`
- `apple_product_id`
- `tag`
- `tag_visible`

#### `candy_orders`

关键字段：

- `order_id`
- `package_id`
- `candy_amount`
- `bonus_candy`
- `total_candy`
- `pay_channel`
- `status`
- `transaction_id`

#### `transactions`

关键字段：

- `type`
- `amount`
- `label`
- `balance_after`
- `ref_id`

---

## 6. iOS 与服务端映射关系总表

## 6.1 会员订阅映射

| 层级 | 字段 | 示例 | 说明 |
|---|---|---|---|
| App Store | Product ID | `bubbly.membership.monthly` | 苹果会员商品，可能是自动续期或非续期订阅 |
| iOS 本地 | `planProductMap` | `month -> bubbly.membership.monthly` | `plan_id` 到 Product ID 的映射 |
| 服务端套餐表 | `membership_plans.plan_code` | `month` | iOS 下单传这个 |
| 服务端套餐表 | `membership_plans.apple_product_id` | `bubbly.membership.monthly` | 用于 Apple 商品反查套餐 |
| 服务端订单表 | `vip_orders.plan_code` | `month` | 订单里的套餐标识 |

## 6.2 糖果充值映射

| 层级 | 字段 | 示例 | 说明 |
|---|---|---|---|
| App Store | Product ID | `bubbly.candy.3800` | 苹果消耗型商品 |
| iOS 页面 | `package_id` | `candy_3800` 或服务端包 ID | 页面选择套餐 |
| iOS 本地 | 字符串替换 | `candy_3800 -> bubbly.candy.3800` | 当前 `WalletViewModel` 的取商品方式 |
| 服务端套餐表 | `candy_packages.apple_product_id` | `bubbly.candy.3800` | 服务端维护正式映射 |
| 服务端订单表 | `candy_orders.package_id` | 套餐 ID | 订单归属套餐 |

> 注意：糖果 iOS 与 server 的 `package_id` 命名看起来依赖约定，最好最终统一成“服务端返回什么，iOS 就直接用什么”，避免双端各自推导。

---

## 7. 当前代码里的关键差异与注意事项

### 7.1 会员链路没有独立 verify 接口

当前会员支付完成后，iOS 调用的是：

- `POST /vip/restore-purchase`

这意味着：

- “恢复购买”
- “购买后核销”

在服务端其实复用了同一个入口。

这没问题，但文档里要明确，不然很容易误以为会员链路缺了一段。

### 7.2 `receipt_data` 实际上传的是 StoreKit Transaction JWS

会员 iOS 代码字段名叫：

- `receipt_data`

但传给服务端的不是传统 base64 App receipt 文件，而是：

- `transaction.jsonRepresentation.base64EncodedString()`

服务端 `IAPService.verifyReceipt()` 也确实按 JWS payload 结构在解析。

所以现状更准确的说法应是：

- **signed transaction**

不是传统 receipt verify。

### 7.3 Apple Server Notifications 文档已写，但当前 server 未找到对应路由

`APP_STORE_CONNECT_SETUP.md` 里建议配置：

- `https://bubbly.taxiangapp.com/v1/apple/notifications`

但当前 `moodly_server/src` 和 `docs` 中**未检索到 `apple/notifications` 实现**。

这表示：

- 文档里已经预留了通知回调地址
- 但当前仓库中暂未看到对应服务端落点

如果后面要支持：

- 自动续订
- 退款
- 账单失败
- 取消订阅

建议再补一条真正的通知处理链路。

### 7.4 糖果链路比会员链路更标准

糖果链路当前是：

- 订单创建
- Apple 支付
- verify
- 发货

相比之下，会员链路把 verify 合并在 `restore-purchase` 中，语义稍绕。

### 7.5 iOS 糖果余额字段仍沿用 `molyBalance`

iOS 用户模型与钱包页面当前仍使用：

- `molyBalance`

但钱包页面和 server 接口语义已经是“糖果”。

这说明当前客户端展示层上：

- 命名还没完全从 `moly` 迁移到 `candy`

需要文档里特别标一下，避免后续继续误用字段。

### 7.6 `CandyRechargeViewModel` 与 `WalletViewModel` 的商品映射方式不一致

`WalletViewModel` 里会把：

- `candy_600`
- 转成 `bubbly.candy.600`

但 `CandyRechargeViewModel` 里是直接：

- `iapManager.product(for: package.packageId)`

如果 `package.packageId` 仍是服务端的包 ID，这里可能拿不到正确商品。

所以当前**真正更可信的主链路是 `WalletViewModel`**。

---

## 8. 本次梳理后的接口清单

## 8.1 iOS 会员实际用到的接口

- `GET /v1/vip/plans`
- `POST /v1/vip/orders`
- `GET /v1/vip/orders/:order_id`
- `POST /v1/vip/restore-purchase`
- `POST /v1/vip/cancel-auto-renew`

## 8.2 iOS 糖果实际用到的接口

- `GET /v1/candy/balance`
- `GET /v1/candy/packages`
- `POST /v1/candy/orders`
- `GET /v1/candy/orders/:order_id`
- `POST /v1/candy/orders/:order_id/verify`
- `GET /v1/candy/transactions`

---

## 9. 推荐后续动作

### 优先级 P1

1. 把会员链路在文档中明确命名为：
   - `createOrder + restorePurchase + getOrder`
2. 核对 `membership_plans.plan_code` 与 iOS `planProductMap` 是否完全一致
3. 核对 `membership_plans.apple_product_id` 与 `APP_STORE_CONNECT_SETUP` 是否完全一致
4. 核对 `candy_packages.apple_product_id` 与 `APP_STORE_CONNECT_SETUP` 是否完全一致

### 优先级 P2

1. 补 `POST /v1/vip/orders/:order_id/verify`
   - 让会员与糖果链路风格统一
2. 补 Apple Server Notifications 落点
3. 把 iOS `molyBalance` 命名逐步收敛成 `candyBalance`

### 优先级 P3

1. 清理 `CandyRechargeViewModel` 的商品 ID 获取方式
2. 统一“服务端包 ID”与“Apple Product ID”的双向映射方案

---

## 10. 关键文件索引

### iOS

- `moodly-ios/APP_STORE_CONNECT_SETUP.md`
- `moodly-ios/Bubbly/Services/IAPManager.swift`
- `moodly-ios/Bubbly/Services/MembershipService.swift`
- `moodly-ios/Bubbly/ViewModels/MembershipViewModel.swift`
- `moodly-ios/Bubbly/Services/CandyService.swift`
- `moodly-ios/Bubbly/ViewModels/WalletViewModel.swift`
- `moodly-ios/Bubbly/ViewModels/CandyRechargeViewModel.swift`

### Server

- `moodly_server/src/modules/vip/vip.routes.ts`
- `moodly_server/src/modules/vip/vip.service.ts`
- `moodly_server/src/modules/candy/candy.routes.ts`
- `moodly_server/src/modules/candy/candy.service.ts`
- `moodly_server/src/modules/membership/iap.service.ts`
- `moodly_server/prisma/schema.prisma`
