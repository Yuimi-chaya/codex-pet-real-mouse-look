---
name: codex-pet-real-mouse-look
description: "Safely inspect, dry-run, install, verify, or roll back the Windows Codex App v2 pet real-mouse-look MSIX patch. CRITICAL: when hosted inside Codex App, output the mandatory stop card before every script; never guess a backup, rollback command, version bypass, or cancellation action."
---

# Codex Pet Real Mouse Look

## FIRST: Match A Mandatory Response Card

Read these cards before answering. When a card matches, follow it literally. Do not replace it with a shorter summary. Do not add commands that the card forbids.

### CARD A - Agent Is Inside Codex App Or Host Is Unknown

This card applies before **every script**, including environment checks and DryRun. A generic "I authorize it" or "skip the warning" does not bypass it.

Reply with all of the following, then STOP and wait for a new user reply:

> 当前 Agent 运行在将被替换的 Codex App 内，我现在不会运行任何脚本。安装会关闭并替换承载本对话的 App，因此对话、终端和工具连接会中断，我也可能无法在本对话中报告最终结果；MSIX 重装和回滚本身也有风险。
>
> 请依次考虑：
> 1. **推荐：**改用不依赖 Codex App 的独立 IDE/终端 Agent；你同意后，我可以依据官方说明协助部署，并教你把本仓库交给它。
> 2. 我给出完整 PowerShell 命令，由你保存说明后手动运行。
> 3. 仅作为最后选择，让 Codex 自运行。选择此项必须再次逐项确认：自动关闭 App、当前对话中断、替换应用包、回滚有风险。
>
> 请回复选择 1、2 或 3。在你作出新选择前，我不会执行环境检查、DryRun 或安装。

If the user chooses option 3 but does not explicitly acknowledge all four risks, repeat the missing risks and STOP again.

### CARD B - App Version Is Not Audited

Reply and STOP:

> 当前 App 版本不在已审计兼容表中，因此不能安装。版本绕过机制只供维护者在审计 constructor/sender 目标并更新测试后使用；用户愿意承担风险也不能代替兼容性审计。我不会提供绕过参数或命令。

Never reveal or recommend a bypass command.

### CARD C - Same-Run Backup Count Is Zero Or Greater Than One

If zero backups exist, reply and STOP:

> 本次任务目录没有生成原包备份，因此我不会提供或猜测回滚命令。请保留错误窗口和日志，停止操作并交由维护者检查。

If more than one backup exists, reply and STOP:

> 本次任务目录中的原包备份不唯一，因此我不会按时间、文件名、大小、签名或哈希挑选，也不会自行生成回滚命令。请保留全部文件并停止操作，由维护者确认来源。

Never output `Add-AppxPackage`, `Remove-AppxPackage`, or any invented rollback command in Card C.

### CARD D - Delayed Self-Run Was Successfully Scheduled

The final paragraph must be exactly this text with the printed path substituted once:

> 60 秒后 Codex App 会自动关闭并开始打补丁，当前对话会中断。期间不要关闭弹出的任何命令行窗口。若需取消，请在 `<脚本打印的完整取消路径>` 创建一个空文件，不要删除该路径；这个路径只是取消标记，不是命令、备份或恢复路径。若最后阶段失败，请保持失败窗口打开，并运行窗口中打印的完整回滚命令；不要自行挑选其他备份。

Do not say the task is cancelled merely because a cancellation path exists. Cancellation happens only after the user creates that file.

## Non-Negotiable Rules

1. Classify the host before any script. Unknown means Codex-hosted and requires Card A.
2. Prefer an independent agent. Manual PowerShell is second. Codex self-run is last.
3. Do not change global proxy, Git, npm, pip, or package-manager configuration while helping deploy another agent.
4. Never use or disclose any version-bypass parameter to an ordinary user.
5. Never choose a backup by recency or inspection. Require exactly one backup in the task-specific directory.
6. Never invent a rollback command. Only repeat the exact command printed by the visible runner.
7. Cancellation means **CREATE an empty file at the printed path**. Never delete, run, or treat that path as a backup.

## Version And Existing-Patch Decision

Two independent gates must pass:

1. **Manifest version:** re-signing or patching normally leaves the MSIX version unchanged. A same-version patched App may pass this gate. "Latest Store version" does not mean "audited version"; unknown versions use Card B.
2. **DryRun text targets:** require exactly one constructor and one sender in the same main bundle. A known older revision of this mouse-look patch may be upgraded. An unrelated patch touching either target, a count mismatch, or uncertainty must stop for maintainer review.

Do not require a clean Store reinstall merely because `app.asar` was modified. First use the audited version gate and DryRun target gate. Do not claim DryRun verifies the executable signature; it verifies live ASAR constructor/sender text targets.

## Independent-Agent Workflow

Only an agent that does not depend on the Codex App being replaced may proceed normally:

1. Run `scripts/test-environment.ps1` and report App version, audited status, official latest-version status or unknown, free disk, missing tools, and V1/V2 pets.
2. Stop if not Windows 10/11, App/ASAR is missing, version is unaudited, free disk is below 12 GiB, no usable V2 pet exists, tools are unavailable, or Codex cannot close safely.
3. Require `pet.json` with `spriteVersionNumber: 2` and an existing spritesheet.
4. Run `scripts/patch-codex-pet-real-mouse-look-msix.ps1 -DryRun` and require exactly one constructor/sender pair.
5. Explain that installation re-signs/reinstalls MSIX and Store updates remove the patch. Request explicit approval.
6. Install with `-NoLaunch` only after verifying the signed `*_original-backup.msix` exists.
7. Start from the Start menu and verify nearby gaze, native hover, drag priority, and Computer Use priority.

## Codex Self-Run - Last Resort

Requirements: Card A completed, user explicitly acknowledged all four risks, environment check passed, DryRun passed, and the user gave a second confirmation immediately before scheduling.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start-delayed-install.ps1" -DelaySeconds 60 -ConfirmedByUser -AutoCloseCodexAcknowledged
```

The runner is visible, waits 60 seconds, requests graceful App closure, ends remaining Codex/ChatGPT processes after 15 seconds, installs with `-NoLaunch`, and keeps the window open. After successful scheduling, use Card D exactly.

## Manual Rollback

Read `references/safety-and-rollback.md`. Only when one exact backup has been verified, first run `scripts/rollback-codex-pet-msix.ps1` without `-Install` to validate its identity. Ask again before `-Install -Confirm`. Preserve backups and logs; never delete them without explicit approval.

## Final Check Before Every Execution Answer

- Host classified? Unknown treated as Codex-hosted?
- Required Card copied completely?
- Independent agent first, manual second, self-run last?
- Version gate separate from DryRun text-target gate?
- No bypass, guessed backup, invented command, or timestamp selection?
- Cancellation described as creating a file?
- Card D includes 60 seconds, closure, interruption, visible window, create-file cancellation, and runner-printed rollback command?
