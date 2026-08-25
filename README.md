# Mac Steam Setup: Run Windows Steam Games on Apple Silicon Mac

**English** | [한국어](README.ko.md)

<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Mac Steam Setup icon">
</p>

**A free, open-source macOS app that helps Apple Silicon Mac users install Windows Steam and launch compatible Windows-only Steam games.** Mac Steam Setup automates the Sikarugir/Wine and D3DMetal setup without requiring a Windows virtual machine or a CrossOver subscription.

[Download DMG beta](https://github.com/heung115/mac-steam-setup/releases/download/v0.12-beta.1/Mac-Steam-Setup-v0.12-beta.1.dmg) · [Share feedback](https://github.com/heung115/mac-steam-setup/discussions) · [Report a bug or game](https://github.com/heung115/mac-steam-setup/issues/new/choose)

[![CI](https://github.com/heung115/mac-steam-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/heung115/mac-steam-setup/actions/workflows/ci.yml) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black) [![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Mac Steam Setup is a non-commercial open-source prototype. It does not bundle its own Wine build or Steam. Instead, it downloads pinned official Sikarugir engine and wrapper releases and Valve's Steam installer when the user starts setup.

This is an independent, unofficial community project. It is not affiliated with, endorsed by, sponsored by, or approved by Valve Corporation, Apple Inc., or the Sikarugir project. Steam and the Steam logo are trademarks and/or registered trademarks of Valve Corporation. This project does not use the Steam logo or Valve's official design assets.

## At a glance

| Question | Answer |
| --- | --- |
| What does it do? | Prepares Windows Steam on an Apple Silicon Mac and creates lightweight macOS shortcuts for installed Windows games. |
| What does it use? | A SwiftUI setup app, Sikarugir/Wine, and D3DMetal. |
| Which Macs are supported? | Apple Silicon Macs running macOS 14 or later. Intel Macs are not supported. |
| Is it a virtual machine? | No. It uses a Wine compatibility wrapper and does not install Windows. |
| Is it free? | Yes. The project is open source under the MIT License and does not require a CrossOver subscription. |
| Will every Steam game work? | No. Compatibility varies, and games that require anti-cheat or additional launchers may fail. |

## Features

- Step-by-step progress and downloaded-size reporting
- Protection against duplicate installation and launch requests
- Automatic cleanup of the Sikarugir waiting process left after Steam installation
- Automatic D3DMetal and Steam executable configuration
- Hidden background Sikarugir launcher Dock icon
- Steam login web-cache repair
- Complete shutdown of Windows Steam and running Windows games
- Lightweight macOS app shortcuts for installed games
- No changes to an existing macOS Steam installation or Porting Kit

## Usage

### Download the beta app

> Recommended download: [Mac Steam Setup v0.12-beta.1 DMG](https://github.com/heung115/mac-steam-setup/releases/download/v0.12-beta.1/Mac-Steam-Setup-v0.12-beta.1.dmg)

1. Download the DMG from the link above. Other versions and the fallback ZIP are available on [GitHub Releases](https://github.com/heung115/mac-steam-setup/releases).
2. Open the DMG and drag `Mac Steam Setup.app` onto the `Applications` folder shown beside it.
3. Try to open `Mac Steam Setup.app` once.
4. If macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**. After this one-time approval, you can open it normally by double-clicking.

The current beta is not signed or notarized by Apple. Make sure you downloaded it directly from this GitHub repository. A `.sha256` checksum is provided so you can check that the download was not corrupted. A ZIP is also available in the same Release as a fallback if the DMG does not open.

### Build from source

```sh
./build.command
```

Open `build/Mac Steam Setup.app`, then click `Windows Steam 준비하기` (Prepare Windows Steam). Complete the Steam installer using its default path. The setup assistant cleans up the first launch and applies the final configuration whether or not Steam is started at the end of the Windows installer.

Steam's initial connection checks may take about a minute on some networks. An IPv6 `TIMEOUT` can also appear during an otherwise normal fast launch, so that message alone does not prove that startup failed. Reproduction conditions and follow-up steps are documented in [Windows Steam startup network-delay notes](docs/diagnostics/steam-startup-network-delay.md). The initial Wine updater cannot render Korean fonts correctly, so Steam is prepared with English as its default language. You can switch to Korean in Steam settings, although Korean text in a later updater may appear as squares.

After installing a game, you can create a macOS app from the game-shortcut screen. A shortcut does not copy the Wine environment or game files. It starts Windows Steam in the background and launches the corresponding Steam App ID. Games that use Steam DRM cannot bypass the Steam process itself.

## Verification

```sh
bash Tests/run.sh
```

The test suite covers installation-state detection, monotonically increasing progress, Steam installation completion, wrapper configuration, duplicate-process detection, cache repair, the full shutdown protocol, Steam manifest parsing, and shortcut creation and signing.

The following checks were completed on a Mac running macOS 26.6.2 with an M4 Pro and Steam build `1785799196`:

- Steam installation and update to the latest client
- Login-window rendering and `steamwebhelper` stability for more than five minutes
- Restart after clearing the login cache
- Duplicate launch-request prevention
- Hidden Sikarugir launcher Dock icon
- Restart after completely terminating all Windows Steam processes

Game compatibility and anti-cheat support vary by title.

## Frequently asked questions

### Can I run Windows-only Steam games on an M-series Mac?

Mac Steam Setup prepares a Windows Steam environment for Apple Silicon Macs. Compatible games can then be installed through Windows Steam and launched from the app or from generated macOS shortcuts. It does not guarantee that every Windows game will run.

### Is this an alternative to CrossOver, Whisky, or Porting Kit?

It is a free setup helper for one specific Sikarugir/Wine workflow. It is not a general-purpose replacement for those projects and does not modify an existing Porting Kit installation.

### Does it include Windows, Steam, Wine, or games?

No. Releases contain only the Mac Steam Setup app. Required third-party components are downloaded from their official sources on the user's Mac, and users install games they own through Steam.

### Do Steam games run without the Steam client?

Generated game shortcuts can open a game directly, but games that use Steam DRM still require the Windows Steam process to run in the background.

### Why does macOS warn that Apple cannot check the app?

The current beta uses an ad-hoc signature and is not notarized by Apple. Download it only from this repository and use **System Settings → Privacy & Security → Open Anyway** for the first launch. Removing this warning for ordinary downloads would require Developer ID signing and Apple notarization.

## Feedback and game compatibility reports

Reports from real users are the most useful way to improve the project.

- Experiences, questions, and ideas: [GitHub Discussions](https://github.com/heung115/mac-steam-setup/discussions)
- Installation or launch problems: [bug report form](https://github.com/heung115/mac-steam-setup/issues/new?template=bug-report.yml)
- A Windows game you tested: [game compatibility form](https://github.com/heung115/mac-steam-setup/issues/new?template=game-compatibility.yml)

Successful games are worth reporting too. Before attaching a log or screenshot, remove account names, email addresses, local file paths, and any other personal information.

## Binary distribution

The small installer app produced by CI may be distributed as long as it does not include Steam, Wine, D3DMetal, or Sikarugir engines and templates. Third-party components must continue to be downloaded on the user's Mac from their official distribution URLs.

The app produced by `build.command` uses an ad-hoc signature intended for local testing. For a public GitHub Release, sign it with a Developer ID certificate from the Apple Developer Program, submit it for Apple notarization, and distribute the notarized result as a ZIP or DMG. Keep signing certificates and notarization credentials in encrypted CI secrets, never in the repository.

## License boundary

This repository's original code is licensed under the MIT License. The MIT License does not grant rights to Sikarugir, Wine, D3DMetal, Steam, or any game. Do not include a completed `Steam.app`, the Steam client, games, or Sikarugir engine and template archives in a release. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.
