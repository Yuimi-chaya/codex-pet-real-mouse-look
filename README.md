# Codex Pet Real Mouse Look / Codex 桌宠真实鼠标跟随

让 Windows 版 Codex App 的 **V2 桌宠**在鼠标靠近时看向真实鼠标，并在鼠标直接悬停宠物时保留 Codex 原生 hover 动作。

This project patches the Windows Codex App package so v2 pets can look toward the real mouse cursor while preserving native hover behavior.

## 先读这里 / Read first

- 这是一个独立的 Windows Codex App 桌宠补丁项目。
- 它会复制、修改、重新签名并重新安装 Codex App 的 MSIX 包。
- 微软商店更新会覆盖补丁；每个版本安装前都必须重新执行严格 DryRun，只有相关 ASAR 结构发生变化时才需要维护者更新补丁。
- 脚本会在安装前生成原包回滚 MSIX，但任何包体修改仍有风险。
- 真实鼠标转头只适用于 `pet.json` 包含 `"spriteVersionNumber": 2` 的宠物；V1 没有 16 方向转头素材。
- 已完成人工安装测试：`26.707.3748.0`。已完成结构签名核验：`26.707.8479.0`。

This project modifies and re-signs the installed Codex App package. Store updates remove the patch, and every installed version must pass strict ASAR target validation before installation.

### App 版本与已有补丁 / App version and existing patches

- 版本检查读取已安装 MSIX 清单版本。重签名或已有补丁通常不会改变版本号，因此不会仅因“已经打过补丁”而失败。
- 版本号不再作为唯一兼容门槛。`DryRun` 会检查实际 ASAR 中 constructor/sender 的完整结构与唯一性，并允许压缩器只改变局部符号名。当前项目的已知旧版鼠标补丁可以升级；如果其他补丁改动同一事件链、目标重复或结构漂移，脚本会停止。
- “人工测试过”“严格 DryRun 兼容”和“微软商店最新”是三个不同结论。微软商店存在账户、地区、设备与灰度差异，外部脚本查不到权威结果时只会报告 `unknown`，不会假装已经是最新版。
- 如果环境检查明确报告 `update-available`，请先通过微软商店更新。如果报告 `unknown` 且你必须确认最新版，请在微软商店“库”中手动执行“获取更新”，再重新检查。

## 推荐使用方式 / Recommended workflow

普通用户建议把整个仓库交给一个 **不依赖当前 Codex App 会话的 Agent** 执行，例如其他 IDE/终端 Agent。安装过程会关闭并替换 Codex App，让正在被替换的 Codex 自己执行会中断当前会话和工具连接，最终状态也更难确认。

如果当前 Agent 就运行在 Codex App 内，它必须在执行任何脚本前停下来说明风险，并按以下顺序提供选择：

1. 推荐改用独立 Agent；用户愿意时，协助安装、配置并说明如何把本仓库交给它。
2. 给出完整命令，让用户在保存说明后自行从 PowerShell 运行。
3. 只有用户明确坚持、确认理解会话中断和包体重装风险后，才使用本仓库的 60 秒延时自运行模式。

Give the repository to an agent that does not depend on the running Codex App. Do not assume that attaching or naming a Skill makes every Agent read it. Require the Agent to open the full file first:

```text
Before doing anything, read `skill/codex-pet-real-mouse-look/SKILL.md` in full and
treat every Mandatory Response Card as binding. In your first reply, state which
Card applies. Do not run any repository script until the Skill permits it. Then
inspect this PC, explain risks in plain language, run a DryRun, and install only
after I explicitly confirm.
```

Skill 目录：`skill/codex-pet-real-mouse-look/`

支持原生 Skill 的 Agent 也可以显式调用 `$codex-pet-real-mouse-look`，但仍应确认它确实读取了正文，而不是只识别名称。对于不支持 Skill 的 Agent，直接把完整 `SKILL.md` 内容放进上下文。

## 手动流程 / Manual workflow

### 1. 只检查环境

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\test-environment.ps1"
```

检查结果会列出：Windows/PowerShell、Codex App 版本、是否完成人工测试、商店更新状态或 `unknown`、磁盘空间、依赖命令以及所有 V1/V2 宠物。

### 2. Dry-run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\patch-codex-pet-real-mouse-look-msix.ps1" -DryRun
```

每个版本的 Dry-run 都必须成功找到且只找到一组受支持的 ASAR 目标。不要因为“看起来差不多”而绕过结构校验。

### 3. 构建并安装

退出 Codex App 后执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\patch-codex-pet-real-mouse-look-msix.ps1" -Install -NoLaunch -InstallPrerequisites
```

脚本会先在输出目录生成 `*_original-backup.msix`，然后才修改、打包、签名并安装补丁包。安装完成后从开始菜单启动 Codex。

### 4. 回滚

先不安装，仅检查回滚文件：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\rollback-codex-pet-msix.ps1" -BackupMsix "<original-backup.msix>"
```

确认后：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\rollback-codex-pet-msix.ps1" -BackupMsix "<original-backup.msix>" -Install -Confirm
```

## Codex 自助延时模式 / Delayed self-install

只有在独立 Agent 和用户手动执行都不可行，而且用户明确要求 Codex 自己完成时才使用。调度后等待 60 秒，先请求 Codex/ChatGPT 正常退出；仍未退出的残留进程会被结束，然后才开始打包和安装。补丁命令行窗口会保持可见。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start-delayed-install.ps1" -DelaySeconds 60 -ConfirmedByUser -AutoCloseCodexAcknowledged
```

调度后，Agent 的最后一段回复必须明确告诉用户：**60 秒后会自动关闭 Codex App 并开始打补丁；期间不要关闭弹出的命令行窗口。** 同时给出调度命令输出的唯一取消文件路径。若失败，窗口会显示同次 `*_original-backup.msix` 对应的完整回滚命令；不要凭文件名猜测其他备份。

## 行为 / Behavior

- 鼠标在宠物中心约 480px 范围内且最近有移动：看向鼠标。
- 鼠标直接进入宠物区域：停止合成注视，保留原生 hover 动作。
- 鼠标离开宠物但仍在附近：恢复看向鼠标。
- 拖拽或 Computer Use 光标活跃：原生行为优先。

## 项目范围 / Project scope

本仓库只处理 Windows Codex App V2 桌宠真实鼠标跟随及其安全安装、验证和回滚流程，不修改用户的宠物图片或对话数据。

## 免责声明 / Disclaimer

本项目会修改、重新打包、重新签名、卸载并重新安装 Windows Codex App 的 MSIX 包，因此存在安装失败、应用暂时不可用、设置或本地状态异常、与其他补丁冲突以及需要手动恢复等风险。微软商店灰度更新、Codex App 内部结构变化、Windows 环境差异、第三方修改和用户本机状态均可能导致未被当前测试覆盖的结果。

本项目已经尽力提供版本记录、V2 宠物检查、严格 DryRun 结构签名校验、原包备份、任务独立输出目录、失败停止和回滚工具，以降低误操作和不可恢复故障的概率；这些措施不能保证在所有设备、版本和修改组合下都能成功，也不能替代用户对重要数据和当前环境所做的独立备份。

使用、复制或运行本项目，即表示你已经阅读并理解上述风险，自愿决定继续，并同意自行承担由使用或无法使用本项目所产生的后果。在适用法律允许的最大范围内，项目作者及贡献者不对数据丢失、配置损坏、应用不可用、业务中断或其他直接、间接、附带或后续损失承担责任。若你不同意这些条件，或无法确认备份和回滚条件，请不要运行安装脚本。

This project modifies, repackages, re-signs, removes, and reinstalls the Windows Codex App MSIX package. Risks include installation failure, temporary App unavailability, settings or local-state problems, conflicts with other patches, and manual recovery. Store rollouts, internal App changes, Windows differences, third-party modifications, and local machine state may produce outcomes not covered by current testing.

The project provides version reporting, v2 pet checks, strict DryRun structural validation, an original-package backup, task-specific output directories, fail-stop behavior, and rollback tooling to reduce risk. These safeguards cannot guarantee success on every device, version, or patch combination and do not replace the user's own backup of important data and environment state.

By using, copying, or running this project, you acknowledge these risks, choose to proceed at your own discretion, and accept responsibility for the outcome. To the maximum extent permitted by applicable law, the authors and contributors are not liable for data loss, configuration damage, App unavailability, interruption, or other direct, indirect, incidental, or consequential damages arising from use of or inability to use this project. Do not run the installer if you disagree or cannot confirm suitable backup and rollback conditions.

## License

MIT. See [LICENSE](LICENSE).
