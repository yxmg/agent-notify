# agent-notify

Claude Code / Codex 任务完成通知 → 企业微信群机器人。

任务完成后推送一条卡片，包含：结论、项目、本次任务、耗时、机型。

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/guanmingzhao/agent-notify/main/install.sh)
```

按提示输入企业微信 Webhook URL，完成。

也可直接传参：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/guanmingzhao/agent-notify/main/install.sh) "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
```

## 效果

```
## Claude Code · 任务完成 ✅

🎯 结论
上图就是完整的接口流程梳理...

---
📦 项目：shopline-dash-subscription
📋 任务：独立商品开通的流程和调用的接口是哪些...
⏰ 耗时：5分13秒（17:05:51-17:11:04）
💻 claude-sonnet-4-6 · SLdeMacBook-Pro
```

## 配置

安装后配置文件位于 `~/.agent-notify/config.json`：

```json
{
  "webhook": "https://qyapi.weixin.qq.com/...",
  "delay": 5,
  "rate_limit": 10
}
```

- `delay`：任务完成后延迟多少秒发送（防打扰：延迟内有新操作则取消）
- `rate_limit`：同类事件最短间隔秒数

## 卸载

```bash
rm -rf ~/.agent-notify
```

然后从 `~/.claude/settings.json` 和 `~/.codex/hooks.json` 中删除 agent-notify 相关 hook 条目。

## 支持

- Claude Code（Stop / Notification 事件）
- Codex（Stop / Notification 事件）
- macOS / Linux
- 依赖：`bash` `jq` `python3` `curl`
