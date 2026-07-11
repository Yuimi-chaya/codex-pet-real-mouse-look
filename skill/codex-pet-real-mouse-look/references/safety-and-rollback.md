# Safety and rollback

## What installation changes

The script copies the installed Codex package, extracts and edits `app/resources/app.asar`, updates executable ASAR integrity, creates/trusts a local signing certificate, packs and signs an MSIX, removes the current user package, and installs the patched package.

## Required safeguards

- Run environment check and Dry-run first.
- Use only audited App versions.
- Keep at least 12 GiB free on the output drive.
- Before patching, create and sign `*_original-backup.msix` from the copied unmodified package layout.
- Install with `-NoLaunch`; start from the Start menu after success.
- Preserve application data where Windows supports it.
- Keep output artifacts until the user validates the patched App and a rollback test path.

## Failure handling

- If extraction, target matching, integrity update, packing, signing, or installation fails, stop.
- Do not edit files directly inside `C:\Program Files\WindowsApps`.
- Do not reuse artifacts from a different App version.
- Do not delete the current package unless a verified rollback MSIX exists.
- If installation fails after removal, install the exact `*_original-backup.msix` generated in the same run.

## Delayed execution

Delayed execution is a last resort for a Codex-hosted agent. It requires explicit approval, a visible delay, a cancellation path, and a clean Codex exit. It must never be registered as a startup task or run later without fresh user awareness.
