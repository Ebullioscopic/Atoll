# Code Island Buddy

This is the Xcode project for the Code Island iPhone, Live Activity, and Apple Watch Buddy.

For the product overview, setup guide, protocol notes, and screenshots, see:

- [`../../apple-companion/README.md`](../../apple-companion/README.md)

## Project Contents

- `CodeIslandCompanion/` - iPhone app
- `CodeIslandCompanionWidget/` - iPhone Live Activity, Dynamic Island, and StandBy UI
- `CodeIslandWatchApp/` - Apple Watch app
- `CodeIslandWatchWidget/` - watchOS widget
- `Shared/` - shared models, display helpers, and mascot views
- `project.yml` - XcodeGen project definition

## Open in Xcode

```bash
cd ios/CodeIslandCompanion
xcodegen generate
open CodeIslandCompanion.xcodeproj
```
