## Cause
- The app bundle references camera APIs (e.g., via LiveKit/WebRTC), which requires `NSCameraUsageDescription` even if camera features are optional or not currently used.

## Fix
- Add `NSCameraUsageDescription` to `Info.plist` with a clear, user-facing reason.
- Recommended string: "Camera access enables optional video during calls and future visual features."
- Keep existing `NSMicrophoneUsageDescription`; no change needed.

## Additional Safeguards (Optional)
- If any library references photo library APIs, add:
  - `NSPhotoLibraryUsageDescription`: "Allow saving or selecting media when needed."
  - `NSPhotoLibraryAddUsageDescription`: "Allow saving call-related media if enabled."
- Audit for other sensitive keys if applicable: `NSBluetoothAlwaysUsageDescription`, `NSSpeechRecognitionUsageDescription` (only if using Apple speech APIs), `NSContactsUsageDescription` (if accessing contacts).

## Rebuild & Reupload (CLI)
1. Bump build number to avoid duplicate build conflicts (e.g., set `CFBundleVersion` to `2`).
2. Archive:
   - `xcodebuild -project Shaw.xcodeproj -scheme Shaw -configuration Release -sdk iphoneos -archivePath build/Shaw.xcarchive archive`
3. Export IPA:
   - `xcodebuild -exportArchive -archivePath build/Shaw.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build -allowProvisioningUpdates`
4. Upload via Transporter (ASC key):
   - `xcrun iTMSTransporter -m upload -assetFile build/Shaw.ipa -apiKey G26HL635HC -apiIssuer 1b1f70f6-3fbb-49c9-8230-2e55cb269214 -verbose`

## Validation
- Inspect `build/Shaw.ipa` Info.plist to confirm `NSCameraUsageDescription` is present and strings are correct.
- Ensure TestFlight shows the new build after processing.

## Next Step
- I will add the usage description to `Info.plist`, bump the build number, re-archive, re-export, and re-upload. Confirm to proceed and I’ll execute these steps immediately.