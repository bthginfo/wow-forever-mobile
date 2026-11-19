# WoW Forever Mobile

## [⬇ Download Android APK](https://github.com/bthginfo/wow-forever-mobile/releases/download/v2.4.4-mobile.15/WoW-Forever-Mobile-2.4.4-mobile.15.apk)

**2.4.4-mobile.15 · Android 10+ · ARM64** · [Release notes](https://github.com/bthginfo/wow-forever-mobile/releases/tag/v2.4.4-mobile.15)

An Android launcher and touch interface for Blizzard’s Windows ARM64 WoW Forever client. The launcher runs the client on the phone using Wine/Proton. It includes a browser-based Battle.net login, Android keyboard and clipboard controls, and a configurable in-game touch HUD.

## What runs on the device

| Component | Role |
| --- | --- |
| GameNative-based Android launcher | Prepares the Wine prefix, mounts the game folder and presents the game through its X server. |
| Wine/Proton 11 ARM64EC | Provides the Windows environment for the ARM64 game executable. |
| ARM64 DXVK and Mesa Turnip | Translate Direct3D 11 to Vulkan and drive the Adreno GPU. |
| Battle.net browser sign-in | Opens Battle.net’s sign-in page and passes a game session to the ARM64 Wine helper. |
| Forever Touch Lua add-on | Scans populated action slots and builds editable touch arcs for spells and items. |

This is an unofficial launcher for players with access to WoW Forever through their Battle.net account. The game client and data come from Blizzard or your existing WoW Forever installation.

## Requirements

- A 64-bit Android phone, tablet or handheld with a Snapdragon 8-series SoC and an Adreno 7xx or 8xx GPU. The runtime is designed for Android 10 and later.
- Several GB of free internal space for the app and its Wine environment. The game folder can grow past 50 GB as it caches more data.
- A Battle.net account with access to WoW Forever. Install the Battle.net Android app if you use its Authenticator.
- Wi-Fi for the first download. A computer is optional for players who already have game files to copy.

## Install and set up

1. **Install the APK.** Use **Download Android APK** above and open the downloaded file. If Android prompts for installation permission, allow installs from the browser or file manager you used. Version .15 updates **WoW Forever Mobile** .14 and carries over its app settings. For a fresh installation, continue with the setup below.
2. **Choose your language.** Open **WoW Forever Mobile** and select **English** or **Deutsch**. You can change it later under **Language** in the launcher. The selection covers setup, the launcher’s login and connection UI, the touch toolbar, and the mobile skill editor. WoW and the Battle.net website manage the language of their own content.
3. **Grant storage access.** The launcher asks for **All files access** so it can read and update the game folder on Android’s shared storage.
4. **Set your game folder.** Use **Download and install** for a fresh setup. For files you already have, use **Find existing game files** and select their installation folder. The default is `/storage/emulated/0/WoW Forever/`.
5. **Check Region and Resolution.** The launcher suggests a Battle.net region from the Android country setting on a fresh setup. It uses Europe for supported European locales, Korea for Korea, Taiwan for Taiwan and Hong Kong, and Americas as the fallback. Choose your account’s region in the launcher if you prefer a different one. The app saves that choice. Select **720p**, **900p**, or **1080p** to suit your device.
6. **Tap Play World of Warcraft.** After the runtime is ready, the Battle.net sign-in page opens in the browser. Use **Authenticator** on that page to switch to the Battle.net app when needed, then return to WoW.
7. **Enter the game.** Use **Play controls** in the toolbar when you’re ready to switch from login controls to the in-game touch layout.

### Use files from an existing installation

Select the folder that contains `.build.info` and `Data/`. You can copy those two items from a WoW Forever installation on another device. Make sure your file manager shows the hidden `.build.info` file.

```text
WoW Forever/
├── .build.info
└── Data/
```

The launcher downloads the matching `_forever_/Wow-ARM64.exe` from Blizzard when needed. A fresh setup downloads the ARM64 client and archive indexes first. WoW caches additional zones and assets as you play.

### Standalone .16 test build

Install the standalone APK alongside **WoW Forever Mobile** .15. It appears as **WoW Forever Mobile Standalone** and keeps its own app settings. Grant storage access and use **Find existing game files** to select your WoW folder. Close the other launcher before starting the game from the same folder.

## Touch controls

| Control | What it does |
| --- | --- |
| Left stick | Movement |
| Right camera area | Drag to turn the camera |
| Jump | Right-side shortcut |
| Target, Interact | Right-side shortcuts on phones and left-side shortcuts in the tablet layout |
| Chat | Opens chat with the Android keyboard. The chat toolbar includes Paste and Send. |
| Bags, Map, Character | Opens the corresponding WoW panel |
| Talents, Quests, Spellbook | Opens the corresponding WoW panel |
| Toolbar arrow | Minimizes the toolbar to one button. Tap it to show the shortcuts again. |
| More controls → Edit controls | Moves the sticks, shortcuts, or toolbar |
| More controls → Edit skills | Assigns spells and usable bag items, swaps slots by dragging, and moves the arcs by their handles |
| More controls → Camera sensitivity | Sets how quickly the camera turns |
| More controls → Enter or exit fullscreen | Hides or shows the Android status and navigation bars |
| More controls → Text input | Opens the Android keyboard and paste controls for the game |

The touch overlay translates Android gestures into keyboard and mouse input for the game window. Forever Touch reads populated action slots and keeps a per-character mobile layout in its own add-on saved variables. Use **Edit skills** to set up the mobile spell and item buttons.

Starting with .16, saving skill changes outside combat briefly reloads the WoW interface to write the layout to disk. If you save during combat, log out through WoW or use `/reload` afterward to write it to disk.

### Tablets and fullscreen

The app selects the tablet layout when both dimensions of the app window are at least 600 dp. Movement, Target and Interact sit at the bottom left. Camera and Jump sit at the bottom right. A smaller split-screen window uses the compact phone layout. Use **Edit controls** to adjust positions or **Default** to try the tablet defaults.

Fullscreen is on by default. Open **More controls** in the game toolbar to enter or exit fullscreen. WoW fits the landscape window at the selected render budget when the session starts. If you resize the window during play, the game preserves its proportions. Start a new session to fit the new aspect ratio.

## Sign-in and connection

- **Play World of Warcraft** takes you to the Battle.net browser sign-in. The launcher keeps the sign-in page available while you switch to the Battle.net app for the Authenticator.
- **An interrupted sign-in** returns you to the launcher with a brief message. Tap **Play World of Warcraft** to start a new attempt.
- **Startup and connection** shows the selected region, runtime and first window timings, browser session handoff, and recognized game connection events. Use **Copy** to share that report when asking for help.

## Troubleshooting

- **Stuck on Connecting.** When the browser has handed off the session and WoW has recorded no response for about 35 seconds, open **Check connection** to view the last step or restart browser sign-in. Android devices with very long uptime can also hit a Wine timing issue. In that case, restart the phone and open the game again.
- **Client files missing or out of date.** Check the selected **Region** and game folder, then use **Check game files** or install the offered client update. The launcher verifies client downloads against Blizzard’s manifests.
- **Moving from version .13.** Install **WoW Forever Mobile** .15 alongside the older **WoW Forever Touch** app, grant storage access and select your existing game folder. The new app prepares its own Wine runtime on first launch.
- **Performance varies by device.** Use a lower **Resolution** in the launcher when testing on a new GPU or when the frame rate drops. The first visit to a zone can take longer while the game downloads assets.

## Build from source

Use JDK 17, Android SDK Platform 36, build-tools 35.0.0, and NDK 27.3.13750724. Point `local.properties` at your Android SDK. For a fresh checkout, build the ARM64 Wine login helper into `app/src/main/assets/wow-session-bridge.exe`. [Helper build and test instructions](tools/wow-session-bridge/README.md)

```bash
tools/fetch_components.sh
python3 tools/trim_proton_i386.py app/src/main/assets/bundled_components/proton-11.0-90624-arm64ec.wcp
./gradlew :app:assembleModernRelease :app:testModernReleaseUnitTest
```

The APK is written to `app/build/outputs/apk/modern/release/`. The runtime download script verifies each component against `tools/components.sha256`.

A local release signing configuration can be provided in `app/keystores/keystore.properties`. Keep keystores and passwords outside version control. This release uses application ID `app.wowforever.mobile.browser`.

Pass `-PforeverStandalone=true` to Gradle to build the separately installable test variant with application ID `app.wowforever.mobile.standalone`.

---

## Credits and how it works

This project packages other people's work into a single-purpose app. None of it would exist without:

- **WoW Forever for Android** by jaredgei and contributors provides the base launcher and runtime integration. [Upstream project](https://github.com/jaredgei/wow-forever-android)
- **[GameNative](https://github.com/utkarshdalal/GameNative)** by Utkarsh Dalal and contributors (GPL-3.0). The Android app, the Wine container management and the X server are all GameNative, based on v1.2.1. GameNative in turn builds on **[Pluvia](https://github.com/oxters168/Pluvia)**, **[Winlator](https://github.com/brunodev85/winlator)**, **[Winlator Cmod](https://github.com/coffincolors/winlator)** and the **[Bionic Vulkan wrapper](https://github.com/leegao/bionic-vulkan-wrapper)**.
- **The WoW Forever RP6 community bundle**, which first got the beta running on a Retroid Pocket 6 in GameNative and supplied the three custom runtime components:
  - **Proton 11 ARM64EC** built from [The412Banner/proton-wine](https://github.com/The412Banner/proton-wine/tree/e5fa703ed7f7329e20d7ede481ab185cf8b1a8b2) with an ARM64 copied-syscall fix and an NLS fallback allocation patch.
  - **DXVK 2.4.1 (aarch64)** built from [doitsujin/dxvk](https://github.com/doitsujin/dxvk/tree/0cf05780abd7250c2cd713b7749cf32180157cf5).
    - **Mesa Turnip (Adreno 740)** built from Mesa [`fe067b17d9`](https://github.com/mirror/mesa/tree/fe067b17d9) with a patch limiting barycentric waits to the current block, which fixes a shader scheduler assertion on Adreno 740.
  - **Mesa Turnip (Adreno 8xx / Snapdragon 8 Elite)** built by **[arusiasotto](https://github.com/arusiasotto/wow-forever-a840)** from **[whitebelyash/mesa-unified](https://github.com/whitebelyash/mesa-unified)** (`turnip/gen8` v32) with the barycentric scheduler fix and ICD exports.
- **[Wine](https://www.winehq.org/)**, **[Proton](https://github.com/ValveSoftware/Proton)**, **[DXVK](https://github.com/doitsujin/dxvk)**, **[Mesa](https://mesa3d.org/)**, **[FEX-Emu](https://github.com/FEX-Emu/FEX)**, **[box64](https://github.com/ptitSeb/box64)** and **[PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/)**.
- **Blizzard Entertainment** for World of Warcraft and its Windows ARM64 client. The app icon and splash art come from Blizzard's official [WoW Forever page](https://worldofwarcraft.blizzard.com/en-us/forever). Blizzard owns them and the World of Warcraft marks.

Full third-party license details are in [`THIRD_PARTY_NOTICES`](THIRD_PARTY_NOTICES).

### What this fork changes from GameNative

GameNative is a general game library with Steam, GOG, Epic, Amazon, EA and Rockstar stores, mod management, VR support and per-game container settings. This fork turns it into a launcher for one pre-configured container:

- **Standalone app:** the launcher uses its own Android application ID and Wine prefix.
- **Launch flow:** tap **Play World of Warcraft** to start Battle.net browser sign-in. Press Back on the loading screen to return to the launcher.
- **Pre-configured container:** bionic, Proton 11 ARM64EC, Turnip through the Vulkan wrapper, DXVK 2.4.1 aarch64, WINEESYNC off, a render size fitted to the window, and `G:` mapped to `/storage/emulated/0/WoW Forever`.
- **Native ARM64 launch:** GameNative wraps every Windows program in `winhandler.exe`, an x86-64 helper that needs x86 emulation. ARM64 executables now launch directly, so the game never goes through FEX, and the working directory is set from the mapped drive.
- **Game file setup:** the launcher installs the client from Blizzard's CDN or upgrades a beta install in place, writes `_forever_/.flavor.info` and a basic `WTF/Config.wtf` if they're missing, forces `gxApi "D3D11"` (so a copied Mac config that says Metal can't break it), and refuses to start without `.build.info`.
- **Package-name fixes:** several paths were hard-coded to `app.gamenative`: the bionic library path rewrite (`WINEMU_HOST_PKG` / `HOST_PKG`), the gamepad shared-memory files, the DXVK state cache and the default drives. The controller path was the reason controllers didn't work.
- **Small robustness fixes:** non-numeric container IDs no longer crash the ID parser, and the bionic redirect library is copied in if it's missing.
- **Keyboard fixes:** GameNative's on-screen keyboard dropped shifted symbols (`@` came through as `2`), because it sent key codes without the character or the Shift key. The fix is in `Keyboard.java` and `IMEInputReceiver.kt`. The keyboard now always goes through the IME receiver, so it appears on the Thor's bottom screen.
- **Battle.net browser sign-in** opens Battle.net’s web flow and hands the resulting session to the ARM64 Wine helper.
- **Native In-App Game Updater (v2.0):** Live version check against Blizzard patch services, direct-from-CDN ARM64 binary and manifest downloads, CASC index synchronization, and atomic `.build.info` updates on-device over Wi-Fi without any PC dependency.
- **Lean runtime & startup:** eliminated continuous background accelerometer polling during gameplay in favor of native OS window management, removed cold-boot bitmap allocations, guarded background performance metric collection loops, and switched DNS to native platform resolution.
- **Removed:** every store backend (Steam and JavaSteam, GOG, Epic, Amazon, EA, Rockstar), library, login, settings, custom game scanner, and downloads screens, ExoPlayer and browser dependencies, `DownloadService`, `ContainerMigrator`, Nexus mod management, the Meta Quest/XR build, PostHog analytics, Play Integrity, the self-updater, the Room database, the notification prompt, extra bundled Box64/FEX/DXVK versions and the legacy (Android 9) build. That's roughly 135k lines of code and about half the APK size.
- **Tooling:** `tools/download_wow_arm64.py` fetches the ARM64 client from Blizzard's CDN, `tools/sync_wow_to_device.sh` handles updates, and `tools/fetch_components.sh` downloads the runtime archives.

## License

GPL-3.0, the same as GameNative. See [`LICENSE`](LICENSE). The bundled runtime components carry their own licenses (LGPL, MIT and others). See `THIRD_PARTY_NOTICES` and the notices inside each component archive.
