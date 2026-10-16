# Lampwerk

Lighting plots for iPhone. Place the heads you rent, read the light and the amps as you go, send the gaffer a one-page sheet. SwiftUI, iOS 17+, portrait, dark only.

## Run it

1. Open `Lampwerk.xcodeproj` in Xcode 16 or later.
2. Pick the **Lampwerk** target, then **Signing & Capabilities**, and choose your team.
3. Run on an iPhone or the simulator. Everything but AR tagging works in the simulator. AR needs a real iPhone (LiDAR phones also show the scanned room mesh).

If the project file ever won't open, regenerate it: `brew install xcodegen && xcodegen`.

## What's here

| Part | File |
| --- | --- |
| Plots list, new plot | `Home/HomeView.swift` |
| Plan editor (setups, readout, lamp rail, add lamp) | `Plot/EditorView.swift` |
| The plan: draw, drag, aim, pinch | `Plot/PlanCanvas.swift`, `Plot/PlanDrawing.swift` |
| Inspector (role, output, colour, modifier, gel, switch, duplicate, mirror) | `Plot/Inspector.swift` |
| Lamp library sheet | `Plot/LibrarySheet.swift` |
| Send sheet: gaffer sheet PDF, plan image, text list; opens after AR Done | `Send/SendSheet.swift`, `Send/Export.swift` |
| AR tagging: talent mark, camera, then lamps on the floor; Done lays them out as the plan | `AR/ARTagView.swift`, `AR/ARTagModel.swift`, `AR/ARContainer.swift` |

Under the hood:

- `Model/Lamp.swift`: the 31-item library, modifiers and gels with rough transmission. Watts and beams are approximate and still need checking against maker spec sheets.
- `Model/LightMath.swift`: lux at the talent, bounce fill, key to fill ratio, amps (HMIs ×1.1), 16 A circuit packing. Ported from the web prototype; every figure is approximate.
- `Model/Starters.swift`: three-point, Rembrandt, window key, car interior, empty room.
- `Model/PlotStore.swift`: plots saved as JSON in Documents. No account.
- `Design/Theme.swift`: brand v2 "Console" tokens. Gel (#FFC21A) only ever means light.
- `Fonts/`: IBM Plex Sans and Mono (SIL OFL), registered at launch.

## Not built yet

- Light and Face views, false colour.
- Live link (web, no app) and laying a plot out on another set.
- Recce photo tracing, Out & Scout handoff.
- Voltage setting in the UI (the maths takes 230 V or 120 V).
- Real drawn fixture art; the plan uses simple top-down shapes.
- Lampwerk Pro (StoreKit 2).
