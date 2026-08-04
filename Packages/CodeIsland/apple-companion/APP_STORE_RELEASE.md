# Code Island App Store Release Checklist

This checklist covers the iPhone, Live Activity, Dynamic Island, StandBy, Apple Watch app, and watchOS widget Buddy for Code Island.

Current public submission target:

- Version: `1.0.0`
- Build: `4`
- Primary working directory: `/Users/fengye/workspace/CodeIsland`
- Xcode project: `ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj`

## Before Uploading a Build

1. Confirm Apple Developer signing is selected for every target:
   - `CodeIslandCompanion`
   - `CodeIslandCompanionWidget`
   - `CodeIslandWatchApp`
   - `CodeIslandWatchWidget`

2. Confirm the app can be reviewed without a Mac:
   - Launch the iPhone app.
   - Tap `进入演示模式`.
   - Tap `开启实时活动` to show the Live Activity / Dynamic Island preview.
   - Open the Apple Watch app and confirm it receives the demo state.

3. Confirm the real Mac path still works:
   - Run the matching Code Island Mac build from this branch.
   - Open Code Island Settings -> Buddy.
   - Enable iPhone Buddy broadcasting.
   - Connect from iPhone and verify state updates.

4. Run local verification:

```bash
scripts/check-companion-ui-regressions.sh
scripts/smoke-companion-ui.sh
scripts/smoke-companion-watch-ui.sh
swift test --filter AppleCompanionPayloadTests
```

5. Archive from Xcode:
   - Select `Any iOS Device (arm64)` or a connected iPhone.
   - Choose `Product -> Archive`.
   - In Organizer, choose `Distribute App -> App Store Connect -> Upload`.

## App Store Connect Metadata

Use `apple-companion/APP_STORE_METADATA.md` as the source of truth for name, subtitle, description, keywords, URLs, privacy answers, export compliance notes, and "What's New" text.

Privacy policy:

Publish `apple-companion/PRIVACY_POLICY.md` somewhere public, for example GitHub Pages, and use that public URL in App Store Connect. The proposed URL is listed in `apple-companion/APP_STORE_METADATA.md`.

## App Privacy Answers

Current intended privacy posture:

- Data collection: no data collected by the developer.
- Tracking: no tracking.
- Third-party advertising: none.
- Account creation: none.
- Local network: used only to discover and communicate with the user's own Mac running Code Island.
- Bluetooth: used only as a lightweight local Buddy signal between the user's own devices.

If new analytics, crash reporting, cloud sync, or third-party SDKs are added later, update these answers before submission.

## Export Compliance

The app uses Apple's local networking and platform security APIs. It does not implement custom encryption. When App Store Connect asks export compliance questions, answer based on the final binary and Apple's current wording. If the app only uses standard Apple-provided encryption, it usually falls under the platform-provided encryption path rather than a custom cryptography product.

## Review Notes

Use the template in `apple-companion/APP_REVIEW_NOTES.md`.

Important: tell reviewers about `进入演示模式`, because reviewers may not have the matching Mac Buddy available.

## Final Manual Test Matrix

| Area | Test |
| --- | --- |
| iPhone app | Launch, enter demo mode, switch demo state, exit demo mode |
| Local network | Connect to Mac, receive idle/running/question/interrupted state |
| Live Activity | Start, update, stop, verify Dynamic Island and Lock Screen |
| Background | Put iPhone app in background, trigger Mac state update, verify Live Activity update if system schedules it |
| Watch app | Install, launch, receive state from iPhone, scroll status/message/actions/activity pages |
| Watch widget | Add widget / Smart Stack item, verify latest state appears |
| Permissions | Local Network, Bluetooth, Notifications |
| Failure modes | Mac not found, Mac disconnected, iPhone app relaunched, Watch launched before iPhone sync |
