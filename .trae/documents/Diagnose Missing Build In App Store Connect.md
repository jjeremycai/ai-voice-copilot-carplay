## Likely Causes
- Bundle identifier mismatch (case-sensitive): build uses `com.vanities.Shaw`; ASC app may be `com.vanities.shaw`.
- Team/account mismatch: upload tied to a different org than your ASC app record.
- Distribution signing: archive signed for Development and export didn’t re-sign properly.
- Version/build duplication: same `CFBundleShortVersionString` and `CFBundleVersion` already uploaded → ASC ignores.

## Quick Checks (You Do In ASC/Transporter)
- ASC → App Information → confirm Bundle ID exactly matches `com.vanities.Shaw`.
- ASC → TestFlight → see if any new build is “Processing”. It can take 10–20 minutes.
- ASC → Users and Access → Keys: confirm key `G26HL635HC` belongs to the same org as the app.
- Transporter app: sign in with Apple ID; Recent Deliveries shows Apple ID uploads only (API key uploads may not appear).

## Local Verification I Can Run
- Inspect `build/Shaw.ipa` Info.plist to confirm bundle id, version, build.
- Check signing on IPA to ensure “Apple Distribution” identity.
- Read `Packaging.log` to confirm export profile and signing.

## Remediation Steps (If Mismatch)
- If bundle ID differs: update Xcode target bundle id to match ASC app, re-archive, re-export, re-upload.
- If team mismatch: re-auth with correct ASC key or use Apple ID + provider short name, then re-upload.
- If signing issue: set Signing Certificate to Apple Distribution for Release, re-export.
- If version/build duplication: bump build number, re-archive, export, upload.

## Simpler Alternative
- Upload via Xcode Organizer (one flow) using Apple ID credentials and correct team; it selects provider automatically and shows the delivery immediately.

## Next Step
- I will run the local verifications (IPA plist, signing, packaging log) and report findings, then re-upload with the minimal fix. Confirm and I’ll proceed.