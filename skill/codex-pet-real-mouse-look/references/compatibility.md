# Compatibility

## Audited App versions

| Codex App | Chromium | Status | Notes |
|---|---:|---|---|
| `26.707.3748.0` | `150` | Audited and human-tested | V2 look, 480px activation, native hover priority |

An audited version is not necessarily the latest Microsoft Store version. Verify latest status separately. Unknown versions stop by default until a maintainer audits the main-process constructor and sender signatures, updates tests, and performs install/rollback validation.

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
