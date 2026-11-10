# The One Ring

A radial quick-action wheel for macOS. Hold **⌥ Space** anywhere and a wheel pops up under your
cursor. Point at a slice and let go to jump to that app or run its action.

```
            Dia
   iTerm           Slack
Cursor     ( ⚙ )      Outlook        ← let go in the center = Settings
   Claude          Notes                let go past the edge / Esc = cancel
          Finder
```

- **Up to 8 slices**, clockwise from the top. Each can have **up to 5 sub-actions**. These fan out
  in an outer ring when you hover the slice: keep moving outwards to pick one. Letting go on the
  slice itself runs the slice's own action.
- **Actions:**
  - **App:** focus the app, launching it if needed. Behaves like a Dock click.
  - **URL:** open a URL, deep link (`slack://…`) or file path, optionally in a chosen app.
  - **Shortcut:** focus an app, then send a keyboard shortcut (for example ⌘T in iTerm).
  - **Shell:** run a command.
  - **None:** for a slice that only groups sub-actions.
- **Visual Settings window:** let go in the center of the wheel, or use the ◎ menu-bar icon. Click
  slices on the live preview to edit them. Everything is also in a plain JSON file that reloads
  live.
- **Themes:** Midnight (default), Daylight and Liquid Glass. Every color lives in `Theme.swift`, so
  adding a theme is just adding values.
- **Always on:** a LaunchAgent starts The One Ring at login and restarts it if it ever crashes. Quitting from
  the menu stays quit.

## Requirements

- macOS 14 or later (built and tested on macOS 26, Apple Silicon)
- Swift 5.10 or later. The Xcode Command Line Tools are enough (`xcode-select --install`).

## Install (runs at login)

```bash
./scripts/install.sh
```

This script:
1. Builds a release `TheOneRing.app` (signed ad-hoc).
2. Copies it to `~/Applications/TheOneRing.app`.
3. Registers `~/Library/LaunchAgents/dev.theonering.app.plist`, which starts it now and at every login.

No `sudo` is needed. Re-run the script to upgrade after changing code.

To remove it (your config stays in `~/.config/theonering`):

```bash
./scripts/uninstall.sh
```

## Run without installing (development)

```bash
swift run TheOneRing
```

Or build the bundle and open it:

```bash
./scripts/build.sh && open build/TheOneRing.app
```

Use a throwaway config so you don't touch your real one:

```bash
THEONERING_CONFIG=/tmp/theonering.json swift run TheOneRing
```

Render the wheel and Settings to PNGs (useful for design tweaks):

```bash
swift run TheOneRing --snapshot /tmp/theonering-shots
```

Run the unit tests (geometry, hit-testing, key parsing, config). With only the Command Line Tools
active, `swift test` builds the tests but doesn't run them, so point it at Xcode:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Permissions

| Feature | Permission |
|---|---|
| Hotkey, wheel, App / URL / Shell actions | **None.** The hotkey uses Carbon `RegisterEventHotKey`, and the pointer is read by polling. |
| **Shortcut** actions (sending ⌘T etc.) | **Accessibility.** You're prompted the first time; or use Settings → General → Grant… |

With ad-hoc signing, macOS ties the Accessibility grant to the exact binary. After a rebuild you
may need to toggle The One Ring off and on again in *System Settings → Privacy & Security →
Accessibility*. If you have an Apple Development certificate, build with
`SIGN_IDENTITY="Apple Development: …" ./scripts/install.sh` and the grant survives rebuilds.

## Configuration

Settings writes to `~/.config/theonering/config.json`. You can also edit the file by hand; changes apply
as soon as you save. If the JSON is invalid, The One Ring keeps the previous config and shows a ⚠︎ in the
menu bar.

```jsonc
{
  "hotkey": "option+space",          // modifiers: cmd, option, control, shift; key: a char, space, f1…f20, …
  "theme": "midnight",               // midnight | daylight | glass
  "items": [                         // ≤ 8, clockwise from the top
    {
      "label": "iTerm",
      "action": { "type": "app", "bundleId": "com.googlecode.iterm2" },
      "children": [                  // ≤ 5
        { "label": "New tab", "icon": "sf:plus.square.on.square",
          "action": { "type": "keys", "keys": "cmd+t", "bundleId": "com.googlecode.iterm2" } }
      ]
    },
    { "label": "Docs", "icon": "sf:book",
      "action": { "type": "url", "url": "https://developer.apple.com", "bundleId": "company.thebrowser.dia" } },
    { "label": "Deploy", "icon": "sf:bolt",
      "action": { "type": "shell", "command": "open -a iTerm ~/code/app" } }
  ]
}
```

`icon` is optional. Leave it out to use the app's icon, set `"sf:<name>"` for any
[SF Symbol](https://developer.apple.com/sf-symbols/), or give a path to an image. To find an app's
bundle ID, run `osascript -e 'id of app "Slack"'`.

## How it works

```
Sources/
  RingCore/            pure logic, unit-tested
    Config.swift       JSON model: RingConfig → WheelItem → Action
    WheelGeometry.swift  angles, rings, hit-testing, sub-ring "sticky parent" tracking
    KeyCombo.swift     "cmd+shift+n" parsing / display
  The One Ring/                the app
    AppDelegate.swift  menu-bar item, wiring
    HotkeyManager.swift  Carbon hotkey press/release (+ Esc while open)
    WheelController.swift  overlay NSPanel, 120 Hz pointer tracking while open, runs actions on release
    WheelView.swift    SwiftUI drawing (slices, sub-ring, hub, backdrop)
    Theme.swift        all colors / materials
    ActionRunner.swift app focus, URLs, shell, synthesized shortcuts
    ConfigStore.swift  load / debounced save / live file watching
    LaunchAtLogin.swift  LaunchAgent toggle
    Settings/          visual editor
```

**Speed:** The One Ring is always resident. The overlay panel is built and rendered once at launch, so
pressing the hotkey only moves an existing window and fades it in. Icons are resolved ahead of
time. Pointer polling runs only while the wheel is open, so The One Ring uses no CPU when idle.

## Troubleshooting

- **Nothing happens on ⌥ Space.** Another app may own that shortcut (Raycast, ChatGPT and some
  launchers use it), and the ◎ menu shows a ⚠︎ when registration fails. Pick another hotkey in
  Settings → General, or free it up in the other app.
- **A shortcut sub-action does nothing.** Grant Accessibility (see Permissions). Check that the
  shortcut exists in that app.
- **Near a screen edge** the wheel shifts inward so the slices stay visible, and the pointer moves
  to its center.

## Ideas / next steps

- Mouse trigger (for example a middle-click hold) as an alternative to the hotkey
- Per-app wheels (different slices depending on the frontmost app)
- Window actions (move/resize the focused window to halves or other displays)
- App icon and a signed, notarized build
