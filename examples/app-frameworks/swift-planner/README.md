# Planner: a SwiftUI app on OpenUI

A planning assistant for iPhone, iPad and Mac built on [`packages/swift-lang`](../../../packages/swift-lang). Answers stream from OpenUI Cloud and render as native SwiftUI views, and their data comes from tools that run on the device: your calendar and reminders, Apple Maps, Wikipedia and Wikimedia Commons photos, and an Open-Meteo forecast. It also adds a few components only a native app can offer: a map, a day timeline, a camera field and a Razorpay pay button.

It's here to show the Swift package in a real app, so it uses more than an example needs: tools, native components, payments, persistence and UI tests.

<img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/hero-charts.png" alt="The same chart answer on a Mac, an iPad and an iPhone">

The same answer on a Mac, an iPad and an iPhone: Saturday's hourly temperatures and rain for three cities, from Open-Meteo.

The clips below are real answers from OpenUI Cloud, replayed so they're repeatable, with the tools on the device running for real. They're sped up and the waits are cut.

### iPhone

| Charts | Photos | Trip | Booking |
|---|---|---|---|
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-charts.gif" width="200" alt="Hourly temperature and rain charts with tooltips, legend and tabs"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-rome.gif" width="200" alt="Sights in Rome as photo cards, then the map full screen"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-gallery.gif" width="200" alt="A Kathmandu trip plan with hotels, sights, a map and a food photo viewer"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-booking.gif" width="200" alt="Paying a brunch deposit through Razorpay's test checkout"> |
| Tap for tooltips, tap a legend key to hide a city, switch tabs | Sights and photos from Wikipedia, then the map full screen | Hotels from Apple Maps, sights, a map, and food photos to swipe through | Brunch spots from Apple Maps, a deposit through Razorpay's checkout (test mode), then the model confirms it |

### Mac

<img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-charts.gif" alt="The chart answer on the Mac, with tooltips following the pointer">

On the Mac the chart follows the pointer. The legend and tabs work the same.

| | |
|---|---|
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-rome.gif" width="400" alt="Rome's sights as a photo grid on the Mac, and the map in a sheet"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-trip.gif" width="400" alt="The Kathmandu trip on the Mac, with the photo viewer"> |
| Rome as a photo grid, and the map in a sheet | The Kathmandu trip; the photo viewer takes arrow keys |

### iPad

| | |
|---|---|
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/ipad-charts.gif" width="400" alt="The chart answer on an iPad in landscape"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/ipad-rome.gif" width="400" alt="Rome's sights on an iPad in landscape"> |
| Charts in landscape, next to the chat list | Rome's photo grid, and the map as a sheet |

<details>
<summary>Screenshots</summary>

| | | | |
|---|---|---|---|
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-charts-1-tooltip.jpg" width="200" alt="Temperature tooltip"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-charts-3-rain.jpg" width="200" alt="Rain chance bars"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-rome-0.jpg" width="200" alt="Rome's sights"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-rome-map.jpg" width="200" alt="The map full screen"> |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-gallery-0.jpg" width="200" alt="Food photos"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-gallery-1-viewer.jpg" width="200" alt="The photo viewer"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-booking-2-checkout.jpg" width="200" alt="Razorpay checkout"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/iphone-booking-4-paid.jpg" width="200" alt="The deposit confirmed"> |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/dark-answer.jpg" width="200" alt="Dark mode"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/dark-sights-map.jpg" width="200" alt="Dark mode sights and map"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/dark-food.jpg" width="200" alt="Dark mode food photos"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/8bcc47d7775de145c0e23afb7b8c04d9c9852bea/planner/light-hotels.jpg" width="200" alt="Hotels from Apple Maps"> |

| | |
|---|---|
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-chart-tooltip.jpg" width="400" alt="Mac: temperature tooltip"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-chart-legend.jpg" width="400" alt="Mac: Delhi hidden from the legend"> |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-chart-rain.jpg" width="400" alt="Mac: rain chance with a tooltip"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-rome.jpg" width="400" alt="Mac: Rome's sights"> |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-food.jpg" width="400" alt="Mac: food photos"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/mac-viewer.jpg" width="400" alt="Mac: the photo viewer"> |
| <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/ipad-charts-1-tooltip.jpg" width="400" alt="iPad: temperature tooltip"> | <img src="https://raw.githubusercontent.com/NandishwarSingh/openui/23529aecf6031f5184cb24f1cf6b5dfba3ba3848/demo/ipad-rome-map.jpg" width="400" alt="iPad: the map as a sheet"> |

</details>

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
  -skip-testing:PlannerUITests/LiveFlowTests -skip-testing:PlannerUITests/DemoVideoTests \
  -skip-testing:PlannerUITests/MediaTests
```

`LiveFlowTests` talk to the model and spend a few calls each; run them on purpose. `DemoVideoTests` and `MediaTests` are slow walkthroughs for recording the media above (`MediaTests.testBooking` sends one live message after paying).

Payments use Razorpay's test mode: the checkout is real, no money moves.

Photo credit: `media/bangalore-palace.jpg`, see `media/CREDITS.txt`.
