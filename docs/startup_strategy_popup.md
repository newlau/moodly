# 启动策略弹窗机制

## 1. 功能背景

为双端 App 预埋一套“冷启动策略能力”，在 App 每次冷启动时向服务端查询启动策略，并由客户端根据策略决定是否展示弹窗或半浮窗。

本次目标不是写死一个更新页面，而是把能力链路完整搭好，后续由服务端配置决定是否开启：

- 普通更新提示
- 强制更新
- 下架/迁移网页半浮窗引导
- 后续更多启动治理策略扩展

当前阶段默认关闭，确保不影响线上现有隐私协议、登录、首页、启动广告等流程。

## 2. 支持的状态说明

- `close`：关闭状态，不展示任何弹窗，直接放行启动链路。
- `optional_update`：普通更新提示，可关闭，不阻断主流程。
- `force_update`：强制更新，不可关闭，阻断主流程，需跳转更新地址。
- `migration_web`：通过半浮窗 / 半屏弹层承载服务端下发 `webUrl`，用于下架迁移、换包引导等场景。

客户端和服务端都保留了扩展字段，后续可以增加更多类型而不重做整套机制。

## 3. 服务端接口字段说明

服务端新增公共接口：

- `GET /v1/app/startup-strategy`

请求建议携带：

- `platform`：`ios` / `android`
- `app_version`：当前客户端版本号
- Header `x-platform`：`ios` / `android`

返回结构使用统一 envelope：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "enabled": false,
    "type": "close",
    "title": "",
    "content": "",
    "minSupportedVersion": "",
    "latestVersion": "",
    "webUrl": "",
    "jumpUrl": "",
    "confirmText": "",
    "cancelText": "",
    "canClose": true,
    "force": false,
    "platform": "both",
    "remark": "",
    "ext": {}
  }
}
```

字段含义：

- `enabled`：总开关，`false` 时强制按关闭态处理。
- `type`：策略类型，当前支持 `close / optional_update / force_update / migration_web`。
- `title` / `content`：弹窗标题和内容。
- `minSupportedVersion`：最低支持版本，小于该版本时触发强制更新。
- `latestVersion`：最新版本，小于该版本时可触发普通更新提示。
- `webUrl`：网页半浮窗内容地址。
- `jumpUrl`：确认按钮外跳地址，例如应用市场、下载页、新包地址。
- `confirmText` / `cancelText`：按钮文案。
- `canClose`：是否允许关闭。
- `force`：是否强制阻断，服务端可冗余声明，客户端也会结合 `type` 兜底。
- `platform`：`ios / android / both`，服务端按平台过滤。
- `remark`：备注字段，便于后续运营或排障。
- `ext`：扩展字段，保留给后续灰度、样式、实验参数等。

### 3.1 iOS 功能入口开关

iOS 客户端会额外从 `ext` 中读取功能入口开关，用于服务端控制审核期和线上期的可见入口。当前已接入：

```json
{
  "ext": {
    "ios_feature_flags": {
      "code_redemption_entry_enabled": false
    }
  }
}
```

- `code_redemption_entry_enabled=false`：隐藏发现页兑换码、角色分享兑换、个人页邀请码、签到页邀请奖励入口。
- `code_redemption_entry_enabled=true`：打开上述入口。
- Release 包本地默认值为 `false`；如果启动策略接口失败，保持本地安全默认或上一次成功下发的值。
- 当前主服务端在 `src/modules/startup-strategy/startup-strategy.service.ts` 用 `CODE_REDEMPTION_ENTRY_ENABLED` 常量组装该开关，即使启动策略是 `close` 也会保留该扩展字段。审核期保持 `false`；过审后手动改为 `true` 并重新发布服务端。

### 3.2 登录页优先级配置

登录页优先级复用同一接口的 `data.login_config.primary_login_method` 字段，详细配置、fallback 和审核注意事项见 [login_priority_config.md](./login_priority_config.md)。

### 3.4 “我的”页活动入口配置

状态：current，双端已接入 `GET /v1/app/activity-configs/active`。

活动入口与启动策略分开查询，客户端冷启动时按平台拉取：

- `scene=profile_entry`
- `platform=ios` 或 `android`
- `app_version=当前客户端版本`
- Android 额外透传 `app_channel`

展示规则：

- 只取服务端返回列表的第一条有效配置。
- 青少年模式开启时隐藏。
- 入口位置在“我的”页会员卡下方、设置菜单上方，作为独立横版活动卡展示，不再混入菜单列表。
- 当配置包含 `imageUrl` 时，客户端把该图片作为完整 banner 直接展示，整张图可点击；仅在没有图片或图片加载失败时回退到标题、副标题和按钮样式。
- 点击活动卡优先用 `jumpUrl`，为空时用 `webUrl`。
- 当前活动配置承载的是运营后台生成的 H5 页面，双端使用 App 内 WebView 打开。

## 4. 默认关闭逻辑说明

当前默认关闭由三层共同保证：

1. 服务端环境变量默认 `STARTUP_STRATEGY_ENABLED=false`，`STARTUP_STRATEGY_TYPE=close`。
2. 服务端即使配置缺失，也会返回一份完整的安全关闭结构，而不是抛错。
3. 客户端对接口异常、字段为空、类型未知都按“跳过启动策略”处理。

因此在当前阶段：

- 服务端默认不打开任何策略
- 客户端默认不会展示任何新弹窗
- 冷启动链路与现网行为保持一致

## 5. 客户端处理流程

### Android

挂载位置：

- `SplashScreen` 在“隐私同意完成 + 登录态解析完成 + 真正路由跳转前”执行启动策略检查。

处理流程：

1. 冷启动进入 `SplashScreen`
2. 检查隐私协议
3. 解析登录态
4. 请求 `/v1/app/startup-strategy`
5. 根据返回结果评估动作
6. `close` 直接继续跳转首页/登录
7. `optional_update` 弹可关闭更新框
8. `force_update` 弹不可关闭更新框并阻断路由
9. `migration_web` 展示 `ModalBottomSheet + WebView` 半浮窗

同一次冷启动只会处理一次，避免重复弹出和路由抖动。

### iOS

挂载位置：

- `BubblyApp` 注入 `StartupStrategyCoordinator`
- `ContentView` 根层在首次 `onAppear` 时触发检查，并用全局 overlay / sheet 承载策略展示

处理流程：

1. App 启动进入 `ContentView`
2. 根层协调器只执行一次启动策略检查
3. `optional_update / force_update` 通过全局 overlay 展示
4. `migration_web` 通过半屏 sheet + `EmbeddedWebView` 展示
5. `force_update` 不允许关闭

这样可以保证不把策略逻辑硬编码进首页或登录页，也尽量减少对现有页面结构的侵入。

## 6. 强制更新规则

统一版本比较逻辑支持：

- `1.2.3`
- `1.2.10`
- `2.0.0`

规则如下：

- `force_update`：当前版本 `< minSupportedVersion` 时触发
- `optional_update`：当前版本 `< latestVersion` 时触发

比较逻辑会将版本号按 `.` 分段后逐段比较，缺失段按 `0` 处理，例如 `2.0` 与 `2.0.0` 视为相等。

## 7. migration_web 半浮窗说明

`migration_web` 当前默认不开启，但机制已经可用：

- Android：使用 `ModalBottomSheet + WebView`
- iOS：使用 sheet + `EmbeddedWebView`

适用场景：

- 应用下架后的迁移引导
- 新包下载指引
- 审核包与正式包切换引导
- 运营活动类启动页网页内容

建议：

- `webUrl` 用于承载可运营化的网页内容
- `jumpUrl` 用于承载最终跳转地址
- 若需要强阻断迁移，可将 `canClose=false`

## 8. 联调方式

### 服务端

服务端通过环境变量控制策略，例如：

- `STARTUP_STRATEGY_ENABLED=true`
- `STARTUP_STRATEGY_TYPE=optional_update`
- `STARTUP_STRATEGY_TITLE=发现新版本`
- `STARTUP_STRATEGY_CONTENT=建议升级到最新版本以获得更稳定体验`
- `STARTUP_STRATEGY_LATEST_VERSION=1.0.1`
- `STARTUP_STRATEGY_JUMP_URL=https://apps.apple.com/...`
- `STARTUP_STRATEGY_PLATFORM=ios`

或：

- `STARTUP_STRATEGY_ENABLED=true`
- `STARTUP_STRATEGY_TYPE=force_update`
- `STARTUP_STRATEGY_MIN_SUPPORTED_VERSION=1.0.1`
- `STARTUP_STRATEGY_JUMP_URL=https://play.google.com/store/apps/details?...`
- `STARTUP_STRATEGY_PLATFORM=android`

或：

- `STARTUP_STRATEGY_ENABLED=true`
- `STARTUP_STRATEGY_TYPE=migration_web`
- `STARTUP_STRATEGY_TITLE=服务迁移通知`
- `STARTUP_STRATEGY_WEB_URL=https://example.com/migration`
- `STARTUP_STRATEGY_JUMP_URL=https://example.com/new-app`
- `STARTUP_STRATEGY_CAN_CLOSE=true`
- `STARTUP_STRATEGY_PLATFORM=both`

### 客户端

- Android：修改 `versionName` 或用当前版本直接联调
- iOS：修改 `MARKETING_VERSION` / `CFBundleShortVersionString` 或直接使用当前版本
- 请求会携带平台和版本号，服务端可按平台下发不同策略

## 9. 测试用例

建议至少覆盖以下场景：

- 服务端未配置任何变量时，接口返回 `close`
- 服务端字段为空字符串时，客户端不崩溃且安全跳过
- `platform=ios` 时 Android 端应跳过
- `platform=android` 时 iOS 端应跳过
- `optional_update` 且当前版本低于 `latestVersion` 时展示可关闭弹窗
- `optional_update` 且当前版本高于等于 `latestVersion` 时不展示
- `force_update` 且当前版本低于 `minSupportedVersion` 时阻断主流程
- `force_update` 且更新链接为空时，不崩溃但继续阻断并提示无法打开链接
- `migration_web` 时展示半浮窗并加载网页
- 同一次冷启动过程中，策略只处理一次
- 接口失败、超时、字段异常时，客户端直接跳过

## 10. 后续扩展建议

- 将当前环境变量配置升级为数据库表 + 后台运营配置页
- 增加灰度字段，例如渠道、国家、包版本范围、用户分组
- 增加生效时间窗口，例如开始时间、结束时间
- 增加素材样式字段，例如插图、主题色、弹窗尺寸
- 增加频控策略，例如每日仅弹一次、某版本仅弹一次
- 增加埋点上报，统计曝光、关闭、确认跳转、网页停留时长
- 增加签名或配置版本号，方便客户端缓存与回滚
