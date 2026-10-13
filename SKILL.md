---
name: zcron
description: ZCode 定时自动化(automation/cron)的批量创建与管理。当用户要一次创建多个定时任务、CronCreate 被单会话限制拒绝、或需要列出/启停/删除/预览已有自动化时使用。直写本地自动化库(端到端验证过),写前自动备份。
---

# zcron — ZCode 自动化直写管理

## 原理(为什么能用)

ZCode 的 CronCreate 在单个会话里拒建多条自动化,但 automations 实际持久化在本地
`~/.zcode/v2/tasks-index.sqlite` 的 `automations` 表(WAL 模式),宿主每次调度 tick
直接查库、**无内存缓存**——外部直写即刻生效。

已端到端验证(2026-10-12):直写插入 → CronList 立即可见 → 宿主按 next_run_at 准时调度
→ `automation_runs.outcome=succeeded`。

## 快速路径

工具与 SKILL.md 同目录,调用方式(优先用绝对路径):

```bash
python3 <本技能目录>/zcron <子命令>
```

前提检查:`zcron doctor`——确认库存在、journal=wal、表结构未被 ZCode 改版。

### 批量创建(核心场景,绕过单会话限制)

1. 在工作区写 N 个 `.md` 文件,每个文件 = 一条自动化:

```markdown
---
title: 每周三 9 点同步数据管线
cron: 0 9 * * 3
max-runs: 1          # 可选,省略=无限循环
enabled: false       # 可选,默认 true
model: providerId/modelId:max   # 可选,省略=取库内现有自动化的众数模型
---
这里写 prompt 正文(就是自动化触发后发给 agent 的完整指令)。
```

2. 一次导入:`python3 <技能目录>/zcron add --from-dir <目录> --yes`
3. 用 CronList 工具验证(列表应立即出现新条目)。

### 单条创建

```bash
python3 <技能目录>/zcron add --title "标题" --cron "30 9 * * *" --prompt-file prompt.md
```

cron 必须恰好 5 字段(分 时 日 月 周),本地时区。下次触发时间由工具算好写入
`next_run_at`(epoch 毫秒),宿主靠它判到期。

### 其他命令

- `list [--disabled]` / `show <id前缀>` — 查看
- `enable|disable <id前缀>` — 启停(disable 保留配置;enable 会重算下次触发时间,并复活已跑完的任务——有限次任务计数清零重新起算)
- `rm <id前缀> --yes` — 删除(连 automation_runs 历史一起清)
- `next "0 9 * * 1" --count 3` — 只预览触发时间,不写库

## 安全设计(不要绕过)

- **每次写操作自动备份**整库到 `~/.zcron/backups/`(保留 10 份)——出问题可回滚。
- 结构闸门:表结构不符合预期(缺 automation_id 列)时拒绝写入,ZCode 改版不会写坏库。
- 写入带 `busy_timeout=10s`,与宿主并发安全;但避免恰好在某条自动化触发的瞬间批量写入。
- `rm` 必须显式 `--yes`;批量导入不带 `--yes` 会先逐条预览等确认。

## 注意事项

- 环境变量:`ZCODE_DB` 换库路径、`ZCODE_WORKSPACE` 换 workspace(默认
  `~/.zcode/workspace/default`,自动化绑定该目录)。
- 写入后验证:**CronList 看得到 → 读取层通;到期后 run_count 增长 → 调度层通**。
  可用一条 `--max-runs 1` 的短周期任务做一次性端到端验证,完事 `rm` 掉。
- prompt 里写清楚:硬规则(数字来自真实输出、查不到写查不到)、结束动作、
  以及"失败时不要连环重试"——自动化无人监督,防呆写在 prompt 里。
- maxRuns 语义:`--max-runs 1` = 一次性任务;省略 = 无限循环。
