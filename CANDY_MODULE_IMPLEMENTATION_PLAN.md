# Moodly 糖果模块接入方案

状态：historical plan（2026-06-05 已同步会员充值额外 20% 加赠移除口径）

## A. 项目现状审查结果

### 1. 服务端现状（moodly_server）

#### 已有能力

**数据库表结构（Prisma Schema）：**
- ✅ `users` 表：已有 `molyBalance` 字段（Int，默认0）用于存储虚拟币余额
- ✅ `transactions` 表：通用流水表，包含 userId, type, amount, description, refId, createdAt
- ✅ `moly_packages` 表：虚拟币充值套餐表，包含：
  - package_id, moly_amount, price_cny, bonus_amount
  - is_first_purchase, apple_product_id, is_active
- ✅ `vip_orders` 表：会员订单表（可参考结构）
- ✅ `membership_plans` 表：会员套餐表（可参考结构）

**已实现模块：**
- ✅ `/src/modules/wallet/` - 钱包模块
  - `wallet.routes.ts`: 已有 /balance, /packages, /topup, /transactions 接口
  - `wallet.service.ts`: 已实现余额查询、套餐列表、充值、流水查询、消费扣款
- ✅ `/src/modules/membership/` - 会员模块
  - `membership.routes.ts`: /plans, /subscribe, /status
  - `membership.service.ts`: 会员订阅、状态查询
  - `iap.service.ts`: Apple IAP 验证（使用 JWS 解析，验证 bundleId）
- ✅ 认证中间件：`app.authenticate`
- ✅ 错误处理：`Errors` 工具类
- ✅ 分页工具：`paginationToSkipTake`, `paginate`

**IAP 验证方式：**
- 使用 App Store Server API v2 的 JWS (JSON Web Signature) 格式
- 解析 signedTransaction，验证 bundleId
- 返回 transactionId, productId, purchaseDate 等信息

**接口返回结构：**
- 标准格式：直接返回数据对象或数组
- 错误通过 Errors 工具类抛出

**数据库命名风格：**
- 表名：snake_case（如 moly_packages, vip_orders）
- 字段名：camelCase 在代码中，snake_case 在数据库（通过 @map 映射）

#### 可复用能力

1. **IAP 验证链路**：`IAPService.verifyReceipt()` 可直接复用
2. **钱包服务**：`WalletService` 已实现完整的余额、充值、流水逻辑
3. **事务处理**：会员订阅中的事务处理模式可参考
4. **分页查询**：通用分页工具可直接使用

#### 缺失能力

1. ❌ **糖果订单表**：当前没有独立的糖果充值订单表（candy_orders）
2. ❌ **首充标记**：用户表中没有 `is_first_candy_recharge` 字段
3. ✅ **会员充值额外 20% 加赠**：已确认不再实现，充值只保留首充赠送
4. ❌ **糖果套餐动态配置**：moly_packages 表缺少 sort, tag, tag_visible, is_popular 字段
5. ❌ **订单状态查询接口**：/candy/orders/{order_id} 未实现
6. ❌ **流水类型筛选**：transactions 查询不支持 type 过滤（all/income/expense）
7. ❌ **流水 label 映射**：transaction 表只有 description，没有结构化的 label 字段
8. ❌ **订单过期机制**：没有订单过期时间和状态管理

---

## B. 糖果模块落地方案

### 1. 数据结构设计

#### 新增表：candy_orders
- order_id（唯一订单号）
- user_id, package_id
- candy_amount, bonus_candy, total_candy
- price, pay_channel, status
- transaction_id（Apple 交易ID）
- expire_at, paid_at

#### 修改 users 表
- 新增：candy_balance（糖果余额）
- 新增：is_first_candy_recharge（首充标记）

#### 修改 candy_packages 表（复用 moly_packages 或新建）
- 新增：sort, tag, tag_visible, is_popular

#### 修改 transactions 表
- 新增：label（业务标签）
- 新增：balance_after（操作后余额）

---

### 2. 接口实现方案

#### 核心接口清单

**GET /v1/candy/balance**
- 返回：{ balance: 223 }
- 复用：查询 users.candy_balance

**GET /v1/candy/packages**
- 返回：套餐列表 + 首充标记 + 当前余额
- 逻辑：
  - 查询 users.is_first_candy_recharge
  - 查询 candy_packages（按 sort 排序）
  - 计算首充赠送：is_first_recharge ? candy_amount : 0
  - 不再计算会员充值额外 20% 加赠
  - total_candy = candy_amount + 首充赠送

**POST /v1/candy/orders**
- 请求：{ package_id, pay_channel }
- 返回：订单信息 + pay_params
- 逻辑：
  - 创建 candy_orders 记录（status: pending）
  - 生成 order_id（CO_时间戳_随机）
  - 设置 expire_at（30分钟后）
  - 返回 Apple Product ID

**GET /v1/candy/orders/:order_id**
- 返回：订单状态 + 到账糖果 + 新余额
- 逻辑：查询 candy_orders 表

**GET /v1/candy/transactions**
- 参数：type (all/income/expense), page, page_size
- 返回：分页流水列表 + 当前余额
- 逻辑：
  - 根据 type 过滤 amount 正负
  - 返回 label, amount, balance_after

---

### 3. 支付链路设计

#### Apple IAP 充值流程

```
1. 用户选择套餐
   ↓
2. 调用 POST /candy/orders 创建订单
   ← 返回 order_id + apple_product_id
   ↓
3. iOS 调用 StoreKit purchase(product_id)
   ↓
4. 购买成功，获取 transaction
   ↓
5. 提取 transaction.jwsRepresentation
   ↓
6. 调用 POST /candy/orders/:order_id/verify
   请求体：{ signed_transaction: "..." }
   ↓
7. 服务端验证 JWS
   - 解析 transactionId, productId
   - 验证 bundleId
   - 检查订单状态（幂等）
   ↓
8. 发糖逻辑（事务）
   - 更新 candy_orders.status = 'paid'
   - 增加 users.candy_balance
   - 设置 users.is_first_candy_recharge = false
   - 创建 transactions 流水
   ↓
9. 返回成功
   ← { success: true, new_balance: 4723 }
   ↓
10. iOS 刷新余额
```

#### 幂等与事务保护

- 使用 transaction_id 作为唯一键
- 验证前检查订单状态，已支付则直接返回
- 使用数据库事务保证余额和流水一致性
- 订单过期检查：expire_at < now 则拒绝

---

### 4. 会员充值加赠策略

**首充赠送（服务端控制）：**
- 条件：users.is_first_candy_recharge = true
- 赠送：candy_amount（1:1 赠送）
- 标签：显示"首充多赠XXX糖果"

**会员充值额外 20% 赠送：**
- 状态：已移除，不再实现
- 到账：total = candy_amount + 首充赠送

**示例计算：**
- 套餐：2500 糖果，¥18
- 首充用户：2500 + 2500 = 5000
- 非首充用户：2500
- 非首充用户：2500
- 非首充非 VIP：2500

---

## C. App Store Connect 配置方案

### 1. 商品类型选择

**糖果充值商品类型：Consumable（消耗型内购）**
- 理由：糖果是虚拟货币，可重复购买，消耗后需再次购买
- 与会员订阅（Auto-Renewable Subscription）区分

### 2. Product ID 设计

**命名规则：** `bubbly.candy.<amount>`

**6 个糖果档位配置：**

| 套餐 | Product ID | 显示名称 | 价格档位 | 对应 package_id |
|------|-----------|---------|---------|----------------|
| 体验包 | bubbly.candy.100 | 100糖果 | ¥1 | candy_100 |
| 基础包 | bubbly.candy.600 | 600糖果 | ¥8 | candy_600 |
| 进阶包 | bubbly.candy.1200 | 1200糖果 | ¥18 | candy_1200 |
| 超值包 | bubbly.candy.3000 | 3000糖果 | ¥38 | candy_3000 |
| 豪华包 | bubbly.candy.6800 | 6800糖果 | ¥88 | candy_6800 |
| 尊享包 | bubbly.candy.12800 | 12800糖果 | ¥168 | candy_12800 |

### 3. Package ID 映射关系

**服务端 candy_packages 表配置：**
```sql
INSERT INTO candy_packages (package_id, candy_amount, price_cny, apple_product_id, tag, is_popular, sort) VALUES
('candy_100', 100, 1.00, 'bubbly.candy.100', '首充多赠100糖果', false, 1),
('candy_600', 600, 8.00, 'bubbly.candy.600', '首充多赠600糖果', false, 2),
('candy_1200', 1200, 18.00, 'bubbly.candy.1200', '首充多赠1200糖果', false, 3),
('candy_3000', 3000, 38.00, 'bubbly.candy.3000', '首充多赠3000糖果', true, 4),
('candy_6800', 6800, 88.00, 'bubbly.candy.6800', '首充多赠6800糖果', false, 5),
('candy_12800', 12800, 168.00, 'bubbly.candy.12800', '首充多赠12800糖果', false, 6);
```

**iOS IAPManager 更新：**
```swift
private static let candyProductIDs: Set<String> = [
    "bubbly.candy.100",
    "bubbly.candy.600",
    "bubbly.candy.1200",
    "bubbly.candy.3000",
    "bubbly.candy.6800",
    "bubbly.candy.12800"
]
```

### 4. App Store Connect 无法表达的逻辑

**必须由服务端控制：**
- ❌ 首充赠送（App Store 不支持"首次购买额外赠送"）
- ❌ 会员充值额外 20% 赠送（已移除，不再配置）
- ❌ 到账糖果数量（App Store 只能配置固定价格，不能配置赠送规则）

**App Store Connect 只配置：**
- ✅ Product ID
- ✅ 显示名称（如"100糖果"）
- ✅ 价格档位（¥1, ¥8, ¥18, ¥38, ¥88, ¥168）
- ✅ 描述文案（审核用）

### 5. 会员与糖果商品区分

**客户端区分方式：**
```swift
func isMembershipProduct(_ productId: String) -> Bool {
    return productId.contains("membership")
}

func isCandyProduct(_ productId: String) -> Bool {
    return productId.contains("candy")
}
```

**服务端区分方式：**
- 会员：调用 /vip/orders + /vip/orders/:id/verify
- 糖果：调用 /candy/orders + /candy/orders/:id/verify

### 6. 配置步骤清单

**在 App Store Connect 中：**
1. [ ] 进入 App → App 内购买项目
2. [ ] 创建 5 个消耗型商品（Consumable）
3. [ ] 逐一填写：
   - Product ID（如 bubbly.candy.100）
   - 参考名称（如"300糖果"）
   - 价格档位（选择对应人民币档位）
   - 本地化信息（至少中文）
   - 审核截图（充值页面截图）
4. [ ] 状态变为 Ready to Submit

**在 Products.storekit 中：**
```json
{
  "identifier": "bubbly.candy.100",
  "type": "Consumable",
  "displayName": "300糖果",
  "displayPrice": "3.00",
  "familyShareable": false
}
```

### 7. 风险点

**审核风险：**
- iOS App Store 版本必须使用 Apple IAP
- 不能在 UI 中显示支付宝/微信支付入口
- 不能引导用户到外部网页充值

**技术风险：**
- 首充标签必须由服务端控制，前端不能硬编码
- 会员充值额外 20% 加赠已移除，不能在套餐配置或客户端中写回

---

## D. 代码改造清单

### 1. 服务端改造（moodly_server）

#### 数据库迁移
**新建：** `prisma/migrations/xxx_add_candy_module.sql`
- 创建 candy_orders 表
- 修改 users 表（添加 candy_balance, is_first_candy_recharge）
- 修改 transactions 表（添加 label, balance_after）
- 创建 candy_packages 表或修改 moly_packages

**执行：** `npx prisma migrate dev --name add_candy_module`

#### 新增模块文件
```
src/modules/candy/
├── candy.routes.ts       # 路由定义（5个接口）
├── candy.service.ts      # 核心业务逻辑
├── candy.schema.ts       # Zod 验证 schema
└── candy.responses.ts    # 响应类型定义（可选）
```

#### 修改现有文件
**src/app.ts**
```typescript
// 注册糖果路由
app.register(candyRoutes, { prefix: '/v1/candy' });
```

**src/utils/errors.ts**
```typescript
// 新增错误码
PACKAGE_NOT_FOUND: () => ({ code: 1007, msg: '充值包不存在' }),
ORDER_EXPIRED: () => ({ code: 1003, msg: '订单已过期' }),
```

#### 复用能力
- ✅ IAPService.verifyReceipt() - 直接复用
- ✅ 分页工具 - 直接复用
- ✅ 事务处理模式 - 参考 membership.service.ts

---

### 2. iOS 改造（moodly-ios）

#### 新增文件
```
Bubbly/
├── Models/
│   └── Candy.swift              # CandyPackage, CandyOrder, CandyTransaction 模型
├── Services/
│   └── CandyService.swift       # 糖果接口封装
├── ViewModels/
│   ├── CandyRechargeViewModel.swift   # 充值页逻辑
│   └── CandyTransactionsViewModel.swift # 流水页逻辑
└── Views/
    └── Profile/
        ├── CandyRechargeView.swift      # 糖果充值页
        └── CandyTransactionsView.swift  # 糖果流水页
```

#### 修改现有文件

**Bubbly/Services/IAPManager.swift**
```swift
// 新增糖果商品 ID
private static let candyProductIDs: Set<String> = [
    "bubbly.candy.100",
    "bubbly.candy.600",
    "bubbly.candy.1200",
    "bubbly.candy.3000",
    "bubbly.candy.6800",
    "bubbly.candy.12800"
]

// 更新 allProductIDs
private static var allProductIDs: Set<String> {
    membershipProductIDs.union(molyProductIDs).union(candyProductIDs)
}

// 新增判断方法
func isCandyProduct(_ productId: String) -> Bool {
    return productId.contains("candy")
}
```

**Bubbly/Views/Profile/WalletView.swift**
```swift
// 添加糖果余额显示
// 添加"充值糖果"按钮，跳转到 CandyRechargeView
```

**Bubbly/Products.storekit**
```json
// 新增 6 个糖果商品配置
```

#### 核心逻辑伪代码

**CandyService.swift**
```swift
func fetchPackages() async throws -> CandyPackagesResponse
func createOrder(packageId: String) async throws -> CandyOrder
func verifyPurchase(orderId: String, transaction: Transaction) async throws
func fetchOrderStatus(orderId: String) async throws -> CandyOrderStatus
func fetchTransactions(type: String, page: Int) async throws -> [CandyTransaction]
```

**CandyRechargeViewModel.swift**
```swift
@Published var packages: [CandyPackage] = []
@Published var balance: Int = 0
@Published var isFirstRecharge: Bool = false

func loadPackages() async
func purchase(package: CandyPackage) async
func pollOrderStatus(orderId: String) async
```

#### 复用能力
- ✅ IAPManager.purchase() - 直接复用
- ✅ APIClient - 直接复用
- ✅ 会员页面的套餐卡片 UI - 可复用样式

---

### 3. 公共层抽象建议

#### 服务端
**抽象 IAP 验证流程：**
- 当前 IAPService 已经足够通用
- 建议：添加 `fulfillPurchase(type, orderId, transactionId)` 统一发货入口

**抽象订单管理：**
- 会员订单和糖果订单结构相似
- 可考虑抽象 BaseOrderService（可选，不强制）

#### iOS
**抽象购买流程：**
```swift
protocol PurchaseFlow {
    func createOrder() async throws -> String  // 返回 orderId
    func verifyPurchase(orderId: String, transaction: Transaction) async throws
    func pollStatus(orderId: String) async throws
}
```

**抽象套餐卡片 UI：**
- 会员和糖果的套餐卡片样式相似
- 可提取 PackageCardView 组件

---

## E. 待确认问题

### 1. 技术实现相关
- [ ] **当前 IAP 验证方式确认**：是使用 App Store Server API v2 的 JWS 还是旧版 receipt 验证？
  - 现状：代码中使用 JWS 解析，但未调用 Apple 服务端验证
  - 建议：生产环境需要调用 Apple API 验证签名真实性

- [ ] **VIP 月赠 1000 糖果是否已实现**？
  - 现状：未在代码中发现
  - 需确认：是否需要在本次实现

- [ ] **Moly 和 Candy 是否是同一种虚拟币**？
  - 现状：数据库中有 molyBalance，PRD 中提到"糖果"
  - 建议：统一命名，避免混淆

### 2. 业务逻辑相关
- [ ] **确认首充赠送不再与会员 20% 加赠叠加**？
  - PRD 未明确说明
  - 建议：叠加（首充 VIP 用户获得最大优惠）

- [ ] **订单过期时间设置**？
  - 建议：30 分钟
  - 需确认：过期订单是否自动取消

- [ ] **支付宝/微信支付是否保留**？
  - iOS App Store 版本不能显示
  - Android 版本或 Web 版本可以保留

### 3. App Store 审核相关
- [ ] **是否允许在 iOS 中展示"首充赠送"标签**？
  - 风险：Apple 可能认为这是诱导消费
  - 建议：标签文案改为"限时优惠"或"特惠"

- [ ] **糖果消费场景是否符合 Apple 审核规则**？
  - 需确认：糖果用于解锁功能是否属于"数字内容"
  - 如果是，必须使用 IAP

---

## F. 建议的下一步执行顺序

### 阶段 1：服务端基础能力（优先级：高）
1. [ ] 数据库迁移（创建 candy_orders, candy_packages 表）
2. [ ] 实现 CandyService 核心逻辑
3. [ ] 实现 6 个糖果接口
4. [ ] 配置糖果套餐数据（INSERT 5 条记录）
5. [ ] 测试接口（Postman/curl）

**预计时间：** 1-2 天

---

### 阶段 2：iOS 基础接入（优先级：高）
1. [ ] 创建 Candy 模型文件
2. [ ] 实现 CandyService 接口封装
3. [ ] 更新 IAPManager（添加糖果商品 ID）
4. [ ] 更新 Products.storekit（添加 6 个糖果商品）
5. [ ] 本地测试 StoreKit 购买流程

**预计时间：** 1 天

---

### 阶段 3：iOS UI 实现（优先级：中）
1. [ ] 实现 CandyRechargeView（充值页）
2. [ ] 实现 CandyRechargeViewModel（充值逻辑）
3. [ ] 修改 WalletView（添加糖果余额和充值入口）
4. [ ] 实现 CandyTransactionsView（流水页）
5. [ ] 实现订单状态轮询逻辑

**预计时间：** 2-3 天

---

### 阶段 4：App Store Connect 配置（优先级：中）
1. [ ] 创建 5 个消耗型商品
2. [ ] 填写本地化信息
3. [ ] 上传审核截图
4. [ ] 创建沙箱测试账号
5. [ ] 真机 Sandbox 测试

**预计时间：** 0.5 天

---

### 阶段 5：联调与测试（优先级：高）
1. [ ] 本地 StoreKit 测试（模拟器）
2. [ ] Sandbox 真机测试（沙箱账号）
3. [ ] 测试首充逻辑
4. [ ] 测试会员充值不再额外加赠 20%
5. [ ] 测试订单过期
6. [ ] 测试幂等性（重复回调）
7. [ ] 测试流水查询和分页

**预计时间：** 1-2 天

---

### 阶段 6：优化与上线（优先级：低）
1. [ ] 错误处理优化
2. [ ] 加载状态优化
3. [ ] UI 细节打磨
4. [ ] 提交 App Store 审核
5. [ ] 监控线上数据

**预计时间：** 1-2 天

---

## 总结

**核心要点：**
1. 服务端已有 wallet 模块，可快速扩展为糖果模块
2. iOS 已有 IAP 封装，只需添加糖果商品和 UI
3. 首充赠送必须由服务端控制，会员充值额外 20% 加赠已移除
4. App Store Connect 只配置基础价格，不能表达赠送逻辑
5. 优先实现核心充值流程，消费扣糖功能后续迭代

**预计总工期：** 6-10 天（1-2 个开发周期）

**关键风险：**
- Apple 审核对"首充赠送"标签的接受度
- IAP 验证的安全性（建议接入 Apple Server API 验证）
- 订单幂等性处理（防止重复发货）

---

**文档生成时间：** 2026-03-31
**审查范围：** moodly_server + moodly-ios
**输出格式：** 可执行的工程化方案


### 2. iOS 现状（moodly-ios）

#### 已有能力

**网络层：**
- ✅ `APIClient.shared`：统一的网络请求封装
- ✅ 支持 GET/POST，自动处理 token 认证
- ✅ `APIEnvelope<T>` 泛型响应包装

**IAP 封装：**
- ✅ `IAPManager.swift`：StoreKit 2 封装
  - 产品加载：`loadProducts()`
  - 购买流程：`purchase(product:)`
  - 交易监听：`listenForTransactionUpdates()`
  - 产品分类：membershipProductIDs, molyProductIDs

**会员模块：**
- ✅ `MembershipService.swift`：会员接口封装
  - fetchPlans, createOrder, fetchOrderStatus, restorePurchase
- ✅ `MembershipViewModel.swift`：会员页面逻辑
- ✅ `MembershipView.swift`：会员购买页面

**钱包模块：**
- ✅ `WalletService.swift`：钱包接口封装
  - fetchBalance, fetchPackages, topup, fetchTransactions
- ✅ `WalletViewModel.swift`：钱包页面逻辑
- ✅ `WalletView.swift`：钱包页面 UI

**数据模型：**
- ✅ `MolyPackage`：虚拟币套餐模型（已包含 bonusCandy, totalCandy, tag, isPopular）
- ✅ `Transaction`：流水模型（type: topup/consume）
- ✅ `MembershipOrder`：会员订单模型（可参考）

**StoreKit 配置：**
- ✅ `Products.storekit`：本地测试配置
  - 3 个订阅商品：bubbly.membership.*
  - 4 个消耗品：bubbly.moly.600/2000/3500/12000

#### 可复用能力

1. **IAP 购买流程**：IAPManager 的 purchase 方法可直接复用
2. **网络请求封装**：APIClient 可直接使用
3. **会员订单流程**：创建订单 → IAP 购买 → 轮询状态的模式可参考
4. **UI 组件**：会员页面的套餐卡片、标签展示可复用

#### 缺失能力

1. ❌ **糖果充值页面**：没有独立的糖果充值 UI（CandyRechargeView）
2. ❌ **糖果钱包页面**：WalletView 需要扩展显示糖果余额和充值入口
3. ❌ **糖果流水页面**：需要独立的糖果流水页面（CandyTransactionsView）
4. ❌ **糖果订单模型**：没有 CandyOrder 模型
5. ❌ **糖果 API 封装**：需要新增 CandyService.swift
6. ❌ **首充标签逻辑**：UI 需要根据 is_first_recharge 动态显示标签
7. ✅ **VIP 加赠提示**：已移除，UI 不再显示会员充值额外 20% 加赠
8. ❌ **订单轮询逻辑**：需要实现糖果订单状态轮询

---

### 3. App Store Connect 配置现状

**已配置商品（根据 APP_STORE_CONNECT_SETUP.md）：**
- ✅ 3 个订阅商品：bubbly.membership.monthly.first, weekly, monthly
- ✅ 4 个消耗品：bubbly.moly.600, 2000, 3500, 12000

**命名规范：**
- 订阅：`bubbly.membership.<duration>.<variant>`
- 消耗品：`bubbly.moly.<amount>`

**问题：**
- ❌ PRD 中的糖果套餐是 5 个（300/600/2500/3500/12000），但 StoreKit 只配置了 4 个
- ❌ 缺少 candy_100 对应的 Apple Product ID

---
