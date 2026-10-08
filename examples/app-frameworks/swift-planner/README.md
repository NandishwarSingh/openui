# Planner: a SwiftUI app on OpenUI

A planning assistant for iPhone, iPad and Mac built on [`packages/swift-lang`](../../../packages/swift-lang). Answers stream from OpenUI Cloud and render as native SwiftUI views, and their data comes from tools that run on the device: your calendar and reminders, Apple Maps, Wikipedia and Wikimedia Commons photos, and an Open-Meteo forecast. It also adds a few components only a native app can offer: a map, a day timeline, a camera field and a Razorpay pay button.

It's here to show the Swift package in a real app, so it uses more than an example needs: tools, native components, payments, persistence and UI tests.

<img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/kathmandu.gif" width="300" alt="Planning a trip to Kathmandu: the answer streams in, then photos, hotels, sights and the map">

A real answer to "Plan me a trip to Kathmandu" (iPhone simulator, sped up). The forecast, hotels, sights and photos come from the tools on the device.

| | | | |
|---|---|---|---|
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/light-answer.jpg" width="200" alt="Forecast and itinerary"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/light-hotels.jpg" width="200" alt="Hotels from Apple Maps"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/light-sights-map.jpg" width="200" alt="Sights from Wikipedia and a map"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/light-map.jpg" width="200" alt="The map full screen"> |
| Forecast and itinerary | Hotels from Apple Maps | Sights from Wikipedia, with a map | The map, full screen |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/light-food.jpg" width="200" alt="Food photos from Wikimedia Commons"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/dark-answer.jpg" width="200" alt="Dark mode"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/dark-sights-map.jpg" width="200" alt="Dark mode sights and map"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/dark-food.jpg" width="200" alt="Dark mode food photos"> |
| Food photos from Commons | Dark mode | | |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/pay-checkout.jpg" width="200" alt="Razorpay checkout"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/pay-bank.jpg" width="200" alt="Razorpay test bank"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/ipad.jpg" width="330" alt="iPad"> | |
| Razorpay checkout (test mode) | Its test bank | iPad | |

## Prerequisites

- Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node.js 20.19+ for the small backend
- An OpenUI Cloud API key from the [Thesys console](https://console.thesys.dev/keys)
- Optional: Razorpay test keys, for the pay button

## Run

Start the backend. It keeps the keys off the device and proxies chat to OpenUI Cloud:

```bash
cd examples/app-frameworks/swift-planner/server
cp .env.example .env   # add THESYS_API_KEY, and the Razorpay test keys if you want payments
node server.mjs
```

Generate the Xcode project and run the `Planner` scheme on an iPhone or iPad simulator, or on My Mac:

```bash
cd examples/app-frameworks/swift-planner
xcodegen generate
open OpenUIPlanner.xcodeproj
```

The app talks to `http://localhost:8787`. On a phone, set the server address in Settings to your Mac's name ending in `.local` (the server prints it when it starts).

The simulator needs a location for the "near me" questions: Features → Location in the Simulator menu, or `xcrun simctl location booted set 12.9716,77.5946`.

## What's where

- `Sources/Chat`: the conversation, streaming and paced text, and how component actions become messages
- `Sources/Library`: the component library (the chat library plus `Map`, `DayTimeline`, `CameraField`, `PayButton`) and the system prompt
- `Sources/Tools`: the tools behind `Query` and `Mutation`, with results saved per message so a reopened chat doesn't run them again
- `Sources/Payments`: Razorpay's native checkout on iOS and its web checkout on the Mac, with the server verifying every payment
- `server/server.mjs`: the backend, with no dependencies

## Tests

The UI tests replay recorded answers, so they don't spend model calls. Run the replay server next to the normal one, then the tests:

```bash
cd examples/app-frameworks/swift-planner/server
PORT=8788 REPLAY=recordings/replays.json node server.mjs
```

```bash
xcodebuild test -project OpenUIPlanner.xcodeproj -scheme Planner \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skip-testing:PlannerUITests/LiveFlowTests -skip-testing:PlannerUITests/DemoVideoTests
```

`LiveFlowTests` talk to the model and spend a few calls each; run them on purpose.

Payments use Razorpay's test mode: the checkout is real, no money moves.

Photo credit: `media/bangalore-palace.jpg`, see `media/CREDITS.txt`.
