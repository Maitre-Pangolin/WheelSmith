# WheelSmith

A radial quick-action wheel for macOS. Hold **⌥ Space** anywhere and a wheel pops up under your
cursor. Point at a slice and let go to jump to that app or run its action.

```
               Dia
      Cursor         Ostraka
  Claude                 Slack
                ( ⚙ )                ← let go in the center, past the edge, or press Esc = cancel
                                        (center after 2 seconds = Settings)
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
  - **Comes to you:** an app slice (and any window picked from its ring) brings the window onto
    the display where you opened the wheel, resized to fit, never back to the display it was last on.
  - **Window picker:** when an app has 2 or more windows, its outer ring lists them first (title,
    a display badge, minimized ones dimmed), followed by the sub-actions, up to 8 entries.
- **Themes:** 29 designed themes (13 light, 16 dark) plus the two originals (Midnight, Daylight), picked in Settings ›
  General. While the wheel is open, **← →** step through the light or dark themes and **↑ ↓** switch
  to light or dark (to the same family when there is one, like Neon Sign ↔ Highlighter). The hub
  shows the theme's name, and the choice is saved.
- **Discover sub-actions from menus:** select a slice in Settings and click **Add from … menus**.
  WheelSmith reads that app's menu bar and lists every command with its shortcut. Search, tick
  up to 5, and each becomes a sub-action with a matching icon. See [Where sub-actions come
  from](#where-sub-actions-come-from).
- **Screenshot** slice (default): area, full screen, or the ⌘⇧5 toolbar for video. It uses macOS's
  own shortcuts, so captures land where you've set and no extra permission is needed.
- **Visual Settings window:** hold the wheel open for two seconds (a ring fills around the center) and let go in the center (a ⚙
  appears there once it's ready; a quicker release in the center just closes the wheel), use the
  menu-bar icon (a ring with one raised segment), or open WheelSmith again (Spotlight, Finder) while it's running. Click
  slices on the live preview to edit them. Everything is also in a plain JSON file that reloads
  live.
- **Theme catalog:** every theme is data in `design/themes/themes.json` (gradients, edges, rails,
  fonts), generated from the Claude Design canvas by `design/tools/build_themes.py`. The fonts are
  bundled from Google Fonts (SIL Open Font License), see `Support/Fonts`.
- **Always on:** a LaunchAgent starts WheelSmith at login and restarts it if it ever crashes. Quitting from
  the menu stays quit.

## Requirements

- macOS 14 or later (built and tested on macOS 26, Apple Silicon). Release builds are universal
  (Apple Silicon and Intel).
- To build from source: Swift 5.10 or later. The Xcode Command Line Tools are enough
  (`xcode-select --install`).

## Install with Homebrew

```bash
brew tap maitre-pangolin/tap
brew trust --cask maitre-pangolin/tap/wheelsmith
brew install --cask maitre-pangolin/tap/wheelsmith
```

Homebrew only loads casks from other people's taps once you trust them, hence `brew trust`. The app
still isn't notarized, so the first launch needs **Open Anyway** once, as in the next section.
Update with `brew upgrade --cask wheelsmith` and open WheelSmith again; remove it, with its login
item and config, with `brew uninstall --zap --cask wheelsmith`.

## Download

1. Get `WheelSmith-<version>.zip` from the
   [latest release](https://github.com/Maitre-Pangolin/WheelSmith/releases/latest) and unzip it.
2. Drag **WheelSmith.app** into your **Applications** folder, then open it.
3. WheelSmith isn't notarized by Apple, so macOS says it can't verify the app. Click **Done**, open
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to WheelSmith.
   You only do this once. Or, in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/WheelSmith.app
   ```

On first launch WheelSmith turns on launch at login (a LaunchAgent, see
[Install from source](#install-from-source)). To update, quit it from the menu bar, replace the app
in Applications, and open it again; the Accessibility permission carries over, because every
release is signed with the same certificate.

To remove it: quit WheelSmith, delete the app, and delete
`~/Library/LaunchAgents/dev.wheelsmith.app.plist`. Your config stays in `~/.config/wheelsmith`.

## Install from source

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
1. Builds a release `WheelSmith.app`, signed with that certificate (or ad-hoc if you skipped the
   setup).
2. Copies it to `~/Applications/WheelSmith.app`.
3. Registers `~/Library/LaunchAgents/dev.wheelsmith.app.plist`, which starts it now and at every login.

No `sudo` is needed. Re-run `install.sh` to upgrade after changing code: it rebuilds, replaces
the app and restarts it. Your config isn't touched.

To remove it (your config stays in `~/.config/wheelsmith`):

```bash
./scripts/uninstall.sh
```

## Run without installing (development)

```bash
swift run WheelSmith
```

Or build the bundle and open it:

```bash
./scripts/build.sh && open build/WheelSmith.app
```

The menu bar icon and the app icon share one shape, `LogoMark` in
`Sources/WheelSmith/LogoMark.swift`. After changing it, run `./scripts/make-icon.sh` to regenerate
`Support/AppIcon.icns`.

Use a throwaway config so you don't touch your real one:

```bash
WHEELSMITH_CONFIG=/tmp/wheelsmith.json swift run WheelSmith
```

Render the wheel and Settings to PNGs (useful for design tweaks):

```bash
swift run WheelSmith --snapshot /tmp/wheelsmith-shots
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
| **Menu** and **Shortcut** actions, **Add from menus**, window picker, bringing windows to your display | **Accessibility.** You're prompted the first time; or use Settings → General → Grant… |

### Code signing

macOS remembers the Accessibility permission per *signing identity*. With ad-hoc signing, every
build counts as a new app, so you'd have to re-grant after each reinstall.
`./scripts/setup-signing.sh` fixes this once and for all:

- It creates a self-signed certificate, **WheelSmith Local Signing**, in your login keychain.
- It trusts that certificate for code signing only. macOS asks for your password here.
- `build.sh` and `install.sh` then use it automatically.

After setting it up, install and grant Accessibility one last time; later reinstalls keep it.
The first build may ask whether `codesign` can use the key: click **Always Allow**.

`build.sh` picks a signing identity in this order:

| Order | Identity | When it's used |
|---|---|---|
| 1 | `SIGN_IDENTITY="…"` | Set it to use, for example, an "Apple Development: …" certificate |
| 2 | WheelSmith Local Signing | Created by `setup-signing.sh` |
| 3 | Ad-hoc | Fallback; a hint is printed |

To remove the certificate: Keychain Access → login → My Certificates → delete "WheelSmith Local
Signing".

### Publishing a release

Releases are built by GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml))
when you push a version tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The workflow runs the tests, builds a universal app with `./scripts/package.sh` (version taken from
the tag), and publishes `WheelSmith-<version>.zip` and its `.sha256` as a release with install notes.
To try the packaging locally: `VERSION=0.2.0 ./scripts/package.sh`, which writes to `dist/`.

Release builds are signed with a self-signed certificate, **WheelSmith Release Signing**, stored as
the repo secrets `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD`. That's what keeps users'
Accessibility permission across updates. Create it once with:

```bash
./scripts/setup-release-signing.sh
```

It also saves a backup to `~/Documents/WheelSmith Release Signing`. Keep it: a new certificate means
every user re-grants Accessibility once. Without the secrets, the workflow still publishes, signed
ad-hoc, with a warning.

## Configuration

Settings writes to `~/.config/wheelsmith/config.json`. You can also edit the file by hand; changes apply
as soon as you save. If the JSON is invalid, WheelSmith keeps the previous config and shows a ⚠︎ in the
menu bar.

On first launch, when there's no config yet, WheelSmith writes a starter wheel built from apps that
come with macOS: Safari, Mail, Calendar, Finder, Screenshot, Notes, Terminal and System Settings.
Any of those your Mac doesn't have are left out. **Settings → Reset** brings that wheel back.
For a full ten-slice wheel with third-party apps, sub-actions and a prompt, see
[`examples/config.json`](examples/config.json); copy it over your config to try it.

```jsonc
{
  "hotkey": "option+space",          // modifiers: cmd, option, control, shift; key: a char, space, f1…f20, …
  "theme": "midnight",               // any id in design/themes/themes.json, e.g. graphite, aurora
  "items": [                         // ≤ 8, clockwise from the top
    {
      "label": "iTerm",
      "action": { "type": "app", "bundleId": "com.googlecode.iterm2" },
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
  WheelSmith/          the app
    AppDelegate.swift  menu-bar item, wiring
    HotkeyManager.swift  Carbon hotkey press/release (+ Esc and arrows while open)
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

**Speed:** WheelSmith is always resident. The overlay panel is built and rendered once at launch, so
pressing the hotkey only moves an existing window and fades it in. Icons are resolved ahead of
time. Pointer polling runs only while the wheel is open, so WheelSmith uses no CPU when idle.

## Troubleshooting


- **Nothing happens on ⌥ Space.** Another app may own that shortcut (Raycast, ChatGPT and some
  launchers use it), and the menu bar icon shows a ⚠︎ when registration fails. Pick another hotkey in
  Settings → General, or free it up in the other app.
- **A Menu or Shortcut sub-action does nothing** (you hear a beep). Grant Accessibility (see
  Permissions). For Menu actions, the app may have renamed the item: open the sub-action in
  Settings and choose it again.
- **No WheelSmith icon in the menu bar.** On notched MacBooks a full menu bar pushes the left-most
  icons, the newest ones, off-screen. To fix it, turn off icons you don't need in *System
  Settings → Menu Bar*, or use a menu-bar manager. Either way, you can always reach Settings by
  holding the wheel open for two seconds and letting go in the center, or by opening WheelSmith again
  from Spotlight. There's a Quit
  button under Settings → General.
- **Windows on other Spaces** (other desktops, full-screen windows) are listed too, with a full-screen
  icon for full-screen ones; picking one switches to its Space. macOS's Accessibility API only reports
  windows on the Spaces you're looking at, so WheelSmith remembers each window once it has been on
  screen (it checks your slices' apps whenever you switch Space or app), and also searches for the
  others the way window switchers like AltTab do. That search is quick for most apps but can't reach
  windows of apps that have been running a long time (iTerm and Dia often): those appear once you've
  visited them after WheelSmith started. Both rely on undocumented macOS calls; if a future macOS
  removes them, only these windows disappear from the ring.
  A full-screen window is brought over too: it leaves full screen, moves, and goes full screen again
  on your display (about a second, for the two animations).
- **Near a screen edge** the wheel shifts inward so the slices stay visible, and the pointer moves
  to its center.

## Ideas / next steps

- Mouse trigger (for example a middle-click hold) as an alternative to the hotkey
- Run Shortcuts-app shortcuts as actions (with a picker fed by `shortcuts list`)
- Per-app wheels (different slices depending on the frontmost app)
- Window actions (move/resize the focused window to halves or other displays)
- App icon and a signed, notarized build
