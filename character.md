# 人物接口文档（`chat/v1/characters`）

说明：
- 公共前缀：`chat/v1/characters`
- 认证：`Authorization: Bearer <token>`
- 下方参数与响应全部用 JSON 表达，字段注释以 `_comment` 说明。

---

## 1) 获取角色列表

- 功能：分页获取角色列表，支持分类与角色类型筛选，并返回是否聊过。
- 接口路径：`GET chat/v1/characters`

### 请求参数（Query）

```json
{
  "category": "custom",
  "_comment_category": "string, 可选, 分类筛选",
  "type": "all",
  "_comment_type": "string, 可选, all/system/user, 默认 all",
  "page": 1,
  "_comment_page": "number, 可选, 页码, 默认 1",
  "page_size": 20,
  "_comment_page_size": "number, 可选, 每页数量 1~100, 默认 20"
}
```

### 响应数据

```json
{
  "total": 12,
  "items": [
    {
      "character_uid": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
      "name": "晚晚",
      "gender": "female",
      "avatar_url": "https://example.com/avatar.png",
      "description": "温柔治愈系角色",
      "tags": ["温柔", "恋人"],
      "category": "custom",
      "is_system": 0,
      "is_chatted": true
    }
  ]
}
```

---

## 2) 获取聊过天的角色列表

- 功能：分页获取当前用户聊过天的角色（游客固定返回空列表）。
- 接口路径：`GET chat/v1/characters/chatted`

### 请求参数（Query）

```json
{
  "page": 1,
  "_comment_page": "number, 可选, 页码, 默认 1",
  "page_size": 20,
  "_comment_page_size": "number, 可选, 每页数量 1~100, 默认 20"
}
```

### 响应数据

```json
{
  "total": 5,
  "items": [
    {
      "character_uid": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
      "name": "晚晚",
      "gender": "female",
      "avatar_url": "https://example.com/avatar.png",
      "description": "温柔治愈系角色",
      "tags": ["温柔", "恋人"],
      "category": "custom",
      "is_system": 0
    }
  ]
}
```

---

## 3) 获取自定义角色配置

- 功能：返回创建自定义角色页面所需的默认配置。
- 接口路径：`GET chat/v1/characters/custom/config`

### 请求参数

```json
{}
```

### 响应数据

```json
{
  "default_avatars": [
    {
      "id": "role_1",
      "url": "https://example.com/avatar/role_1.png"
    }
  ],
  "genders": ["male", "female"],
  "speech_styles": ["像恋人一样", "像朋友一样", "少年感", "成熟温柔"],
  "defaults": {
    "chat_background": "#FFF7F2"
  }
}
```

---

## 4) 审核自定义角色设定

- 功能：在创建流程进入音色选择前，仅审核用户填写的角色设定文本，不创建角色、不创建聊天会话。
- 接口路径：`POST chat/v1/characters/custom/review`
- 审核范围：`name`、`description`、`speech_style`、`relationship_stance`、`relationship_state_summary`、`reply_mode`。
- 服务端行为：复用自定义角色创建链路的本地规则、服务端敏感词、模型文本审核和失败冷却；审核通过返回 `{ "ok": true }`，审核失败返回创建链路同款错误提示。服务端日志记录 `policy_version`、`text_hash`、命中分类、`rule_id` 和 `matched_pattern`，不回显完整角色设定原文；客户端不展示具体敏感词，避免引导规避。
- 客户端行为：进入接口前只做必填和长度等基础校验；内容风控结果以服务端审核为准，客户端用 toast 展示审核中/失败提示。

### 请求参数（Body）

字段与 `POST chat/v1/characters/custom` 创建接口保持一致。客户端可只传进入下一步所需的文本字段，`avatar_url` 可为空；本地新选头像仍在保存上传后由创建接口兜底审核。

```json
{
  "gender": "female",
  "name": "晚晚",
  "description": "温柔治愈系角色",
  "speech_style": "说话自然一点",
  "relationship_stance": "刚开始熟起来",
  "relationship_state_summary": "朋友关系",
  "reply_mode": "action",
  "timezone": "Asia/Shanghai"
}
```

### 响应数据

```json
{
  "ok": true
}
```

---

## 5) 创建自定义角色

- 功能：创建用户自定义角色，并自动创建聊天会话和聊天设置。
- 接口路径：`POST chat/v1/characters/custom`

### 请求参数（Body）

```json
{
  "gender": "female",
  "_comment_gender": "string, 必填, 性别枚举, 如 male/female",
  "avatar_url": "https://example.com/avatar.png",
  "_comment_avatar_url": "string(url), 必填, 头像地址",
  "name": "晚晚",
  "_comment_name": "string, 必填, 1~20 字",
  "personality": "温柔",
  "_comment_personality": "string, 必填, 人设短句，建议短文本输入",
  "speech_style": "像恋人一样",
  "_comment_speech_style": "string, 必填, 说话风格短句；客户端可结合 config.speech_styles 做快捷填充",
  "relationship": "恋人",
  "_comment_relationship": "string, 必填, 对用户的感情/关系描述，建议短文本输入",
  "user_title": "你",
  "_comment_user_title": "string, 必填；当前客户端创建页不再单独暴露该输入项，统一传固定兜底值",
  "chat_background": "#FFF7F2",
  "_comment_chat_background": "string, 必填, 长度 1~255"
}
```

### 响应数据

```json
{
  "character_uid": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "name": "晚晚",
  "gender": "female",
  "avatar_url": "https://example.com/avatar.png",
  "description": "恋人系温柔角色，擅长像恋人一样风格交流，称呼你为宝宝。",
  "tags": ["温柔", "像恋人一样", "恋人"],
  "category": "custom",
  "age": 24,
  "height": "168cm",
  "body_type": "匀称",
  "job": "自由职业者",
  "background": "她/他与用户是恋人关系，性格温柔，平时说话风格偏像恋人一样。",
  "is_official": false,
  "is_system": 0,
  "creator_id": "user_uid_123",
  "timezone": "Asia/Shanghai",
  "chat_id": "chat_user_uid_123_8f5b4f40",
  "chat_background": "#FFF7F2"
}
```

---

## 6) 获取角色详情

- 功能：按角色 ID 获取角色详情。
- 接口路径：`GET chat/v1/characters/:id`

### 请求参数（Path）

```json
{
  "id": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "_comment_id": "string(uuid), 必填, 角色 character_uid"
}
```

### 响应数据

```json
{
  "character_uid": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "name": "晚晚",
  "gender": "female",
  "avatar_url": "https://example.com/avatar.png",
  "description": "温柔治愈系角色",
  "tags": ["温柔", "恋人"],
  "category": "custom",
  "age": 24,
  "height": "168cm",
  "body_type": "匀称",
  "job": "自由职业者",
  "background": "角色背景描述",
  "is_official": false,
  "is_system": 0,
  "creator_id": "user_uid_123",
  "timezone": "Asia/Shanghai"
}
```

---

## 7) 获取角色实时状态

- 功能：获取角色当前实时状态。
- 接口路径：`GET chat/v1/characters/:id/live-status`

### 请求参数（Path）

```json
{
  "id": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "_comment_id": "string(uuid), 必填, 角色 character_uid"
}
```

### 响应数据

```json
{
  "character_uid": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "activity": "resting",
  "activity_text": "休息中",
  "activity_icon": "💤",
  "location": "未知",
  "mood": "neutral",
  "availability": "busy",
  "reply_delay_seconds": 300,
  "started_at": null,
  "until": null,
  "updated_at": "2026-03-23T10:05:00.000Z"
}
```

---

## 8) 获取角色周计划（挂起）

- 功能：获取角色周计划。
- 接口路径：`GET chat/v1/characters/:id/schedule`
- 当前状态：`501 Not Implemented`（缺少 `character_schedule_slots` 表）。

### 请求参数（Path）

```json
{
  "id": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "_comment_id": "string(uuid), 必填, 角色 character_uid"
}
```

### 响应数据（当前）

```json
{
  "statusCode": 501,
  "error": "Not Implemented",
  "message": "接口已挂起：当前库缺少文档要求的表（character_schedule_slots / character_life_events），请先补表后启用"
}
```

---

## 9) 获取角色当日时间线（挂起）

- 功能：获取角色某日时间线。
- 接口路径：`GET chat/v1/characters/:id/timeline`
- 当前状态：`501 Not Implemented`（缺少 `character_schedule_slots` / `character_life_events` 表）。

### 请求参数（Path + Query）

```json
{
  "id": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "_comment_id": "string(uuid), 必填, 角色 character_uid",
  "date": "2026-03-23",
  "_comment_date": "string, 可选, 日期格式 YYYY-MM-DD"
}
```

### 响应数据（当前）

```json
{
  "statusCode": 501,
  "error": "Not Implemented",
  "message": "接口已挂起：当前库缺少文档要求的表（character_schedule_slots / character_life_events），请先补表后启用"
}
```

---

## 10) 获取角色生活事件列表（挂起）

- 功能：获取角色生活事件列表。
- 接口路径：`GET chat/v1/characters/:id/life-events`
- 当前状态：`501 Not Implemented`（缺少 `character_life_events` 表）。

### 请求参数（Path + Query）

```json
{
  "id": "8f5b4f40-7dd5-4f4c-9d1e-9c9ff8b209a7",
  "_comment_id": "string(uuid), 必填, 角色 character_uid",
  "limit": 10,
  "_comment_limit": "number, 可选, 1~50, 默认 10"
}
```

### 响应数据（当前）

```json
{
  "statusCode": 501,
  "error": "Not Implemented",
  "message": "接口已挂起：当前库缺少文档要求的表（character_schedule_slots / character_life_events），请先补表后启用"
}
```
