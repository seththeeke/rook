# Rook — Native iOS Rebuild Plan

**Status:** Decisions confirmed (2026-11-13), ready for Phase 0 · **Owner:** seththeeke · **Created:** 2026-11-13
**Target directory:** `ios-app/` · **Bundle ID:** `com.rookfitness.app` · **Installs alongside** the existing Capacitor app (`com.repwisefit.app`), which stays untouched

## Progress

| Phase | Status | Notes |
|---|---|---|
| 0: Foundation | **Done** (2026-11-13) | See "Phase 0 deviations" below. |
| 1: Auth / onboarding / profile / settings | **Built**, awaiting device test | Sign in/up/confirm/reset, biometric lock, equipment onboarding, profile, settings (units, Face ID, sign out, delete account). |
| 2: Dashboard + history | **Built**, awaiting device test | Streak, corrected 30-day stats, PRs, week strip + calendar, recent workouts, history, detail. |
| 3: Workout building | **Built**, awaiting device test | AI (stream, progress, cancel, regenerate), manual, past workout, review, start. |
| 4a / 4b: Execution + Live Activity | **Built**, awaiting device test | Execution screen, session controller, widget extension, interactive Pause/Next. |
| 5: Release readiness | Not started | Accessibility pass, TestFlight upload. |

**Verification so far:** 208 RookKit tests (every module ≥ 93% line coverage, gated) and 17 app/UI tests pass on the iOS 18.4 simulator, and the signed-out UI was checked visually. **Not yet verified:** live Cognito sign-in, real API responses, and everything in the Phase 4a manual device checklist (Dynamic Island, lock-screen ticking, background intents). These need a real account and an iPhone.

**Phases 1–4 deviations from the plan**

- **View models live in the `RookFeatures` package module**, not the app target, so they're covered by fast `swift test` runs and by the RookKit coverage gate. The app target is now SwiftUI views and thin platform adapters (Amplify, ActivityKit, LocalAuthentication), so its line coverage is low by design. Those adapters are verified on device.
- **The Dashboard is the signed-in root from the start**, rather than Profile in Phase 1 and then Dashboard in Phase 2, because the phases shipped together.
- **Cancelling a workout that fails on the server** offers "Discard Workout" (local only) instead of silently clearing it.
- **A workout that's already completed or cancelled on the server** (e.g. finished on the web) is treated as finished when you complete or cancel it in Rook.
- **The Dynamic Island "Next" button** is hidden on the last exercise, because completing needs the confirmation in the app.

**Phase 0 deviations from the plan**

- **Widget extension target and `RookLiveActivityKit` are deferred to Phase 4.** There's nothing to put in them until the Live Activity is ported, and an empty widget bundle doesn't compile.
- **Amplify Swift is pinned to 2.61.0.** Releases 2.62.0 and later use a language feature that the Swift 6.1 compiler in Xcode 16.3 rejects. Revisit after upgrading Xcode.
- **Command-line builds pass `-skipPackagePluginValidation -skipMacroValidation`** because Amplify's `smithy-swift` dependency ships an SPM plugin. In Xcode, trust the plugin once when prompted.
- **Fixtures** were built from the Lambda response mappers (`toResponse`, `toMeProfile`, etc.) rather than captured from the live API. If a decoding problem shows up against real data, capture and add that payload as a fixture.
- **Coverage gate:** RookKit is gated per module by `scripts/check-coverage.py` (`make test-kit`). The app-target view-model threshold (70%) starts being enforced in Phase 1, once view models exist. Right now the app target is mostly views and the live Amplify adapter.
- **No SwiftLint/SwiftFormat yet.** `make lint` currently runs only the brand check.
- `make archive` / `make export` are added in Phase 5.

## 1. Goal

Rebuild the iPhone app as a native **Swift / SwiftUI** app called **Rook** (rebranded from Repwise). It talks to the **existing, unchanged** Repwise backend. The first release is a deliberately smaller app built around the flows used daily:

1. Sign in / sign out / a simple profile
2. The dashboard
3. Building a workout, then running it, with the **Live Activity / Dynamic Island**. This is the most-used feature and the top priority.

### Ground rules

| Rule | What it means in practice |
|---|---|
| **No backend changes** | Nothing in `packages/lambdas`, `packages/cdk`, or the Cognito setup changes. Every backend quirk the app must live with is listed in §6. |
| **Production-ready, no mocks** | The app target has no mock data, placeholder screens, admin tools, dev toggles, or "coming soon" items. Everything on screen is backed by a real endpoint or real local state, or it isn't shown. Fakes live **only** in test targets. |
| **Rebrand, no Repwise anywhere** | Nothing a user can see says "Repwise": app name, copy, icon, launch screen, Live Activity, permission prompts (`NSFaceIDUsageDescription`), App Store metadata. Internal identifiers use `rook` too (bundle IDs, `os.Logger` subsystem, UserDefaults and file names). The color palette stays. Backend names (`repwise-*` tables, `api.repwisefit.com`, the Cognito pool) are never shown to users and stay as they are. A grep check in `make lint` fails the build if "repwise" (any case) appears in `ios-app/` outside `Config/*.xcconfig` endpoint values. |
| **Built in pieces** | Each phase in §7 ships something that runs, is tested, and works end to end before the next phase starts. |
| **Well tested** | Every phase includes the tests for its own code (see §8). A phase isn't done until its tests pass. |

### What's out of scope (relative to the current app)

| Feature in the current app | Rebuild decision | Notes |
|---|---|---|
| Activity feed (`FeedPage`, `ActivityFeedWidget`, `api/feed.ts`) | **Removed** | The server still fans out feed events when a workout completes. That's harmless and nothing displays them. |
| Goals (`GoalsPage`, `GoalsWidget`, goal suggestion, onboarding goals step) | **Removed** | Goals that already exist on the server still shape AI generation (the server's `analyzing_goals` step). The app never shows or creates them. |
| Rich profile (stats bar, streak/PR/calendar/recent widgets, gyms section, edit profile sheet) | **Simplified** | The profile shows username, display name, and **Member since** only. |
| Admin (`AdminHomePage`, `BuilderAiConfigPage`, `AdminFloatingButton`) | **Removed** | Admins keep using the web app. |
| Dev tools (`devToolsStore` simulate loading, `?showOnboarding=1`) | **Removed** | |
| Web landing page, `ConfigRequired` screen | **Removed** | Native app only. Configuration is checked at build time instead. |
| **Sign in with Apple** | **Removed** | Production Cognito has **no Apple IdP** (`list-identity-providers` returns `[]`), so the current button can't work. Add it back only once the IdP exists. |
| Keychain shared-credential button (`KeychainPasswordPlugin`) | **Replaced** | Uses standard iOS Password AutoFill (`textContentType`). See §6.11 for what AutoFill can and can't do with the new bundle ID. |
| Exercise catalog browse page, exercise metrics list/detail pages | **Deferred** | Not linked from the core flows. They can come back after v1. |
| Gym management (create/edit/delete gyms) | **Deferred** | Onboarding still creates the first gym, and the builder shows a gym picker that only reads gyms. |
| `TickerMarquee.swift` | **Removed** | Not used anywhere in the current widget. |

---

## 2. Decisions (with recommendations)

Confirmed with the owner on 2026-11-13.

| # | Decision | Choice | Why |
|---|---|---|---|
| D1 | Bundle ID | **`com.rookfitness.app`** (app) and **`com.rookfitness.app.LiveActivity`** (widget extension; the ID must start with the app's ID). Team `2C568CVX27`. A new App Store Connect record named **Rook**. | The existing Repwise app stays installed and working. **No infrastructure changes:** email/password SRP sign-in is a direct call to the `cognito-idp` API and doesn't use a redirect URL. Cognito app clients aren't tied to a bundle ID. API Gateway and the Function URL check the JWT, not the caller's origin (native requests send no `Origin`). The app uses no universal links, so the AASA file doesn't need to list it and there's no Associated Domains entitlement. **Future caveat:** adding Hosted UI / Sign in with Apple later would need `com.rookfitness.app://callback` added to the Cognito client's callback and logout URLs (a one-line CDK change). |
| D2 | Cognito client | **Amplify Swift, Auth plugin only** (`AWSCognitoAuthPlugin`), configured in code and hidden behind a `AuthService` protocol. | The app client only allows **SRP** (`authFlows: { userSrp: true }`), so a plain `InitiateAuth USER_PASSWORD_AUTH` call is rejected. Writing SRP by hand is risky. Amplify also handles token refresh and Keychain storage. |
| D3 | Minimum iOS | **iOS 17.0** (confirmed) | Allows `@Observable`, `NavigationStack` APIs, interactive Live Activity buttons (App Intents, iOS 17), and Swift Testing. The current shell targets 16.2. |
| D4 | Xcode project | **XcodeGen** (`ios-app/project.yml`, `brew install xcodegen`). The generated `.xcodeproj` is git-ignored. | The project file stays reviewable and diff-able, with no `.pbxproj` merge conflicts. App logic lives in a local Swift package, so `swift test` runs most tests without a simulator. |
| D5 | Third-party dependencies | **Amplify Swift only.** Everything else uses system frameworks (URLSession, SwiftUI, ActivityKit, LocalAuthentication, Network, os.Logger). | Smaller attack surface and fewer upgrades to maintain. |
| D6 | Test frameworks | **Swift Testing** (`import Testing`) for unit and integration tests. **XCTest/XCUITest** for UI tests. | Swift Testing is the modern default in Xcode 16. UI automation still requires XCUITest. |
| D7 | Interactive Dynamic Island buttons (Pause/Resume, Next) | **Phase 4b** (after the Live Activity matches today's behavior) | Couldn't be built in Capacitor. Now possible natively and very valuable for the most-used feature. Kept separate so the port itself isn't held up. |
| D8 | App icon and launch screen | **Icon:** the "R" monogram (`packages/web/ios/App/App/Assets.xcassets/AppIcon.appiconset/R-on-black-circle-logo.png`, 1024×1024, white R on a black circle over purple, no wordmark). **Launch screen:** an Info.plist `UILaunchScreen` with the brand background color and the R mark. The Capacitor splash PNGs (generic placeholders) and every "repwise" logo variant are **not** used. | The owner asked for no Repwise branding and may supply new art later. Replacing the icon means swapping one 1024 px PNG in `Rook/Resources/Assets.xcassets/AppIcon.appiconset`. |

---

## 3. Current-app inventory (what gets rebuilt)

This is the full list of what ships today in `packages/web/src`, with where each item lands. **Phase** refers to §7.

### 3.1 Routes / screens

| Web route / screen | Source | Rebuild | Phase | Native screen |
|---|---|---|---|---|
| Login / sign-up / confirm / forgot / reset | `components/LoginDialog.tsx` (657 lines) | **Keep** (minus Apple and Keychain buttons) | 1 | `SignInView`, `SignUpView`, `ConfirmSignUpView`, `ForgotPasswordView`, `ResetPasswordView` |
| Biometric unlock gate | `components/BiometricUnlockGate.tsx`, `lib/biometric*.ts` | **Keep** | 1 | `BiometricLockView` |
| Onboarding | `features/onboarding/OnboardingFlow.tsx` | **Simplify:** equipment step only | 1 | `OnboardingEquipmentView` |
| `/profile` | `features/profile/ProfilePage.tsx`, `ProfileHeader.tsx` | **Simplify** | 1 | `ProfileView` |
| `/settings` | `features/profile/SettingsPage.tsx` | **Keep** (adds a weight unit setting, §6.8) | 1 | `SettingsView` |
| `/dashboard` | `features/dashboard/*`, `components/widgets/*` | **Keep, minus feed and goals** | 2 | `DashboardView` |
| Calendar modal | `components/widgets/CalendarViewModal.tsx` | **Keep** | 2 | `CalendarSheet` |
| `/workouts` (history) | `features/workout/WorkoutsHistoryPage.tsx` | **Keep** (dashboard "See all" and the builder's "past workout" option both need it) | 2 (list), 3 (picker mode) | `WorkoutHistoryView` |
| `/workouts/:id` | `features/workout/WorkoutDetailPage.tsx` | **Keep** | 2 | `WorkoutDetailView` |
| `/workout/new` | `features/workoutBuilder/NewWorkoutScreen.tsx` | **Keep** | 3 | `NewWorkoutView` |
| `/workout/new/ai` | `AIWorkoutScreen.tsx`, `QuickPromptChips.tsx`, `api/aiWorkoutStream.ts` | **Keep** | 3 | `AIWorkoutView` |
| `/workout/new/manual` | `SelectExercisesScreen.tsx` | **Keep** | 3 | `SelectExercisesView` |
| `/workout/review` | `ReviewWorkoutScreen.tsx`, `ReviewExerciseRow.tsx` | **Keep** | 3 | `ReviewWorkoutView` |
| `/workout/execute/:id` | `features/workoutExecution/*` | **Keep (pivotal)** | 4 | `WorkoutExecutionView` |
| Live Activity / Dynamic Island | `packages/web/ios/App/WorkoutLiveActivityExtension/*`, `packages/capacitor-workout-live-activity/*` | **Port (pivotal)** | 4 | `RookLiveActivity` widget extension |
| `/goals`, `/feed`, `/admin*`, `/exercises`, `/metrics*`, landing page | — | Removed or deferred (§1) | — | — |

### 3.2 Components → native equivalents

| Web component | Used by | Native equivalent | Phase |
|---|---|---|---|
| `ui/Button`, `Card`, `Input`, `Badge`, `Spinner`, `Skeleton`, `EmptyState`, `Toast`, `Modal`, `BottomSheet`, `SegmentedControl`, `FilterChip`, `NumberInput`, `ProgressBar`, `Avatar` | everywhere | `DesignSystem/`: `RookButton` styles, `CardContainer`, `RookTextField`, `EmptyStateView`, `.redacted(.placeholder)` skeletons, `ToastCenter`, system `.sheet` / `.confirmationDialog` / `.alert`, `Stepper`-style `NumberStepper`, `ProgressView`, `AvatarView` | 0 |
| `ErrorBoundary`, offline banner (`useOnlineStatus`) | app shell | `ErrorStateView`, `NetworkMonitor` (NWPathMonitor) plus `OfflineBanner` | 0 |
| `DashboardHeader` | dashboard | `DashboardHeader` (greeting + avatar → profile) | 2 |
| `StreakWidget` | dashboard | `StreakCard` | 2 |
| `StatsRow` | dashboard | `StatsRow` (fixes in §6.6) | 2 |
| `PersonalRecordsWidget` | dashboard | `PersonalRecordsCard` | 2 |
| `WeekCalendarWidget` | dashboard | `WeekStrip` | 2 |
| `CalendarViewModal` | dashboard | `CalendarSheet` (month grid + that day's workouts) | 2 |
| `RecentWorkoutsWidget` | dashboard | `RecentWorkoutsCard` | 2 |
| FAB + coach mark | dashboard | Floating "New workout" button (coach mark dropped) | 2 |
| `QuickPromptChips` | AI builder | `QuickPromptChips` ("Push day", "Pull day", "Leg day", "Full body", "30 min quick") | 3 |
| `ReviewExerciseRow` | review | `ReviewExerciseRow` (sets/reps/duration edit, select for regenerate, swap, delete; reorder with `List.onMove`) | 3 |
| `ExecutionHeader` | execution | `ExecutionHeader` (elapsed, pause/resume, cancel, skip) | 4 |
| `WeightEntryCard` | execution | `WeightEntryCard` (keypad entry, ± increments, "Use previous") | 4 |
| `DurationTimerCard` | execution | `DurationTimerCard` (date-driven countdown) | 4 |
| `ExecutionConfirmModal` | execution | `.confirmationDialog` / `.alert` | 4 |
| `WorkoutActivityAttributes`, `LiveSessionTimer`, `CompactLiveSessionTimer`, `ExpandedDynamicIslandTimer`, `WorkoutLiveActivityLiveActivity` | Live Activity | Ported mostly as-is into `RookKit` (attributes) and `RookLiveActivity` (views) | 4 |

### 3.3 Endpoints used by the rebuild

All requests go to `https://api.repwisefit.com` with `Authorization: Bearer <Cognito ID token>`, except the AI stream.

| Endpoint | Used for | Phase |
|---|---|---|
| `GET /users/me` | Session bootstrap, profile, `onboardingCompletedAt`, `weightUnit`, `createdAt` | 1 |
| `PATCH /users/me` | `onboardingCompletedAt`, `defaultGymId`, `weightUnit` (the server accepts `displayName, bio, weightUnit, profilePhoto, defaultGymId, onboardingCompletedAt`) | 1 |
| `DELETE /users/me` | Account deletion, which also removes the Cognito user (**App Store requirement 5.1.1(v)**) | 1 |
| `GET /users/me/gyms` · `POST /users/me/gyms` | Gym picker (read) · onboarding creates "My Gym" | 1 / 3 |
| `GET /metrics/me/global` | Streak, totals, `completedDates` | 2 |
| `GET /metrics/me/exercises` | Personal records | 2 |
| `GET /workout-instances?limit=&nextToken=` | Recent workouts, history (paginated) | 2 |
| `GET /workout-instances/{id}` | Detail, rehydrating execution, "redo past workout" | 2–4 |
| `GET /exercises?muscleGroup=&search=` | Manual builder, swap | 3 |
| `POST <AiWorkoutStreamUrl>` (SSE) | AI generate (`aiPrompt, weightUnit, equipmentTypes, builderSessionId`) and regenerate (`regenerateContext, currentExercises, builderSessionId`) | 3 |
| `POST /workout-instances` | Start workout (`exercises, source, permissionType, gymId, gymName`) | 3 |
| `PATCH /workout-instances/{id}` | Progress autosave (`exercises`), complete (`status: completed`), cancel (`status: cancelled`) | 4 |

---

## 4. Architecture

```
ios-app/
├── project.yml                     # XcodeGen spec (app, widget, test targets, schemes)
├── Config/
│   ├── Shared.xcconfig             # bundle IDs, team, versions, deployment target
│   ├── Production.xcconfig         # API_BASE_URL, AI_STREAM_URL, COGNITO_* (non-secret, same as .env.production.example)
│   └── Local.xcconfig.example      # optional overrides (git-ignored copy)
├── RookKit/                        # Local Swift package: all non-UI logic, testable with `swift test`
│   ├── Package.swift
│   ├── Sources/
│   │   ├── RookModels/             # Codable DTOs matching lambdas/shared/src/models.ts + enums.ts
│   │   ├── RookNetworking/         # APIClient, Endpoint, SSEClient/SSEParser, APIError, retry policy
│   │   ├── RookAuth/               # AuthService protocol, AmplifyAuthService, TokenProvider
│   │   ├── RookSession/            # WorkoutSession engine (wall-clock timer, pause ledger, duration segments), persistence
│   │   ├── RookLiveActivityKit/    # WorkoutActivityAttributes + ContentState builder (shared with widget)
│   │   └── RookFormatting/         # Volume, durations, relative dates, weight units, UTC day keys
│   └── Tests/                      # Swift Testing suites per module
├── Rook/                           # App target (SwiftUI)
│   ├── App/                        # RookApp, AppModel (root state machine), dependency container
│   ├── DesignSystem/               # Colors, typography, components
│   ├── Features/
│   │   ├── Auth/  Onboarding/  Profile/  Settings/
│   │   ├── Dashboard/  History/
│   │   ├── Builder/  Execution/
│   ├── Services/                   # LiveActivityController, BiometricService, NetworkMonitor, Repositories
│   └── Resources/                  # Assets.xcassets (icon, colors), Info.plist, PrivacyInfo.xcprivacy, Rook.entitlements
├── RookLiveActivity/               # Widget extension (ported views)
├── RookTests/                      # App-target unit tests: view models, repositories (Swift Testing)
└── RookUITests/                    # XCUITest smoke flows
```

**Patterns**

- **MVVM with `@Observable`.** Each feature has a `…ViewModel` that only talks to protocols (`AuthService`, `WorkoutsRepository`, `MetricsRepository`, `ExercisesRepository`, `GymsRepository`, `UsersRepository`, `AIWorkoutStreaming`, `LiveActivityControlling`, `Clock`). Production implementations live in the app or RookKit. Fakes live **only** in test targets.
- **Root state machine** (`AppModel.phase`): `launching → signedOut → locked (biometric) → onboarding → ready(user)`. Phase 1 builds and tests this.
- **Networking:** `async/await` URLSession and a single `APIClient` that adds the ID token, decodes with snake/camel-safe `Codable`, maps `{ error: string }` bodies to `APIError.server(message)`, and retries 5xx/network errors with backoff `1s/2s/4s` (same as `api/client.ts`). On 401 it refreshes the session once, then signs out.
- **SSE:** `URLSession.bytes(for:)` feeds a pure `SSEParser` (event/data framing, unit tested against recorded payloads). Events are `progress {step, message}`, `complete {exercises}`, `error {message}`.
- **Clock injection:** all timer math takes a `Clock`/`now` so it can be tested deterministically.
- **Logging:** `os.Logger` with subsystem `com.rookfitness.app`. Never log tokens, emails, or workout notes.

**Theme (unchanged colors):** primary `#7C3AED` (light `#8B5CF6`, dark `#6D28D9`), accent orange `#F97316`, accent green `#22C55E`, surface `#FFFFFF` / `#F8F7FF`, execution background `#0F0F1A`. The web app uses DM Sans/DM Mono. v1 uses SF Pro with `.rounded` for numbers, so no fonts need bundling. Bundling DM Sans can be revisited later. App icon and launch screen: see D8 (the "R" monogram, no wordmark).

---

## 5. The pivotal feature: workout session + Live Activity

This feature is designed first, even though it's built in Phase 4, because the session model it depends on is built earlier, in Phase 0.

### 5.1 Session engine (`RookSession`)

This is a direct port of `stores/workoutSessionStore.ts`, as value types:

```swift
struct WorkoutSessionState: Codable, Equatable {
  var workoutId: String
  var displayName: String?          // gym name / notes / "Workout"
  var exercises: [WorkoutExercise]
  var currentIndex: Int
  var startedAt: Date
  var isPaused: Bool
  var totalPausedMs: Int
  var pauseStartedAt: Date?
  var durationSegment: DurationSegment?   // exerciseIndex, running, startedAt, accumulatedSeconds
}
```

- Pure functions `elapsedSeconds(at:)` and `durationElapsedSeconds(at:)` mirror `computeSessionElapsedSeconds` and `computeDurationElapsedSeconds` exactly, including the clamp to the target duration.
- Mutations: `start`, `updateExercise`, `goTo`, `pause`, `resume`, `startDuration`, `pauseDuration`, `skip`, `clear`. Each one is a pure state transition and is unit tested.
- **Persistence:** after every mutation the state is written as JSON in Application Support, using atomic writes. On launch, a stored session takes the user straight back to Execution and the Live Activity is rebuilt. This replaces zustand `persist`.
- **Autosave:** exercise changes are debounced 500 ms into `PATCH /workout-instances/{id} {exercises}`, as on the web. Failures are queued and retried, never silently dropped.
- **Complete:** `PATCH {status: completed, exercises}`. If it **fails, the session is kept** and the user sees an error with Retry. The web app currently clears the session even when the request fails, which loses the workout. That bug is deliberately not ported.
- **Cancel:** `PATCH {status: cancelled}`, then clear the session and end the Live Activity.

### 5.2 Live Activity

- **Port from:** `packages/capacitor-workout-live-activity/ios/Sources/WorkoutActivityKit/WorkoutActivityAttributes.swift` and `packages/web/ios/App/WorkoutLiveActivityExtension/{WorkoutLiveActivityLiveActivity,LiveSessionTimer,WorkoutLiveActivityBundle}.swift`.
- **Keep the proven design:** timers use `Text(date, style: .timer)` anchored at `startedAt + totalPausedMs`. Don't use `TimelineView`, because WidgetKit throttles it in the background (see the comment in `LiveSessionTimer.swift`). Keep the compact trailing column at 56 pt, the expanded center timer with `.belowIfTooWide`, and the single-line bottom caption.
- **Improvements over the port:**
  - `ContentState` stores `Date`s directly (not ISO strings) and a typed `modality` enum. A `ContentStateBuilder` in `RookLiveActivityKit` (shared and unit tested) replaces `workoutLiveActivityPayload.ts`.
  - The weight unit comes from the exercise or profile, not a hard-coded `LBS` (§6.8).
  - The fallback subtitle reads "Rook". The duration exercise shows a **live countdown** (`Text(timerInterval:countsDown:)`) instead of a static "Ns left".
  - The pause state shows the frozen elapsed time and a "Paused" label.
- **`LiveActivityController`** (app target, behind the `LiveActivityControlling` protocol):
  - `start(session)` ends any existing `Activity<WorkoutActivityAttributes>` for that workout (as the plugin does today), then requests a new one.
  - `update(session)` runs **on state changes only**. Polling isn't needed because the timers are date-driven. Updates are coalesced to at most one per second.
  - `end()` runs on complete or cancel.
  - On launch: `reconcile(storedSession)` ends orphaned activities when there's no stored session, and re-adopts or rebuilds the activity when there is one. This handles the force-quit case from `dynamic-island-spec.md` without server push.
  - If Live Activities are disabled, the workout still runs. The user sees a one-time inline tip ("Enable Live Activities in Settings → Rook").
- **Phase 4b, interactive controls (iOS 17):** `LiveActivityIntent`s for **Pause/Resume** and **Next exercise** in the expanded island and on the lock screen. They run in the app process, change `WorkoutSession`, persist it, autosave, and update the activity, all through the same code path the UI uses.
- **Out of scope:** APNs push-to-end (needs backend work, which is out of scope here).

---

## 6. Backend quirks the app must handle (no backend changes)

1. **SRP-only Cognito client** → Amplify Swift (D2). Pool `us-east-1_9jr8u8h37`, client `3aatm24d4c0r2qtt57jnfoutod`. The password policy is min 8 characters with upper, lower, and digit, no symbol required. The client validates this before calling Cognito.
2. **The API and the AI stream both expect the ID token** (`tokenUse: 'id'` in `lambdas/ai`). Send the ID token, not the access token.
3. **`GET /workout-instances?status=` filters *after* `Limit`** (`lambdas/workout`). A `status=completed&limit=50` page can come back with fewer items than expected, or none. The app pages **without** `status` and filters on the client. To detect an active workout it relies on the locally stored session, not on the server.
4. **Exercise PATCH merges by `exerciseId`**, so one exercise appearing twice in a workout would collide. The builder **must not allow duplicate exercises**. Manual select already blocks this, and swap and regenerate must too.
5. **Completion validation:** every non-skipped `sets_reps`/`burnout` exercise needs `weight`, and `duration` exercises need `durationSeconds`. Bodyweight work sends `weight: 0`. The Complete button is disabled with an explanation until these rules are met, so the user never hits a 400.
6. **Dashboard stats as computed today are wrong.** "Volume · 30d" is summed over a 90-day, 50-workout window, and "This Month" is really `workoutsLast30`. The rebuild labels them **"Last 30 days"** and computes volume and minutes from completed workouts whose `completedAt` falls in the last 30 days (paging as needed).
7. **`completedDates` are UTC `YYYY-MM-DD` strings** (`metrics-processor` uses `toISOString()`), so a late-evening workout in a US time zone lands on the next day. The week strip (and the home-screen widgets built from it) therefore ignores `completedDates` and places each loaded workout on the **local** calendar day of its `completedAt` (fixed 2026-11-21; it used to compare by UTC day key, which showed a Tuesday-night sauna on Wednesday). The exercise "last performed" label still uses a server UTC day key, since the API returns no timestamp for it; that needs the backend change.
8. **Weight units:** profiles have a `weightUnit` (`LBS`/`KG`), but the web app hard-codes `LBS` everywhere. The rebuild reads the profile unit for input, display, and the AI request (`weightUnit`), and stores `weightUnit` on each exercise it writes. Settings offers a unit picker (`PATCH /users/me {weightUnit}`, which the server already supports). PRs show each exercise's own `maxWeightUnit`.
9. **Gyms:** onboarding creates "My Gym" with the selected equipment types, then PATCHes `defaultGymId` and `onboardingCompletedAt`. The equipment IDs are `dumbbells, free_weights, cables, weight_rack, cardio, machines`, with presets commercial, home, and minimalist.
10. **AI stream:** there are five `progress` steps (`analyzing_goals, reviewing_history, scanning_catalog, balancing_muscles, optimizing_structure`). The app **shows the `message` the server sends** rather than hard-coded labels. The generation request has a 120 s Lambda timeout, and the client uses a 130 s timeout plus a Cancel button.
11. **Password AutoFill:** the app has no associated domain, so iOS won't automatically suggest passwords saved for repwisefit.com. Fields use `.username` / `.password` / `.newPassword` content types, so the keyboard's password key still opens Passwords, and iOS offers to save credentials after sign-in. Domain-matched suggestions would need a `webcredentials` entry for the new app ID in the AASA file (a CDK change), which this plan doesn't make.
12. **`permissionType`:** new workouts are sent as `FOLLOWERS_ONLY` (the current default). No UI exposes it.

---

## 7. Phased build

Each phase lists its scope, screens, the tests it must add, and its **exit criteria**. A phase merges only when `make test` is green and its exit criteria are demonstrated on a device.

### Phase 0 — Foundation

**Scope:** project skeleton, design system, networking and auth plumbing, session engine, CI script. No screens yet beyond a launch screen.

- `project.yml` with targets **Rook** (app), **RookLiveActivity** (widget, an empty bundle for now), **RookTests**, **RookUITests**, and the local package **RookKit**. Schemes **Rook** (Debug/Release).
- `Config/*.xcconfig` → Info.plist keys (`API_BASE_URL`, `AI_STREAM_URL`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `COGNITO_REGION`). The app **fails fast at launch** with a clear fatal log if any key is missing. (This is a build error, not a user-facing screen.)
- `RookModels`: Codable types for `UserProfile`, `Gym`, `GymsListResponse`, `ExerciseCatalogItem`, `WorkoutExercise`, `WorkoutInstance`, `WorkoutListPage`, `GlobalMetrics`, `ExerciseMetrics`, `PRRecord`, and the enums. Decoding tolerates unknown enum values and missing optional fields.
- `RookNetworking`: `APIClient`, `Endpoint`, retry policy, `APIError`, `SSEParser`, `SSEClient`.
- `RookAuth`: the `AuthService` protocol and `AmplifyAuthService`.
- `RookSession`: the session engine (§5.1) and its persistence.
- `RookFormatting`: formatters (volume `1.2K`/`3.4M`, `mm:ss`, relative dates "Today/Yesterday/N days ago", weight units, UTC day keys).
- `DesignSystem`: colors (light and dark), buttons, cards, text fields, empty and error states, skeletons, toasts, offline banner.
- `Makefile`: `make generate` (xcodegen), `make test` (RookKit `swift test` plus `xcodebuild test` on an iPhone 16 Pro simulator), `make lint` (SwiftFormat/SwiftLint if adopted), `make archive`.
- Assets: app icon (D8), accent color, and the launch screen. `make lint` includes the no-"repwise" brand check (§1). `PrivacyInfo.xcprivacy` (declares UserDefaults and file timestamp API reasons; collected data = email and fitness data, linked to the user, not used for tracking).

**Tests:** model decoding against real fixture JSON captured from each endpoint (with PII scrubbed), `APIClient` (auth header, error mapping, retry/backoff, 401 refresh-then-sign-out) using a `URLProtocol` stub, `SSEParser` (split chunks, multiple events per chunk, trailing event, malformed data), session engine (elapsed time with and without pauses, pause during a duration segment, clamping, goTo resetting the duration, Codable round-trip), and formatters.

**Exit:** `make generate && make test` passes from a clean clone. The app launches on the simulator and the device with Rook branding.

### Phase 1 — Sign in, sign out, onboarding, profile, settings

**Screens**

- **Sign in:** email and password, show/hide password, "Forgot password?", "Create account". Inline validation (email format), Cognito errors mapped to friendly messages (`UserNotConfirmedException` → goes to confirm, `NotAuthorizedException` → "Incorrect email or password").
- **Sign up → Confirm code:** password rules shown up front, confirm password, resend code.
- **Forgot → Reset:** code, new password, confirm.
- **Biometric lock:** opt-in from Settings. On cold launch or foregrounding after more than N minutes, `LAContext` with device-passcode fallback, plus "Use password instead" (signs out). The preference is stored in UserDefaults (`rook.biometricUnlockEnabled`).
- **Onboarding (equipment only):** shown when `GET /users/me` returns no `onboardingCompletedAt`. Choose presets or toggle equipment, then `POST /users/me/gyms {name: "My Gym", equipmentTypes}` → `PATCH /users/me {defaultGymId, onboardingCompletedAt}`. "Skip" uses all equipment.
- **Profile:** large header with **@username**, **display name**, and a **Member since** card (from `createdAt`, formatted "March 2026"). A toolbar gear opens Settings. Nothing else.
- **Settings:** weight unit (LBS/KG), Face ID/Touch ID toggle (only shown when the device supports it), **Sign out**, **Delete account** (confirmation that must be acknowledged → `DELETE /users/me` → sign out → back to Sign in), and app version/build.
- **Dashboard placeholder?** **No.** Phase 1 ends on a minimal signed-in root that is the Profile screen. Phase 2 swaps in the dashboard as the root, so nothing fake ships.

**Tests:** `AppModel` state machine (each transition, including a 404 profile → error with retry, and an expired session → signedOut), every auth view model (validation, error mapping, loading states), onboarding (gym create → patch order, and a patch failure after the gym is created → retry patches without creating a second gym), profile formatting, settings (unit change PATCH and rollback on failure, delete flow), and biometric gating policy. **UI smoke (XCUITest):** launch → sign-in form present and validates.

**Exit:** on a device, a real account can sign up, confirm, sign in, onboard, view the profile, change units, sign out, sign back in, use biometric unlock, and delete a throwaway account.

### Phase 2 — Dashboard (+ history read-only)

**Data:** `GET /metrics/me/global`, `GET /metrics/me/exercises`, `GET /workout-instances` (paged, filtered to completed on the client, see §6.3), loaded in parallel. Loads on appear, on **pull to refresh**, and when the app returns to the foreground. This replaces the 30 s polling. Overlapping loads share one request, and a cancelled refresh (SwiftUI cancels `.refreshable` when the view updates mid-refresh) is never shown as an error.

**Screen (top to bottom)**

1. **Header:** "Welcome back" + display name, avatar (initials; `profilePhoto` URL if present) → Profile.
2. **Streak card:** current streak and best (`currentStreak`, `longestStreak`).
3. **Stats row:** Workouts (last 30 days, sauna sessions excluded) · Sauna sessions (last 30 days) · Steps today. The 30-day window is corrected per §6.6. The total-workouts tile was removed when sauna sessions were added.
   - **Steps today** tile (rightmost): today's count from the device pedometer (CoreMotion `CMPedometer`, `NSMotionUsageDescription`), live while the dashboard is in the foreground and reset at local midnight. Shows "—" when the device has no pedometer; when Motion & Fitness access is off it reads "Off · Enable steps" and opens the app's Settings page. Device-only data: nothing is sent to the backend.
4. **Personal records:** top 5 by `maxWeight` with each exercise's own unit and session count. Hidden when empty.
5. **This week strip:** Mon–Sun local days, filled from the loaded workouts by the local day of `completedAt` (§6.7). Each day's icon shows what was done: a dumbbell for one workout, an orange flame for one sauna session, and a checkmark for more than one session. Tap → **Calendar sheet** (month navigation, workout days marked, tap a day → that day's workouts → detail).
6. **Recent workouts:** latest 5, each showing the first exercise names, count, minutes, relative date, and volume in the user's unit. "See all" → **History**. When empty: "No workouts yet", plus a "Start a workout" button that goes to the builder in Phase 3 and is hidden until then.
7. **Active workout banner** (only when a stored session exists): "Workout in progress · 12:34 · Resume" → Execution. The banner itself is built in Phase 4. Phase 2 reserves the slot.
8. **Floating "New workout" button:** added in Phase 3, when the builder exists.

**History:** paginated list (infinite scroll using `nextToken`) → **Workout detail** (date, duration, gym, total volume, exercises with sets×reps@weight or duration, skipped exercises marked).

**States:** a skeleton while loading, an error card with Retry, empty states for each card, and the offline banner.

**Tests:** dashboard view model (aggregation, 30-day windowing across page boundaries, PR sorting and unit handling, local-day week mapping, including late-evening sessions near UTC midnight, the Sunday→Monday edge and the year boundary), calendar month grid generation, history pagination (dedupe, end of list), and detail volume math. **Snapshot-free UI test:** the dashboard renders its sections against a test account (§8.3).

**Exit:** the dashboard matches the web app's numbers for the same account, except for the intentional fixes in §6.6, and the calendar, history, and detail screens work.

### Phase 3 — Workout building

**Screens**

- **New workout:** gym picker (from `GET /users/me/gyms`, defaulting to `defaultGymId`), then three options: **AI Generate**, **Manual Build**, **Choose from past workout**.
- **AI Generate:** multi-line prompt, quick-prompt chips, Generate → a progress list driven by the server's `progress` messages → the Review screen. Sends `aiPrompt`, `weightUnit`, the gym's `equipmentTypes`, and a client-generated `builderSessionId` (UUID) that's kept for regenerate calls. Supports Cancel and error retry.
- **Manual Build:** search (debounced 300 ms) plus muscle-group chips (`chest, back, shoulders, biceps, triceps, quadriceps, hamstrings, glutes, core`), catalog list with add/check, and a selected tray with sets/reps or duration steppers (defaults 3×8 / 60 s, or the catalog's defaults). Duplicates are blocked (§6.4).
- **Choose from past workout:** History in picker mode → copy the exercises (reset to `skipped=false`, re-number `orderIndex`) → Review as `manual`.
- **Review:** editable rows (sets, reps, duration), drag to reorder, swipe to delete, **Swap** (catalog sheet without duplicates), **Edit in manual builder**, and for AI drafts **select rows → Regenerate** (sends `regenerateContext {exerciseIndices, currentExerciseIds, targetMuscleGroups, userPrompt, equipmentTypes}` + `currentExercises`). The gym can be changed here. **Start workout** → `POST /workout-instances` → creates the session → Execution.
- The draft lives in memory only, owned by `BuilderFlowModel`. Abandoning the builder discards it, matching the web app.

**Tests:** builder flow model (manual add/remove/duplicate block/defaults, swap, reorder `orderIndex` renumbering, past-workout copy, edit in manual), AI view model with a fake `AIWorkoutStreaming` (progress sequencing, complete, error, cancel, timeout, empty result → friendly error), the regenerate request body, the start-workout request body (`source`, `gymId/gymName`, `permissionType`), and an SSE end-to-end test against recorded stream fixtures.

**Exit:** on a device, all three build paths produce a started workout on the real backend, visible on the web app as in-progress.

### Phase 4a — Workout execution + Live Activity (pivotal)

**Execution screen** (dark `#0F0F1A`, as on the web):

- **Header:** elapsed `mm:ss` (date-driven `Text(timerInterval:)`, so it never drifts), Pause/Resume, Cancel (confirmation: "Your progress will not be saved"), Skip.
- **Progress:** "Exercise N of M" plus a progress bar.
- **"Last" chip:** `lastUsedWeight` in its unit, `sets×reps`, and the relative `lastPerformedDate` (when present).
- **Exercise title** plus its target ("3 sets × 8 reps" / "60 seconds").
- **Sets/reps/burnout → `WeightEntryCard`:** a numeric field prefilled from the current weight, else the last-used weight. ± steps of 5 lb / 2.5 kg. "Use previous". Haptics on change.
- **Duration → `DurationTimerCard`:** start/pause countdown backed by the session's duration segment, then auto-advances or asks "Done" when it reaches 0. Writes `durationSeconds` and `weight: 0`.
- **Footer:** Previous / Next. The last exercise turns Next into **Complete** → a confirmation summary (time, exercises, skipped count) → `PATCH completed` → success haptic → Dashboard (refreshed). On failure: keep the session, show an error, offer Retry (§5.1).
- **Keyboard:** a decimal pad with a toolbar Done button. The screen stays awake while a workout is active (`isIdleTimerDisabled`), and that's reverted on exit.

**Lifecycle:** start → persist → start the Live Activity. Every mutation → persist → debounced autosave → coalesced Live Activity update. scenePhase `.active` → re-sync. Cold launch with a stored session → Execution, plus the dashboard Resume banner. Complete or cancel → clear the session and end the Live Activity.

**Live Activity:** §5.2, ported, with the listed improvements.

**Tests:** execution view model with a fake clock, fake repository, and fake `LiveActivityControlling` (next/prev/skip, weight parsing and locale decimals, completion validation, complete success/failure/retry, cancel, autosave debounce and retry queue, rehydration from GET when the stored session doesn't match, Live Activity calls on start/update/end, no updates while unchanged). `ContentStateBuilder` tests (sets/reps vs duration, paused state, countdown end date, unit passthrough, empty workout name). **Widget view tests:** render each Live Activity presentation (lock screen, compact, expanded, minimal) for sets/reps, duration, and paused states via `ImageRenderer`, and assert they don't crash and fit their size bounds. **Manual device checklist** (can't be automated in a simulator): Dynamic Island on an iPhone 14 Pro or newer, lock screen ticking for over 10 minutes while locked, pause freezing the timer, app kill → relaunch reconciles, Live Activities disabled → workout still works.

**Exit:** a full workout runs on a device with the phone locked for most of it. The Dynamic Island and lock screen stay accurate throughout, the completed workout shows up on the dashboard and web app, and metrics update via the stream processor.

### Phase 4b — Interactive Live Activity (iOS 17)

**Scope:** `PauseResumeIntent` and `NextExerciseIntent` (`LiveActivityIntent`) as buttons in the expanded island and lock screen. Both share the `WorkoutSessionController` used by the UI.

**Tests:** intent → controller → persisted state → autosave → activity update, through the same fakes as 4a.

**Exit:** pause and advance work from the lock screen without opening the app, and the app reflects the change when it's opened.

### Phase 5 — Release readiness and TestFlight

- **Accessibility:** Dynamic Type up to XXL on every screen, VoiceOver labels on icon buttons, sufficient contrast in dark mode.
- **Reliability:** full pass with network-loss simulation (Network Link Conditioner), plus token expiry while a workout is running (refresh, so autosave keeps working).
- **App Store metadata:** name "Rook", subtitle, privacy nutrition labels matching `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption = NO`, support URL, and the account deletion path documented for review.
- Version and build numbering (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` via `agvtool` or the xcconfig).
- See §9 for the build and upload runbook.

---

## 8. Testing strategy

You haven't written Swift tests before, so this section explains the approach.

### 8.1 Layers

| Layer | Framework | Where | What | Runs on |
|---|---|---|---|---|
| **Unit (logic)** | Swift Testing | `RookKit/Tests/*` | Models, networking, SSE, session engine, formatters, ContentState builder | `swift test` (macOS, no simulator; fast) |
| **Unit (feature)** | Swift Testing | `RookTests/` | View models and repositories with fake services | iOS Simulator via `xcodebuild test` |
| **Widget rendering** | Swift Testing + `ImageRenderer` | `RookTests/LiveActivity*` | Each Live Activity presentation renders for every state | Simulator |
| **UI smoke** | XCUITest | `RookUITests/` | Launch, sign-in validation, and (opt-in, §8.3) signed-in dashboard, build → start → complete | Simulator |
| **Manual device** | Checklist | This spec, Phase 4a | Dynamic Island and lock screen behavior that simulators can't reproduce reliably | Physical iPhone |

### 8.2 Conventions

- Every service is a protocol, and view models get their dependencies through `init`. Tests inject **fakes** (hand-written structs that record calls and return canned results). There's no mocking library.
- Network fixtures are real JSON responses captured from the API (with PII scrubbed) under `RookKit/Tests/Fixtures/`. If the backend's shape changes, decoding tests fail first.
- Time is always injected (`Clock`, or `now: () -> Date`). Tests never sleep.
- A Swift Testing example, for orientation:

  ```swift
  @Test func pausedTimeIsExcludedFromElapsed() {
    var s = WorkoutSessionState.fixture(startedAt: t0)
    s.pause(at: t0 + 60)
    s.resume(at: t0 + 90)
    #expect(s.elapsedSeconds(at: t0 + 120) == 90)
  }
  ```

- **Coverage targets** (Xcode code coverage, enforced in `make test` via `xccov`): **≥ 90%** for `RookSession` and `RookLiveActivityKit`, **≥ 80%** for the rest of RookKit, **≥ 70%** for view models. Views and layout are covered by UI smoke tests and the device checklist, not by line coverage.

### 8.3 Tests against the real backend

UI flows past sign-in need a real account. They use the **existing integration-test user** (`TEST_USER_EMAIL`/`TEST_USER_PASSWORD` from `packages/integration-tests/.env.test`) passed in as test-runner environment variables. Credentials are **never** committed or compiled into the app. These tests write real workouts, so they're **opt-in** (`make uitest-live`) and never part of the default `make test`. Ask before running them.

---

## 9. Build and deploy (TestFlight) runbook

Phase 5 walks through this together. It's summarized here so the prerequisites can be sorted out early.

**One-time setup**

1. `brew install xcodegen` (plus `swiftlint`/`swiftformat` if adopted).
2. Apple Developer account for team **2C568CVX27**. Xcode → Settings → Accounts → signed in.
3. Register **new** App IDs in Certificates, Identifiers & Profiles: `com.rookfitness.app` and `com.rookfitness.app.LiveActivity`. No extra capabilities are needed: Live Activities only need `NSSupportsLiveActivities` in Info.plist, and there are no Associated Domains or Push for v1. With automatic signing, Xcode can register these itself the first time you build to a device.
4. App Store Connect → **New App**: name **Rook**, bundle ID `com.rookfitness.app`, SKU e.g. `rook-ios`. Create an internal TestFlight group. The existing Repwise record isn't touched.

**Each build**

```bash
cd ios-app
make generate                                  # xcodegen
make test                                      # must be green
# bump CURRENT_PROJECT_VERSION in Config/Shared.xcconfig
make archive                                   # xcodebuild archive -scheme Rook -configuration Release
make export                                    # xcodebuild -exportArchive with ExportOptions.plist (app-store-connect)
# Upload: Xcode Organizer → Distribute App → TestFlight, or
xcrun altool --upload-app -f build/Rook.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

Automatic signing is used throughout. Fastlane is unnecessary at this size. It can be added later along with CI.

---

## 10. Risks and open questions

| Risk | Mitigation |
|---|---|
| Amplify Swift adds a large dependency and has its own release cycle | Isolated behind `AuthService`. It can be swapped for a custom SRP client later without touching features. |
| Both apps are installed and signed in to the same account, and a workout is started in each | The server allows several in-progress workouts, so nothing corrupts, but each app shows its own Live Activity. Rook only resumes sessions it started. Don't run workouts in both apps at once during the transition. |
| UTC `completedDates` show the wrong day for late-evening workouts | The week strip uses local days from `completedAt` instead (§6.7). Server-only day keys (exercise "last performed") still need a backend fix that stores the client's local date. |
| Live Activity left behind after force-quit | Reconcile on launch (§5.2). Push-to-end needs backend work and is out of scope. |
| `GET /workout-instances` status filtering returns sparse pages | The client filters and pages (§6.3). |
| The web app and the native app write the same records | They share the same API contract. The native app never writes fields the web app doesn't know about. |

**Open questions:** none blocking Phase 0. Final Rook artwork, if the owner provides it, replaces the D8 icon and needs no code changes.


## Sauna sessions

Added 2026-11-14. Sauna is modelled inside the existing workout structure, with **no new backend types or endpoints**:

- **Catalog:** `recovery-sauna` ("Sauna"), modality `duration`, muscle group `recovery`, equipment `sauna`, default 20 min (`packages/lambdas/exercise/scripts/full-exercise-database.json`).
- **Logging:** Builder → **Sauna** (under "Repeat a past workout") → choose minutes → Complete. This calls `POST /workout-instances` with one Sauna exercise (`durationSeconds = minutes × 60`, `sets = 1`), then `PATCH … status=completed`. If completing fails, the new workout is cancelled. There's no execution screen and no Live Activity.
- **Recognition:** a workout counts as a sauna session when every non-skipped exercise is Sauna (`Sauna.isSaunaWorkout`). Its minutes come from the exercise duration, because the server's `durationMinutes` is ~0 for a logged session.
- **Side effects of using the existing structure:** sauna sessions count toward the server's streak, `totalWorkouts`, and `completedDates`, and they appear in the feed and in history like any workout. Quick start in the builder leaves them out. The AI builder sees Sauna in the catalog, so it could pick it.

## Home-screen widgets

Added 2026-11-14. Four widgets live in the existing widget extension (`RookLiveActivity`, alongside the Live Activity):

| Widget | Family | Shows |
|---|---|---|
| Overview | Medium | Workouts · 30d, Saunas · 30d and Steps today in one compact row above the week strip (no titles) |
| Steps | Small | Steps today |
| This Week | Medium | The week strip (dumbbell / flame / checkmark), no title |
| Stats | Small | Workouts · 30d, Saunas · 30d, Steps today, stacked |

- **Data flow:** the extension has no session and never calls the API. After each dashboard change the app writes a `DashboardSnapshot` (30-day counts, this week's day activities, and the last step count) as JSON to the App Group `group.com.rookfitness.app` (`RookWidgetData`). `WidgetSync` reloads the timelines only when the figures change, not on every step. Signing out deletes the snapshot.
- **Steps:** the widget reads today's count from CoreMotion itself when Motion & Fitness access is already granted, and otherwise falls back to the app's last count for today. Timelines refresh every 15 minutes and just after midnight, when the week and steps roll over.
- **Staleness:** the 30-day counts and the week only update when the app loads the dashboard. A session logged on the web shows up in the widget the next time the app is opened.
