# Rook (iOS)

Native SwiftUI app for Rook. It uses the existing backend in `packages/` without any changes to it.
The plan and the status of each phase are in [`specs/ios-native-rebuild-plan.md`](../specs/ios-native-rebuild-plan.md).

## Requirements

- Xcode 16.3+ (iOS 17 deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Everyday commands

```bash
make open        # generate Rook.xcodeproj from project.yml and open it in Xcode
make test        # brand check + RookKit tests (macOS) + app unit/UI tests (simulator)
make test-kit    # fast: RookKit logic tests only, no simulator
make build       # debug simulator build
```

`Rook.xcodeproj` is generated and git-ignored. Edit `project.yml`, never the project file itself.

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec: targets, schemes, Info.plist keys |
| `Config/Base.xcconfig` | Signing team, version, and backend endpoints (public identifiers, not secrets). Per-machine overrides go in a git-ignored `Config/Local.xcconfig` |
| `RookKit/` | Swift package holding all non-UI logic (models, networking, auth contracts, workout session engine, formatting). Tests run with `swift test` |
| `Rook/` | The app: SwiftUI features, design system, services, resources |
| `RookTests/` | App-target unit tests (Swift Testing) |
| `RookUITests/` | UI smoke tests (XCUITest) |

## Rules

- No mock data, placeholder features, or dev toggles in the `Rook` target. Fakes belong in test targets only.
- No Repwise branding: `make lint` fails if "repwise" appears outside the backend endpoint values in `Config/`.
- Backend code in `packages/` is never modified for this app.
