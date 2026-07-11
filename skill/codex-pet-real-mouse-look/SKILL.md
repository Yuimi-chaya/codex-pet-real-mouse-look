---
name: codex-pet-real-mouse-look
description: Inspect, dry-run, install, verify, or roll back the standalone Windows Codex App v2 pet real-mouse-look MSIX patch. Use when a user wants real mouse look without Codex++, needs compatibility checks for Windows/PowerShell/App version/path/disk/tools, needs v2 pet validation, or needs a safe delayed install after Codex exits.
---

# Codex Pet Real Mouse Look

Treat the user as non-technical unless they demonstrate otherwise. Explain each destructive or package-changing step in plain language and never ask them to improvise paths or commands.

## Boundaries

- This Skill controls the standalone MSIX/ASAR patch in this repository.
- It is not the package-free Codex++ pet PR.
- The patch modifies, re-signs, removes, and reinstalls the Windows Codex App package. State this before requesting installation approval.
- Prefer an agent that does not run inside the Codex App being replaced. Codex may inspect and teach, but another terminal/IDE agent should execute when available.

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

Use `scripts/start-delayed-install.ps1 -ConfirmedByUser`. Default to at least 180 seconds. Tell the user the exact task-specific cancellation file path printed by the command. The delayed runner must keep checking that marker while it waits for Codex to exit, cancel after 10 minutes, and never force-close Codex.

## Rollback

Read `references/safety-and-rollback.md`. First run rollback without `-Install`, show the resolved backup path, then request confirmation. Never choose a backup by filename guess when multiple packages exist.
