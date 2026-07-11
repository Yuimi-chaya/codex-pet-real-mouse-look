# Codex Pet Real Mouse Look / Codex 桌宠真实鼠标跟随

让 Windows 版 Codex App 的 **V2 桌宠**在鼠标靠近时看向真实鼠标，并在鼠标直接悬停宠物时保留 Codex 原生 hover 动作。

This project patches the Windows Codex App package so v2 pets can look toward the real mouse cursor while preserving native hover behavior.

## 先读这里 / Read first

- 这是独立脚本项目，**不需要安装 Codex++**。
- 它会复制、修改、重新签名并重新安装 Codex App 的 MSIX 包。
- 微软商店更新会覆盖补丁；每个新 App 版本都必须重新审计兼容性。
- 脚本会在安装前生成原包回滚 MSIX，但任何包体修改仍有风险。
- 真实鼠标转头只适用于 `pet.json` 包含 `"spriteVersionNumber": 2` 的宠物；V1 没有 16 方向转头素材。
- 当前已审计版本：`26.707.3748.0`。版本不匹配时默认停止。

This is a standalone package patch, not the Codex++ integration. It modifies and re-signs the installed package. Store updates remove the patch, and unaudited App versions are rejected by default.

## 推荐使用方式 / Recommended workflow

普通用户建议把整个仓库交给一个 **不依赖当前 Codex App 会话的 Agent** 执行，例如其他 IDE/终端 Agent。因为安装过程需要退出并替换 Codex App，让 Codex 自己重启自己不够稳定。

Give the repository to an agent that does not depend on the running Codex App. Ask it to use the bundled Skill:

```text
Use $codex-pet-real-mouse-look to inspect this PC, explain risks in plain language,
run a dry-run, and install only after I explicitly confirm.
```

Skill 目录：`skill/codex-pet-real-mouse-look/`

## 手动流程 / Manual workflow

### 1. 只检查环境

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\test-environment.ps1"
```

检查结果会列出：Windows/PowerShell、Codex App 版本、版本是否已审计、磁盘空间、依赖命令以及所有 V1/V2 宠物。

### 2. Dry-run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\patch-codex-pet-real-mouse-look-msix.ps1" -DryRun
```

Dry-run 必须成功找到且只找到一组受支持的 ASAR 目标。不要因为“看起来差不多”而使用版本绕过。

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

只有在用户明确确认风险、但无法自行退出后运行命令时才使用。默认等待 180 秒，并继续等待 Codex 完全退出；不会强杀 Codex。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start-delayed-install.ps1" -DelaySeconds 180 -ConfirmedByUser
```

取消：创建调度命令输出的唯一 `CANCEL-DELAYED-INSTALL-<任务 ID>` 文件。脚本在延时期间、等待 Codex 退出期间和安装前都会检查它；若 Codex 10 分钟内没有完全退出，安装自动取消。

## 行为 / Behavior

- 鼠标在宠物中心约 480px 范围内且最近有移动：看向鼠标。
- 鼠标直接进入宠物区域：停止合成注视，保留原生 hover 动作。
- 鼠标离开宠物但仍在附近：恢复看向鼠标。
- 拖拽或 Computer Use 光标活跃：原生行为优先。

## 项目边界 / Project boundary

- 本仓库：面向不安装 Codex++ 的用户，修改 Codex App 包体。
- Codex++ PR：免改包的 launcher/CDP 集成，是另一个项目和发布路径。

两者不能混用安装说明、风险声明或回滚方式。

## License

MIT. See [LICENSE](LICENSE).
