# The One Ring

A radial quick-action wheel for macOS. Hold **⌥ Space** anywhere and a wheel pops up under your
cursor. Point at a slice and let go to jump to that app or run its action.

```
               Dia
      Cursor         Ostraka
  Claude                 Slack
                ( )                  ← let go in the center, past the edge, or press Esc = cancel
  iTerm                  Outlook
       Figma         Finder
            Screenshot
```

- **Up to 10 slices**, clockwise from the top. Each can have **up to 5 sub-actions**. These fan out
  in an outer ring when you hover the slice: keep moving outwards to pick one. Letting go on the
  slice itself runs the slice's own action.
- **Actions:**
  - **App:** focus the app, launching it if needed. Behaves like a Dock click.
  - **URL:** open a URL, deep link (`slack://…`) or file path, optionally in a chosen app.
  - **Menu:** focus an app, then click one of its menu-bar items (for example iTerm › Shell ›
    New Tab). This is the most reliable kind of sub-action: it needs no keyboard shortcut and
    ignores your keyboard layout.
  - **Shortcut:** focus an app, then send a keyboard shortcut (for example ⌘T in iTerm).
  - **Shell:** run a command.
  - **Prompt:** release on it and the wheel stays open with a text field. Type, then press
    Return to run a command with your text as `$1`, or Escape to quit. For example, Ostraka ›
    **Quick todo** runs `ostraka todo add "$1"`, so typing `Review the board #sched *high ^fri`
    adds a tagged, high-priority todo due Friday.
  - **None:** for a slice that only groups sub-actions.
- **Multiple windows and displays:**
  - **Prefer this display:** an app slice focuses the app's window on the display where you
    opened the wheel, if it has one there. Otherwise it focuses the last used window.
  - **Window picker:** when an app has 2 or more windows, its outer ring lists them first (title,
    a display badge, minimized ones dimmed), followed by the sub-actions, up to 8 entries.
  - **Bring here** (opt-in per slice): moves the app's window onto the display you're on,
    resized to fit.
- **Discover sub-actions from menus:** select a slice in Settings and click **Add from … menus**.
  The One Ring reads that app's menu bar and lists every command with its shortcut. Search, tick
  up to 5, and each becomes a sub-action with a matching icon. See [Where sub-actions come
  from](#where-sub-actions-come-from).
- **Screenshot** slice (default): area, full screen, or the ⌘⇧5 toolbar for video. It uses macOS's
  own shortcuts, so captures land where you've set and no extra permission is needed.
- **Visual Settings window:** use the ◎ menu-bar icon, or open The One Ring again (Spotlight,
  Finder) while it's running. Click
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

First, once per Mac, create a local signing certificate. This keeps the Accessibility permission
across reinstalls (see [Code signing](#code-signing)):

```bash
./scripts/setup-signing.sh
```

Then install:

```bash
./scripts/install.sh
```

This script:
1. Builds a release `TheOneRing.app`, signed with that certificate (or ad-hoc if you skipped the
   setup).
2. Copies it to `~/Applications/TheOneRing.app`.
3. Registers `~/Library/LaunchAgents/dev.theonering.app.plist`, which starts it now and at every login.

No `sudo` is needed. Re-run `install.sh` to upgrade after changing code: it rebuilds, replaces
the app and restarts it. Your config isn't touched.

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
active, `swift test` builds the tests but doesn't run them, so point it at Xcode. Use a separate
build folder, because the two toolchains' compiled modules can't be mixed:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path .build-xcode
```

## Permissions

| Feature | Permission |
|---|---|
| Hotkey, wheel, App / URL / Shell / Prompt actions | **None.** The hotkey uses Carbon `RegisterEventHotKey`, and the pointer is read by polling. |
| **Menu** and **Shortcut** actions, **Add from menus**, window picker, prefer this display, Bring here | **Accessibility.** You're prompted the first time; or use Settings → General → Grant… |

### Code signing

macOS remembers the Accessibility permission per *signing identity*. With ad-hoc signing, every
build counts as a new app, so you'd have to re-grant after each reinstall.
`./scripts/setup-signing.sh` fixes this once and for all:

- It creates a self-signed certificate, **TheOneRing Local Signing**, in your login keychain.
- It trusts that certificate for code signing only. macOS asks for your password here.
- `build.sh` and `install.sh` then use it automatically.

After setting it up, install and grant Accessibility one last time; later reinstalls keep it.
The first build may ask whether `codesign` can use the key: click **Always Allow**.

`build.sh` picks a signing identity in this order:

| Order | Identity | When it's used |
|---|---|---|
| 1 | `SIGN_IDENTITY="…"` | Set it to use, for example, an "Apple Development: …" certificate |
| 2 | TheOneRing Local Signing | Created by `setup-signing.sh` |
| 3 | Ad-hoc | Fallback; a hint is printed |

To remove the certificate: Keychain Access → login → My Certificates → delete "TheOneRing Local
Signing".

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
      "bringHere": true,               // optional: move its window to the display you're on
      "children": [                  // ≤ 5
        { "label": "New Tab", "icon": "sf:plus.square.on.square",
          "action": { "type": "menu", "menu": ["Shell", "New Tab"], "bundleId": "com.googlecode.iterm2" } },
        { "label": "Clear", "icon": "sf:eraser",
          "action": { "type": "keys", "keys": "cmd+k", "bundleId": "com.googlecode.iterm2" } }
      ]
    },
    { "label": "Docs", "icon": "sf:book",
      "action": { "type": "url", "url": "https://developer.apple.com", "bundleId": "company.thebrowser.dia" } },
    { "label": "Deploy", "icon": "sf:bolt",
      "action": { "type": "shell", "command": "open -a iTerm ~/code/app" } },
    { "label": "Quick todo", "icon": "sf:checklist",
      "action": { "type": "prompt", "command": "ostraka todo add \"$1\"",
                  "placeholder": "Review the board #tag *high ^fri" } }
  ]
}
```

`icon` is optional. Leave it out to use the app's icon, set `"sf:<name>"` for any
[SF Symbol](https://developer.apple.com/sf-symbols/), or give a path to an image. To find an app's
bundle ID, run `osascript -e 'id of app "Slack"'`.

Menu titles match loosely: case, extra spaces and a trailing `…` are ignored.

A `prompt` passes what you type as `$1`, never pasted into the command, so quotes, `$` or `;` in
your text can't run as shell code. Write `"$1"` with the quotes to keep it one argument.
`placeholder` is optional. Return runs it, shows the command's first line of output and closes the
wheel; on failure the wheel stays open with the error so you can fix the text. Escape or clicking
another window quits. The app you were in keeps focus throughout. The field opens to the right of
the wheel, or on the left near the screen's right edge.

Shell and Prompt commands run with `/bin/zsh -lc`, which doesn't read `~/.zshrc`. So they also look
in `~/.local/bin`, `~/bin`, `/opt/homebrew/bin` and `/usr/local/bin`. For a tool anywhere else, use
its full path.

## Where sub-actions come from

macOS has no single "quick actions" list that every app publishes. Apps make their actions
available in a few separate places:

| Source | What it gives | Used here |
|---|---|---|
| **Menu bar**, via Accessibility | Every command of every app, with its shortcut | ✅ **Add from menus** and the Menu action |
| Keyboard shortcuts | Whatever the app binds | ✅ Shortcut action |
| URL schemes (`slack://…`) | Deep links, documented per app | ✅ URL action |
| Shortcuts app (App Intents) | Actions apps offer to Shortcuts | Not yet (could run your shortcuts via `shortcuts run`) |
| AppleScript | Full scripting, different for every app | Use a Shell action with `osascript` |

The menu bar is the one source every app shares, so it's the default for discovering
sub-actions. An app only has menus while it's running; the browser offers to launch it in the
background first. Greyed-out items are commands the app has disabled right now (for example
when no window is open), and they may work later.

## How it works

```
Sources/
  RingCore/            pure logic, unit-tested
    Config.swift       JSON model: RingConfig → WheelItem → Action
    WheelGeometry.swift  angles, rings, hit-testing, sub-ring "sticky parent" tracking
    KeyCombo.swift     "cmd+shift+n" parsing / display
    MenuPath.swift     menu title matching, search, icon guessing
    RingLayout.swift   how many windows and sub-actions the outer ring shows
  TheOneRing/          the app
    AppDelegate.swift  menu-bar item, wiring
    HotkeyManager.swift  Carbon hotkey press/release (+ Esc while open)
    WheelController.swift  overlay NSPanel, 120 Hz pointer tracking while open, runs actions on release
    WheelView.swift    SwiftUI drawing (slices, sub-ring, hub, backdrop)
    Theme.swift        all colors / materials
    ActionRunner.swift app focus, URLs, shell, synthesized shortcuts, menu clicks
    MenuBar.swift      reads and clicks other apps' menu bars (Accessibility API)
    Windows.swift      lists, raises and moves other apps' windows; display layout
    ConfigStore.swift  load / debounced save / live file watching
    LaunchAtLogin.swift  LaunchAgent toggle
    Settings/          visual editor, including the menu browser sheet
```

**Speed:** The One Ring is always resident. The overlay panel is built and rendered once at launch, so
pressing the hotkey only moves an existing window and fades it in. Icons are resolved ahead of
time. Pointer polling runs only while the wheel is open, so The One Ring uses no CPU when idle.

## Troubleshooting


- **Nothing happens on ⌥ Space.** Another app may own that shortcut (Raycast, ChatGPT and some
  launchers use it), and the ◎ menu shows a ⚠︎ when registration fails. Pick another hotkey in
  Settings → General, or free it up in the other app.
- **A Menu or Shortcut sub-action does nothing** (you hear a beep). Grant Accessibility (see
  Permissions). For Menu actions, the app may have renamed the item: open the sub-action in
  Settings and choose it again.
- **No ◎ icon in the menu bar.** On notched MacBooks a full menu bar pushes the left-most
  icons, the newest ones, off-screen. To fix it, turn off icons you don't need in *System
  Settings → Menu Bar*, or use a menu-bar manager. Either way, you can always reach Settings by
  opening The One Ring again from Spotlight. There's a Quit
  button under Settings → General.
- **Windows on other Spaces** (other desktops, full-screen windows) are listed too, with a full-screen
  icon for full-screen ones; picking one switches to its Space. macOS's Accessibility API only reports
  windows on the Spaces you're looking at, so The One Ring remembers each window once it has been on
  screen (it checks your slices' apps whenever you switch Space or app), and also searches for the
  others the way window switchers like AltTab do. That search is quick for most apps but can't reach
  windows of apps that have been running a long time (iTerm and Dia often): those appear once you've
  visited them after The One Ring started. Both rely on undocumented macOS calls; if a future macOS
  removes them, only these windows disappear from the ring. Windows can't be moved between Spaces, so
  Bring here leaves them where they are.
  Full-screen windows can't be moved by Bring here.
- **Near a screen edge** the wheel shifts inward so the slices stay visible, and the pointer moves
  to its center.

## Ideas / next steps

- Mouse trigger (for example a middle-click hold) as an alternative to the hotkey
- Run Shortcuts-app shortcuts as actions (with a picker fed by `shortcuts list`)
- Per-app wheels (different slices depending on the frontmost app)
- Window actions (move/resize the focused window to halves or other displays)
- App icon and a signed, notarized build
