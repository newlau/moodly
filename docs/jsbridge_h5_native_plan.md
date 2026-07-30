# Moodly H5 JSBridge 双端方案

Status: current + plan
Owner topic: cross-platform H5/native bridge
Updated: 2026-07-30

## 背景

运营活动、启动策略迁移页、协议页和后续内嵌 H5 需要复用客户端原生能力，包括 App 内打开网页、跳转原生页、打开系统相册、关闭容器和 H5 行为埋点。双端统一暴露 `window.MoodlyJSBridge`，H5 不直接依赖 iOS `window.webkit` 或 Android `JavascriptInterface`。

## 调用约定

H5 监听桥就绪：

```js
window.addEventListener('MoodlyJSBridgeReady', function () {
  window.MoodlyJSBridge.call('getEnv', {}, function (res) {
    console.log(res)
  })
})
```

统一调用格式：

```js
window.MoodlyJSBridge.call(method, params, callback)
```

统一回包：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

`code = 0` 表示成功；非 0 表示失败或用户取消。H5 必须按 `code` 判断结果，不要只依赖 callback 是否触发。

## P0 方法

| method | params | data | 说明 |
| --- | --- | --- | --- |
| `getEnv` | `{}` | `platform`, `bridgeVersion`, `appVersion`, `buildNumber`, `page`, `source`, `activityId`, `title`；可信 H5 域名下额外返回 `token`, `accessToken` | 获取容器环境 |
| `setTitle` | `{ "title": "活动详情" }` | `{}` | 更新原生顶部标题 |
| `close` | `{}` | `{}` | 关闭当前 WebView 容器 |
| `openWebView` | `{ "url": "https://...", "title": "详情", "source": "h5_bridge", "activityId": "..." }` | `{}` | App 内打开新的 H5 容器，仅允许 `http/https` |
| `openExternalUrl` | `{ "url": "https://..." }` | `{}` | 调系统能力打开外链；Android 禁止 `javascript/file/content` |
| `openNativeRoute` | `{ "route": "subscription", "initialTier": "vip", "source": "h5_bridge" }` | `{}` | 跳转原生页，未知 route 返回 `unsupported_route` |
| `pickImage` | `{ "count": 1 }` | `url`, `mediaUrl`, `fileName`, `mimeType`, `size` | 打开系统相册，由客户端上传图片后把远端 URL 回给 H5 |
| `downloadImage`（兼容 `saveImage`） | `{ "url": "https://...", "fileName": "活动海报.png" }` | `saved: true`；Android 额外返回 `uri` | 下载 `http/https` 图片并保存到系统相册；首次使用会请求相册写入权限 |
| `trackEvent` | `{ "actionName": "join_click", "buttonName": "立即参加", "result": "click" }` | `{}` | 上报 `activity_webview_action_click` |

当前原生 route 白名单：

| route | iOS | Android |
| --- | --- | --- |
| `subscription`, `membership` | `MembershipView` | `Screen.Subscription` / `Screen.SubscriptionTier` |
| `candy_wallet`, `wallet` | `WalletView` | `Screen.CandyWallet` |
| `task_center` | `TaskCenterView` | `Screen.TaskCenter` |
| `check_in` | `CheckInView` | `Screen.CheckIn` |
| `home` | needs follow-up | `Screen.Home` |

## 已落地

- iOS: `EmbeddedWebView` 注入 `MoodlyJSBridge`，覆盖协议页、活动页以及复用该容器的 H5；支持环境、标题、关闭、内嵌网页、原生 route、外链、相册选择后客户端上传、图片保存到相册、H5 行为埋点。
- Android: `LegalWebViewScreen` 注入 `MoodlyJSBridge`；`MoodlyNavHost` 已接 `openWebView` 和原生 route 白名单；支持环境、标题、关闭、内嵌网页、原生 route、外链、相册选择后客户端上传、图片保存到相册、H5 行为埋点。
- 双端 WebView 打开 `taxiangapp.com` 及其子域 H5 时，如果链接缺少 `token/access_token`，客户端会自动追加当前登录 `token`；外部域名不注入登录态。

## 待确认

- 第三方 App scheme 白名单，例如小红书、抖音、微信。当前 Android 只禁止高危 scheme；iOS `openExternalUrl` 第一版仅放行 `http/https`。
- 启动策略 `migration_web` 的 Android 半屏 WebView 仍是内联 WebView，后续应抽成同一桥接容器，避免双轨维护。
- `home` 等跨 Tab 原生跳转在 iOS 需要接根导航状态后再开放。

## H5 示例

```js
function openVip() {
  window.MoodlyJSBridge.call(
    'openNativeRoute',
    { route: 'subscription', initialTier: 'vip', source: 'activity_h5' },
    function (res) {
      if (res.code !== 0) console.warn(res.message)
    }
  )
}

function chooseImage() {
  window.MoodlyJSBridge.call('pickImage', { count: 1 }, function (res) {
    if (res.code === 1001) return
    if (res.code !== 0) throw new Error(res.message)
    console.log(res.data)
  })
}

function downloadPoster(url) {
  window.MoodlyJSBridge.call('downloadImage', { url, fileName: '活动海报.png' }, function (res) {
    if (res.code !== 0) throw new Error(res.message)
    console.log('图片已保存', res.data)
  })
}
```
