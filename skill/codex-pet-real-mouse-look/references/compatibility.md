# Compatibility

## Known App versions

| Codex App | Status | Notes |
|---|---|---|
| `26.707.3748.0` | Human-tested | Install, rollback, V2 look, 480px activation, native hover priority |
| `26.707.8479.0` | Structure-verified | Constructor/sender event flow matches after minifier-symbol normalization; installation not yet human-tested |

A known or human-tested version is not necessarily the latest Microsoft Store version. Microsoft Store rollout can vary by account, region, device, and time. An external Agent must report `unknown` when it cannot obtain an authoritative per-user result; it must never translate “no result” into “up to date.”

The version check reads the installed package manifest. Re-signing or patching an App normally leaves that version unchanged. Version membership is informational rather than the sole compatibility gate: every version must pass DryRun against the live ASAR. The matcher accepts minifier-only changes to the native-position controller, subscription, and Electron screen aliases while requiring the complete constructor/sender event flow to be unique. Known earlier revisions of this mouse-look patch can be upgraded; unrelated changes, partial matches, duplicate targets, or ambiguous aliases stop for maintainer review.

## Pet format

The patch requires at least one manifest at:

```text
%USERPROFILE%\.codex\pets\<pet-id>\pet.json
```

V2 requires:

```json
{
  "spriteVersionNumber": 2,
  "spritesheetPath": "spritesheet.png"
}
```

V2 uses an 8x11 atlas: 9 standard animation rows plus 16 look directions in rows 9-10. V1 pets lack these look-direction rows.
