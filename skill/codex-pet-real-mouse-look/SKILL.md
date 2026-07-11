---
name: codex-pet-real-mouse-look
description: Inspect, dry-run, install, verify, or roll back the standalone Windows Codex App v2 pet real-mouse-look MSIX patch. Use when a user needs compatibility checks for Windows, PowerShell, App version, existing package patches, paths, disk, tools, v2 pet validation, or a carefully confirmed delayed install.
---

# Codex Pet Real Mouse Look

Treat the user as non-technical unless they demonstrate otherwise. Explain each destructive or package-changing step in plain language and never ask them to improvise paths or commands.

## Boundaries

- This Skill controls the standalone MSIX/ASAR patch in this repository.
- The patch modifies, re-signs, removes, and reinstalls the Windows Codex App package. State this before requesting installation approval.
- Prefer an agent that does not run inside the Codex App being replaced. Codex may inspect and teach, but another terminal/IDE agent should execute when available.

## Mandatory Codex-host stop

If you are running inside Codex App, stop before executing **any repository script**, including environment checks and DryRun. Explain that installation closes and replaces the App hosting this conversation, so the session, terminal, and status reporting can be interrupted.

Offer these paths in order:

1. Recommend an independent terminal/IDE agent. If the user agrees, help install and configure one using its official instructions, then explain how to open this repository and invoke this Skill there. Do not change global proxy/package-manager configuration.
2. Give the user exact PowerShell commands to run manually after preserving the instructions.
3. Only after the user explicitly insists on Codex self-execution and acknowledges automatic App closure, session interruption, package replacement, and rollback risk may you inspect or run scripts here. Never infer consent from the original feature request.

## Required workflow

1. Confirm the shell and OS. Use Windows PowerShell or PowerShell 7 syntax correctly. Quote all paths.
2. Run `scripts/test-environment.ps1` and summarize only:
   - installed Codex App version
   - whether that version is audited
   - latest-version status
   - free disk space
   - missing dependencies
   - pet IDs and V1/V2 status
3. Do not call a version “latest” from the audited matrix. Check Microsoft Store or an official source. If unavailable, report latest status as unknown.
4. Require at least one usable manifest under `~/.codex/pets/*/pet.json` with `spriteVersionNumber: 2` and an existing spritesheet. V1 pets do not contain look-direction rows. Stop unless the user explicitly asks only to build for later use.
5. Run the patch script with `-DryRun`. Require an audited App version and exactly one constructor/sender target pair.
6. Explain the result and ask for explicit approval before `-Install`. Mention that the App must close, the package is re-signed/reinstalled, Store updates remove the patch, and rollback is not risk-free.
7. Install with `-NoLaunch`. Confirm the `*_original-backup.msix` exists before allowing package replacement.
8. Start Codex from the Start menu only after installation completes. Verify nearby gaze, native hover priority, exit/resume behavior, dragging, and Computer Use priority.
9. Preserve the backup MSIX and logs. Never delete rollback artifacts without explicit approval.

## Compatibility stops

Stop rather than bypass when any condition holds:

- not Windows 10/11
- Codex App package is missing
- App version is not in `references/compatibility.md`
- package path or `app/resources/app.asar` is missing
- no usable v2 pet exists
- output drive has less than 12 GiB free
- Dry-run target count is not exactly one pair
- required signing/packing tools cannot be installed or located
- Codex cannot be closed safely

Never use `-AllowVersionMismatch` merely because the user wants to proceed. That switch is for a maintainer who has audited and updated target signatures.

## Delayed self-install

Use delayed installation only when all are true:

- no independent agent is available
- the user cannot execute the final command themselves
- Dry-run already passed
- rollback MSIX expectations and risks were explained
- the user explicitly approved delayed execution

Use `scripts/start-delayed-install.ps1 -DelaySeconds 60 -ConfirmedByUser -AutoCloseCodexAcknowledged`. Tell the user the exact task-specific cancellation file path printed by the command. The visible delayed runner waits 60 seconds, requests graceful App closure, ends remaining Codex/ChatGPT processes after 15 seconds, installs with `-NoLaunch`, and keeps its window open with either success information or the exact rollback command.

The final paragraph before ending the Codex-hosted conversation must say, in the user's language: **Codex App will close automatically and patching will begin in 60 seconds. Do not close any command window that appears. If the final stage fails, keep that window open and run the rollback command printed there.** Include the cancellation file path in the same paragraph.

## Rollback

Read `references/safety-and-rollback.md`. First run rollback without `-Install`, show the resolved backup path, then request confirmation. Never choose a backup by filename guess when multiple packages exist.
