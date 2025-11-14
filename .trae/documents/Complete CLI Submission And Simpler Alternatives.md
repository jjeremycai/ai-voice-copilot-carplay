## Current Status
- Archive completed: `build/Shaw.xcarchive` (Xcode logs show archive succeeded).
- IPA exported: `build/Shaw.ipa` with automatic signing and App Store Connect method (ExportOptions updated).
- dSYMs present: `build/Shaw.xcarchive/dSYMs/Shaw.app.dSYM`.
- Scheme confirms app target: `Shaw.xcodeproj/xcshareddata/xcschemes/Shaw.xcscheme:19-22`.
- Bundle identifier and signing verified via `xcodebuild -showBuildSettings`.

## Simplest Paths
- Fastest GUI: Use Xcode Organizer → Distribute App → App Store Connect → Upload (single flow).
- Transporter app GUI: Drag `build/Shaw.ipa`, sign in, upload.
- One-command CLI (Apple ID): `xcrun iTMSTransporter -m upload -assetFile build/Shaw.ipa -u <apple_id> -p <app_specific_password> -verbose`.
- One-command CLI (ASC API key): `xcrun iTMSTransporter -m upload -assetFile build/Shaw.ipa -apiKey <ASC_KEY_ID> -apiIssuer <ASC_ISSUER_ID> -verbose` with `AuthKey_<ASC_KEY_ID>.p8` placed in `~/.appstoreconnect/private_keys/`.

## Preferred CLI Plan (Minimal Steps)
1. Create an Apple ID app-specific password if you don’t already have one.
2. Upload IPA via Transporter CLI:
   - `xcrun iTMSTransporter -m upload -assetFile build/Shaw.ipa -u <apple_id> -p <app_specific_password> -verbose`
3. Verify processing in App Store Connect → TestFlight.
4. If needed, distribute to internal testers.

## Alternative: ASC API Key (You already have a .p8)
1. Move your `.p8` key to `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`.
2. Run:
   - `xcrun iTMSTransporter -m upload -assetFile build/Shaw.ipa -apiKey <ASC_KEY_ID> -apiIssuer <ASC_ISSUER_ID> -verbose`
3. Check status:
   - `xcrun iTMSTransporter -m status -apiKey <ASC_KEY_ID> -apiIssuer <ASC_ISSUER_ID>`

## Alternative: Fastlane (Single Command)
- Create `api_key.json` from your `.p8` (key id, issuer id, key file path).
- Upload:
  - `fastlane pilot upload --ipa build/Shaw.ipa --api_key_path api_key.json`
- Distribute to testers:
  - `fastlane pilot distribute --groups "Internal" --api_key_path api_key.json`

## Validation
- After upload, confirm the build appears in TestFlight and finishes processing.
- Run a quick internal tester install on device to verify launch and microphone permission prompt; app icons and entitlements are already configured (`Info.plist:35-41`, `Shaw.entitlements:12-23`).

## Next Step
- Pick the preferred path (Transporter CLI with Apple ID, ASC API key, or Fastlane). After confirmation, I will run the exact upload command, wait for completion, and report TestFlight processing status.