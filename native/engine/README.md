# simulator-use engine (prototype)

One long-lived process per booted Simulator. It loads CoreSimulator's private frameworks, the HID connection,
the accessibility translator and the framebuffer once, then answers JSON requests, one per line on stdin, with
one JSON answer per line on stdout. Built on the FBSimulatorControl frameworks AXe ships (MIT; AXe by Cameron
Cooke, FBSimulatorControl from Meta's idb). `TextToHIDEvents.swift` and `KeyCode.swift` are AXe's, unchanged.

Ops: `describe` (whole screen, AXe's JSON), `point` {x,y}, `tap` {x,y}, `swipe`, `type` {text}, `home`,
`screenshot` {width,height,quality,path|inline}, `settle` {quiet_ms,first_change_ms}, `tap_settle_describe`,
`tap_trace`, `stream` {codec h264|hevc, transport annexb|fmp4|mpegts, fps, scale, bitrate, seconds, path}.

Measured October 21, 2026 on an Apple M6 Mac mini (iOS 27.0 runtime), against AXe 1.8.0 with one process per call:

| | AXe per call | engine |
|---|---|---|
| tap | 2.1 to 3.2 s | about 1 ms to send |
| whole-screen read | 1.6 to 1.8 s | 250 to 300 ms |
| read at a point | 0.45 to 0.5 s | 4 to 5 ms |
| screenshot (JPEG at points) | about 250 ms | 60 to 115 ms |
| tap, wait until the screen is still, read | 3.6 to 7.2 s (simulator-use act) | 1.2 s p50 (0.75 s of it is iOS's own animation) |

What makes that possible:
- **One automation session per phone, kept open.** iOS 27 Simulators read accessibility only after an XCTest
  "remote automation session" has loaded it, and an app launched afterwards reads empty until it is loaded again.
  FBSimulatorControl opens a session, loads accessibility and closes the session before every request (AXe pays
  about 1 to 2 s for that per call); in a long-lived process new sessions soon time out. The engine opens one
  session, keeps it, and reloads accessibility on it when the frontmost app reads empty (`forceBootstrap`). It
  closes the session when its input ends and waits 0.8 s for that to reach the phone: without the wait, the next
  process could not open a session at all. A new engine's first read takes 1.0 to 1.25 s; after that a point read
  takes 3 to 15 ms and a whole screen about 300 ms.
- **Never restart CoreSimulatorService under booted phones:** their automation sessions then time out until each
  phone is rebooted. A host also needs `automationmodetool enable-automationmode-without-authentication` once.
- **"Settled" is read from the screen buffer**, not from repeated tree reads: the IOSurface seed changes on every
  write. After an input the engine waits up to 500 ms for the first change, then for 150 ms without one.

Video: `stream` uses the Mac's hardware encoder (H.264 or HEVC, Annex B, fragmented MP4 or MPEG-TS): about
1.1 to 1.4 Mbit/s at 30 fps and half resolution, first data after 39 to 245 ms, 7% of one core.

`bench/` holds the scripts behind every number (T7 density, T13 clone start, T14 volumes, the act and stream tests).
