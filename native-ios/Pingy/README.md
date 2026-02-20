# Pingy Native iOS

Fully native iOS client for Pingy using:
- Swift + SwiftUI
- MVVM architecture
- CryptoKit (ECDH + AES.GCM)
- URLSession + URLSessionWebSocketTask (Socket.IO frame protocol)
- AVFoundation (voice recording)
- PhotosUI (media picker)

## Folders

- `Pingy/App` app lifecycle, config, Info.plist
- `Pingy/Views` SwiftUI screens
- `Pingy/ViewModels` state + UI logic
- `Pingy/Models` API/domain models
- `Pingy/Services` REST/chat/settings/auth/push/voice services
- `Pingy/Crypto` end-to-end encryption service
- `Pingy/Networking` API and websocket transport
- `Pingy/Utilities` shared helpers

## Build via GitHub Actions

Workflow file:
- `.github/workflows/build-native-ios-ipa.yml`

It produces:
- Unsigned IPA artifact (`Pingy-native-v3.3-unsigned-ipa`) on every push to `main`.
- Optional signed IPA artifact when signing secrets are configured.

## Optional signing secrets

If you want CI to export a signed IPA, set:
- `APPLE_TEAM_ID`
- `IOS_P12_BASE64`
- `IOS_P12_PASSWORD`
- `IOS_MOBILEPROVISION_BASE64`
- `APPLE_ID` (optional metadata)
- `APPLE_APP_PASSWORD` (optional metadata)

## E2EE compatibility note

The current backend schema accepts public key JWK with `crv: P-256`.
This native app uses CryptoKit ECDH P-256 for interoperability with existing web clients and stored chat data.
