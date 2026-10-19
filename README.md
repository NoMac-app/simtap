# simtap

Give your agent a phone. simtap lets Claude Code, Codex, Cursor and any other MCP client read and drive the iOS Simulator on your Mac, with a small set of tools and a compact view of the screen.

It builds, runs and tests Xcode projects, reads and uses the screen of any app (SwiftUI, UIKit, React Native), answers iOS's permission prompts, reads the app's logs and crashes, and records video. Tested on Xcode 26.5 and 27 with iOS 26.5 and 27, on iPhone and iPad.

## What the agent sees

```
Demo · Sign In · iPhone 17 Pro (iOS 26.5)
textfield "Email" #email @201,194
securefield "Password" #password @201,246
switch "Remember me" #remember off @341,298
button "Sign In" #signIn @201,350
text "Not signed in" #status @201,402
tabs: Login (selected) @158,822, Items @244,822
```

- One line per element: kind, label, `#id` (the app's accessibility identifier), state and `@x,y`, the center in points.
- Groups, icons inside buttons, scroll bars, the status bar and the keyboard's keys are folded away. The tab bar, scrolling and the keyboard are one line each.
- Only what can be tapped is listed. An alert, a sheet, a menu or a full-screen view in front hides the screen behind it, and iOS's own permission prompts read as alerts over the app. Rows under the navigation bar, the tab bar or the keyboard are counted as hidden (above, below, to the left or right), not listed.
- Web views (Capacitor, Expo DOM components), maps, games and iOS's out-of-process pickers have nothing for accessibility to read. They come back as one `unreadable` line with their place, so the agent knows to take a screenshot and tap by point.
- A screenshot, when asked for, is sized to points, so a point in the picture is a point to tap.
- The sign-in screen above is about 70 tokens. The full accessibility tree it comes from is about 40,000.

## Using the screen

`ui_act` takes steps in the same words `ui_look` prints, runs them in order, and answers with what changed:

```
ui_act steps: ["fill #email gary@example.com", "fill #password secret1", "tap #signIn", "wait \"Welcome\""]

4 steps done in 4.5 s
changed: #email "gary@example.com" · #password "•••••••" · #status "Welcome, gary@example.com"
```

Steps:

| Step | Does |
|---|---|
| `tap #id`, `tap "label"`, `tap button "label"`, `tap @x,y` | Taps; a switch gets a real touch |
| `fill #id text` | Focuses the field, clears it, types, and reads the text back |
| `type text` | Types into the field that has focus |
| `scroll down`, `scroll right @201,402` | Scrolls the screen, or one carousel |
| `swipe left`, `swipe left "Row 3"` | Swipes the screen, or one row (to reveal Delete) |
| `hold "Row 5" [seconds]` | Long press, for context menus |
| `set #volume 75` | Sets a slider to a percent |
| `back`, `home`, `key return` | The back button (or edge swipe), the home button, a key |
| `wait "Welcome" [seconds]`, `gone "Loading"` | Waits for something to appear or go |

Every step is checked, so nothing succeeds silently:
- Typed text is read back from the field. When iOS's autocorrect or smart punctuation changes it (`--` to `—`, `'` to `’`), the text is pasted instead, which iOS takes as is. A field that still shows something else stops the call and says what it shows.
- Text in any language (Café, 日本語, emoji) can be typed: what a US keyboard lacks goes through the Simulator's clipboard.
- `fill` refuses anything that isn't a text field, so keys never land in whichever field still has focus.
- A tap that changes nothing is reported, after waiting 2.5 s for late answers such as a permission prompt. A tap inside a web view says it can't be checked.
- A target that isn't on screen yet gets two seconds to appear, then fails with the next step: "2 elements are below: scroll down", or, when an alert came up in front, "Answer it first: tap "Cancel" or "Open"".
- The first failing step stops the rest and returns the screen as it is now.
- A new screen comes back whole; otherwise only what changed.

## Tools

| Tool | CLI | Does |
|---|---|---|
| `app_run` | `simtap run` | Builds the Xcode project here, installs and launches it, answers with the first screen; errors as `file:line` |
| `devices` | `simtap devices` | Lists the Simulators on this Mac with their runtime, UDID and state |
| `device_use` | `simtap use "iPhone 17 Pro"` | Chooses the Simulator the other tools use, booting it (one boot at a time); dark mode, a clean status bar |
| `app_control` | `simtap app launch dev.example.app` | `install`, `launch` (answers with the first screen), `terminate`, `uninstall`, `open_url`; `grant`, `revoke` and `reset_permissions`; `location`; `push` |
| `ui_look` | `simtap look` | Reads the screen; `find` keeps matching lines, `screenshot` adds a picture, `full` saves the whole tree |
| `ui_act` | `simtap act "tap #signIn" ...` | Does steps in order and answers with what changed |
| `app_logs` | `simtap logs` | The app's print output and its own system log lines; `grep`, `wait_for`, `crashes` |
| `tests_run` | `simtap test` | Runs the unit and UI tests; counts, and each failure as `file:line`; "0 tests ran" is an error |
| `screen_record` | `simtap record start` | Starts or stops a video of the screen; stop answers with the MP4 |
| `job_status` | `simtap job` | Waits up to 40 s for a long build and answers with its result, or its progress |
| `job_cancel` | `simtap cancel` | Stops a job |

The MCP server and the CLI are built from one list, so they always match. The tool list and instructions stay under 4,000 tokens; a test enforces it.

## Build and run

`app_run` does the whole loop in one call: it finds the project (a workspace first, then a project, an XcodeGen spec, or `ios/`), picks the scheme, builds for the Simulator, installs, launches, and answers with the first screen.

```
Built Demo in 4.2 s, installed dev.simtap.demo.
Launched Demo in 3.9 s.
Demo · Sign In · iPhone 17 Pro (iOS 26.5)
textfield "Email" #email @201,194
...
```

- A failed build answers with the errors only, as `Sources/App.swift:49:37: error: ...`, and the path to the full log.
- Each folder (each git worktree) builds into its own DerivedData, so rebuilds are incremental and worktrees never share products.
- An XcodeGen project is regenerated from `project.yml` before each build (skipped when nothing changed), so new files are always in it.
- The next call in the same folder needs no arguments.
- An MCP call answers within 40 s; a longer build answers with a job, and `job_status` waits for it. From the CLI, `simtap run` simply waits.
- Expo, React Native, Flutter and Capacitor builds are not done yet; build them with their own tools, then `app_control install`.

## Tests

`tests_run` runs the scheme's tests and reads the answer from Xcode's result bundle, not from the scrolling output:

```
Tests failed: 1 passed, 2 failed (3 in 35.3 s). Result bundle: .../tests-1792370825323.xcresult
DemoTests/SignInTests/testRejectsAShortPassword(): Tests/SignInTests.swift:12: XCTAssertEqual failed: ("Welcome, gary@example.com") is not equal to ("Invalid email or password")
DemoTests/rejectsAnEmailWithoutAt(): Tests/SignInTests.swift:18: Expectation failed: ...
```

- XCTest and Swift Testing both.
- Each failing test is named the way `only` takes it, to rerun just that one.
- "0 tests ran" (no test target, or a filter that matched nothing) is an error, never a pass.

## Logs and crashes

`app_logs` shows what the app itself said, not the thousands of lines Apple's frameworks log from inside it:
- Its `print()` output, kept from the moment `app_control` launches it.
- Its own system log lines (its subsystem, or logged by its own code), streamed from launch. macOS keeps info lines only in memory and drops them within seconds when the Simulator is busy, so reading the log store afterwards misses them.
- `grep` also searches Apple's lines, for things like a missing image or a layout warning.
- `wait_for` waits up to 25 seconds for a line, for example after a tap that starts a network call.
- `crashes` lists crash reports with the crashing thread down to your code (`ItemsView.body.getter (App.swift:64)`), next to the app's last output, which holds Swift's own message (`App.swift:64: Fatal error: ...`). macOS can take up to a minute to write a report.

## Several agents, one Mac

- Each agent runs its own MCP server and holds its own Simulator through `device_use`.
- Boots never overlap, across every simtap process on the Mac: two Simulators booting at once on an 8 GB Mac pushed it into swap for minutes.
- `SIMTAP_MAX_BOOTED` caps how many run at once; asking for another shuts down the others first.
- Calls on one Simulator run one at a time, so two agents' steps never interleave.

## What it can't do yet

- Read inside web views, Flutter or game canvases: it says so, and a screenshot plus tap by point works.
- Real devices, Android, rotating to landscape, pinch and multi-touch.
- Reading text an app hides from accessibility: some React Native apps set a test id as the label, and the read says when labels look like that.

## Install

Needs macOS with Xcode and a Simulator runtime, and Node 20 or newer.

**No Mac?** If your agent works on Linux, Windows or in a cloud sandbox, [NoMac](https://nomac.app) gives it a real Mac in the cloud, with Xcode and the iOS Simulator, billed by the minute.

```sh
# Claude Code
claude mcp add simtap -- npx -y simtap mcp

# Codex
codex mcp add simtap -- npx -y simtap mcp
```

Cursor, Windsurf, VS Code and other clients that take a JSON config:

```json
{
  "mcpServers": {
    "simtap": { "command": "npx", "args": ["-y", "simtap", "mcp"] }
  }
}
```

Any other client: run `npx -y simtap mcp` as a stdio server. It speaks MCP 2024-11-05 through 2026-07-28.

Agents that work from a shell can use the CLI instead; `skill/SKILL.md` in the package teaches it in under 2 KB.

From a shell: `npx simtap look`.

## Privacy

simtap sends nothing anywhere. There is no telemetry and no network access at runtime: it runs `xcrun simctl`, the bundled AXe binary and `sips`, all on your Mac.

## How it works

simtap reads the Simulator through [AXe](https://github.com/cameroncooke/AXe) (MIT), bundled at a pinned version with its checksum checked at packaging, and through `xcrun simctl`. There is no test runner to build, so the first call is as fast as the rest.

## Develop

```sh
npm install
npm run axe        # fetch the pinned AXe into vendor/axe
npm test           # node --test, no build needed
npm run build      # dist/ for the npm package
node bin/simtap.js look
```

`examples/swiftui-demo` is the sample app the tests' screens come from. `scripts/golden.sh` builds it, runs it on a Simulator and checks 19 golden tasks: build and launch in one call, sign in, toggle, open an item, back and scroll, the app's logs, a crash, a build error and a failing test as `file:line`, a video, and a wrong password that must fail loudly.

`examples/edge-lab` is an app with every awkward screen: segments, steppers, sliders, menus, alerts, sheets, full-screen covers, permission prompts, text in any language, autocorrect, late content, toasts, swipe-to-delete, long press, a web view, UIKit and a deep link. `scripts/lab.sh` builds it and runs 26 checks on it.

`SIMTAP_DEBUG=1` prints every step and every program run with its time.

## Made at NoMac

simtap is built at [NoMac](https://nomac.app), where AI agents rent real Macs in the cloud to build, run and test Apple apps. It comes from thousands of agent runs on those Macs: where agents get stuck, what they misread on screen, and what they need to be told to keep going.

When simtap can't run where it is (no Mac, no Xcode, no Simulator runtime), its error names NoMac as a place to get one. It never shows when simtap works, and `SIMTAP_NO_CLOUD_HINT=1` hides it.

## License

MIT. AXe and the IDB frameworks it includes are MIT too; see `THIRD_PARTY_LICENSES`.
