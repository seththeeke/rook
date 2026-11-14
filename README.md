# Rook

**Train smarter. Get stronger.** · **[Open Rook on the web](https://repwisefit.com)**

Rook is a fitness app for building and running workouts. Build a workout with AI or by hand (or restart a recent one in a tap), log every set mid-workout, and watch your streaks and personal records update automatically.

---

## What you can do

- **Build workouts**: describe what you want ("upper body, 45 min") and let AI pick exercises for your gym's equipment, choose from the exercise catalog yourself, or repeat a past workout.
- **Quick start**: restart a recent workout with one tap, with the same exercises, sets and reps and no setup.
- **Log as you go**: your last weight is pre-filled. Adjust it with quick buttons (−5, +5, +10, +25, +50), handle timed exercises with a countdown, and progress saves even if you close the app.
- **Live Activity**: on iPhone, the session timer and current exercise stay on the Lock Screen and Dynamic Island, with Pause and Next buttons.
- **Track progress**: streaks, workout counts, per-exercise PRs, and your workout history update automatically after every session.

---

## Apps

| | |
|---|---|
| **iOS** (`ios-app/`) | Native SwiftUI app with the Live Activity / Dynamic Island. See [ios-app/README.md](ios-app/README.md) and the [rebuild plan](specs/ios-native-rebuild-plan.md). |
| **Web** (`packages/web/`) | React app served at [repwisefit.com](https://repwisefit.com); also includes goals and the social feed. |

Both use the same serverless backend.

---

## Tech

React, SwiftUI, TypeScript, Swift, AWS (Lambda, API Gateway, DynamoDB, Cognito, CloudFront), and Amazon Bedrock for AI workout generation. See **[DEPLOYMENT.md](DEPLOYMENT.md)** for setup, deployment, and development details.

---

## License

Proprietary. All rights reserved.
