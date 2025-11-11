# AI Voice Copilot for CarPlay

A hands-free AI voice assistant for iOS and CarPlay, enabling real-time voice conversations through LiveKit audio streaming.

## Features

- 🚗 **CarPlay Integration** - Native CarPlay interface for hands-free operation
- 📱 **iOS App** - Full-featured phone app with call management
- 🎙️ **Real-time Audio** - LiveKit-powered audio streaming
- 📝 **Session Logging** - Optional conversation recording and summaries
- 🔐 **Secure Authentication** - Token-based auth with Keychain storage
- 💳 **Monetization** - StoreKit 2 subscriptions with free tier (10 min/month)
- ✅ **Comprehensive Testing** - Full unit test coverage

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/jjeremycai/ai-voice-copilot-carplay.git
cd ai-voice-copilot-carplay
open CarPlaySwiftUI.xcodeproj
```

### 2. Add LiveKit SDK

In Xcode:
1. **File → Add Package Dependencies...**
2. Enter: `https://github.com/livekit/client-swift`
3. Add to `CarPlaySwiftUI` target

### 3. Configure Backend

Set your API endpoint via environment variable:

```bash
export API_BASE_URL="https://api.yourcompany.com/v1"
```

Or edit `Services/Configuration.swift`:

```swift
var apiBaseURL: String {
    return "https://api.yourcompany.com/v1"
}
```

### 4. Run Tests

```bash
xcodebuild test -scheme CarPlaySwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or in Xcode: **⌘U**

### 5. Run App

Select target device/simulator and press **⌘R**

## Documentation

- **[COMPLETE_IMPLEMENTATION_SUMMARY.md](COMPLETE_IMPLEMENTATION_SUMMARY.md)** - Monetization setup guide (iOS + Backend)
- **[CLOUDKIT_SETUP.md](CLOUDKIT_SETUP.md)** - CloudKit sync configuration
- **[SETUP.md](SETUP.md)** - Comprehensive setup guide
- **[HANDOFF.md](HANDOFF.md)** - Engineering handoff document
- **[Documentation/MASTER_SPEC.md](Documentation/MASTER_SPEC.md)** - Complete specification

## Architecture

```
┌─────────────────┐
│   CarPlay UI    │
│   Phone UI      │
└────────┬────────┘
         │
┌────────▼────────────────────────┐
│  AssistantCallCoordinator       │
├─────────────────────────────────┤
│  - CallManager (CallKit)        │
│  - LiveKitService (Audio)       │
│  - SessionLogger (Backend)      │
│  - AuthService (Auth)           │
└─────────────────────────────────┘
```

### Core Services

- **CallManager** - CallKit integration for VoIP calls
- **LiveKitService** - Real-time audio streaming
- **SessionLogger** - Backend API client
- **AuthService** - Token management
- **Configuration** - Environment configuration

## Requirements

- **Xcode**: 15.2+
- **iOS**: 17.2+
- **Swift**: 5.9+
- **Apple Developer Account** (for CarPlay entitlement)
- **LiveKit Server** (for audio streaming)
- **Backend API** (for session management)

## Configuration

The app uses a centralized configuration system:

```swift
// Services/Configuration.swift
struct Configuration {
    var apiBaseURL: String        // Backend API
    var authLoginURL: String       // Login endpoint
    var authRefreshURL: String     // Token refresh
    var isLoggingEnabled: Bool     // Session logging
}
```

Configure per environment:
- **Development**: `API_BASE_URL` environment variable
- **Staging**: Modify `Configuration.swift`
- **Production**: Set in Xcode scheme

## API Endpoints

Your backend must implement:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/sessions/start` | POST | Start session, get LiveKit credentials |
| `/sessions/end` | POST | End session |
| `/sessions/:id/turns` | POST | Log conversation turn |
| `/sessions` | GET | Fetch session list |
| `/sessions/:id` | GET | Fetch session details |
| `/sessions/:id` | DELETE | Delete session |
| `/auth/login` | POST | User login |
| `/auth/refresh` | POST | Refresh token |

See [SETUP.md](SETUP.md) for detailed API specifications.

## Testing

### Run All Tests

```bash
xcodebuild test -scheme CarPlaySwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage

- ✅ CallManager - Call lifecycle, error handling
- ✅ AssistantCallCoordinator - State transitions, context
- ✅ SessionLogger - API requests, authentication
- ✅ AuthService - Token storage, Keychain operations

### Mock Infrastructure

- **MockCallKit** - Simulates CallKit without system dependencies
- **MockURLProtocol** - Intercepts network requests

## Development

### Without Backend

For local testing:

```swift
// Set dev token directly
AuthService.shared.setToken("dev-token-12345")
```

### With Backend

1. Configure API URL in `Configuration.swift`
2. Start your backend server
3. Test authentication and call flow

### CarPlay Testing

**Simulator:**
- I/O → External Displays → CarPlay

**Device:**
- Connect to CarPlay-enabled vehicle
- Test hands-free operation

## Deployment

### Pre-Deployment Checklist

- [ ] LiveKit SDK integrated
- [ ] Backend API connected
- [ ] CarPlay entitlement approved
- [ ] Tests passing
- [ ] Production URLs configured
- [ ] Error handling tested

### CarPlay Entitlement

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Select your App ID
3. Enable **CarPlay Communication** capability
4. Submit request (1-2 weeks approval)

See [SETUP.md](SETUP.md) for detailed deployment instructions.

## Project Structure

```
carplay-swiftui-master/
├── Services/
│   ├── CallManager.swift              # CallKit integration
│   ├── LiveKitService.swift           # Audio streaming
│   ├── SessionLogger.swift            # Backend API
│   ├── AuthService.swift              # Authentication
│   └── Configuration.swift            # Environment config
├── Coordinators/
│   ├── AppCoordinator.swift
│   └── AssistantCallCoordinator.swift
├── Models/
│   ├── Session.swift
│   └── UserSettings.swift
├── Screens/
│   ├── HomeScreen.swift
│   ├── OnboardingScreen.swift
│   ├── SessionsListScreen.swift
│   ├── SessionDetailScreen.swift
│   └── SettingsScreen.swift
├── CarPlaySceneDelegate.swift
├── CarPlaySwiftUITests/
│   ├── Mocks/
│   ├── CallManagerTests.swift
│   ├── AssistantCallCoordinatorTests.swift
│   ├── SessionLoggerTests.swift
│   └── AuthServiceTests.swift
└── Documentation/
    ├── MASTER_SPEC.md
    ├── IMPLEMENTATION_STATUS.md
    └── FIXES_APPLIED.md
```

## Troubleshooting

### LiveKit SDK Not Found

```bash
# Clean build
⌘⇧K

# Reset package cache
File → Packages → Reset Package Caches

# Rebuild
⌘B
```

### Backend Connection Fails

1. Verify API URL is correct
2. Test endpoint with curl:
   ```bash
   curl -X POST https://api.yourcompany.com/v1/sessions/start \
     -H "Authorization: Bearer token" \
     -d '{"context":"phone"}'
   ```

### CarPlay Not Appearing

1. Verify entitlement approved by Apple
2. Update provisioning profiles
3. Test on physical device

See [SETUP.md](SETUP.md) for more troubleshooting.

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## License

[License information]

## Acknowledgments

- [LiveKit](https://livekit.io/) - Real-time audio infrastructure
- [Apple CarPlay](https://developer.apple.com/carplay/) - In-vehicle interface

---

**Status**: ✅ Foundation Complete - Ready for LiveKit & Backend Integration

See [HANDOFF.md](HANDOFF.md) for detailed implementation status.
