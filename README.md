# Telmi for muOS

A port of [Telmi OS](https://telmi.fr), the open-source storyteller and music player for kids, to Anbernic handhelds running [muOS](https://muos.dev).
It runs as a muOS application with LÖVE 11.5.

It follows the official C code ([DantSu/Telmi-story-teller](https://github.com/DantSu/Telmi-story-teller)) closely, so you get the same behaviour as Telmi OS:

- the same screens, using the official Telmi images and fonts
- interactive stories in Telmi Sync format (`nodes.json`): tiles or single-title view, inventory, timeline, night mode, resuming a saved story
- the music player, with albums, repeat modes and the screen turning off
- the same `Saves/` files (`.parameters`, `.storytellerState`, per-story saves)
- lock (hold MENU), volume and brightness limits, auto-sleep

The **Telmi Sync** desktop app recognises the SD card, so you can download stories, podcasts and music to it as you would on a Miyoo Mini running Telmi OS.

> Tested on an Anbernic RG40XXV running muOS: stories and music play, and Telmi Sync recognises the card and transfers stories to it. Bug reports are welcome. Attach `telmi.log` from the app folder.

## Download

Download `Telmi-vX.Y.Z.zip` from the [Releases](https://github.com/jeromarsan/Telmi-App-MuOS/releases) page. It contains:

- `Telmi/`: the app, to copy to `MUOS/application/`
- `sdcard-root/`: its **contents** go at the root of the card that will hold the stories. It holds `autorun.inf`, `Saves/.parameters`, and empty `Stories/`, `Music/` and `Saves/Stories/` folders.

## Requirements

- muOS
- the PortMaster **LÖVE 11.5** runtime (`love_11.5`). If it is not already installed, install any LÖVE-based port from PortMaster and the runtime comes with it.

## Installation

1. Copy the `Telmi/` folder to `MUOS/application/Telmi/` on the SD card. If you cloned the repository instead of using the release zip, the clone is the app folder: you can skip `sdcard-root/`, `README.md` and `LICENSE`.
2. Copy the **contents** of `sdcard-root/` to the **root** of the card that will hold the stories (SD1 / Primary Storage or SD2):
   ```
   autorun.inf        marker "TelmiOS": makes Telmi Sync recognise the card
   Saves/.parameters  Telmi settings (editable in Telmi Sync)
   ```
   The release zip also contains empty `Stories/`, `Music/` and `Saves/Stories/` folders. If they are missing, the app creates them at that root on first launch.
3. Put the card in your PC. Telmi Sync shows it as **TelmiOS v99.0.0**. Version 99 stops Telmi Sync from offering a Telmi OS update, which would be useless on muOS.

At launch, Telmi picks the first root (`/mnt/sdcard`, `/mnt/mmc`, …) that contains an `autorun.inf` with "TelmiOS". If none has one, it uses the first root with a non-empty `Stories/` folder. If that fails too, it uses its own folder. To force a folder, set `TELMI_ROOT` at the top of `mux_launch.sh`.

## Controls

| Button | Action |
|---|---|
| D-pad left / right | choose; −10 s / +10 s while playing |
| D-pad up / down | change row in the tile view; show the time bar while playing |
| A or B | OK |
| X or Y | Home |
| START or SELECT | pause / play |
| MENU | tiles ↔ single story; inside a story: save and go back to the title. Music: player ↔ albums |
| hold MENU | lock / unlock |
| L1 / R1 | volume − / + (capped by `audioVolumeMax`) |
| MENU + L1/R1 or MENU + L2/R2 | brightness − / + (capped by `screenBrightnessMax`) |
| MENU + START | quit Telmi |

A black screen with only the player controls while a story plays is normal. Many story steps are audio-only, and Telmi OS turns the screen off the same way.

## Auto-sleep

As on Telmi OS, Telmi saves and **powers off the console** after the inactivity time set in `.parameters`, and 5 s after night mode ends.
To go back to the muOS menu instead, set `FIN_INACTIVITE="quitter"` at the top of `mux_launch.sh`.

## muOS-specific adaptations

- Brightness goes through `/opt/muos/script/device/bright.sh`, using Telmi's brightness curve. Telmi restores the muOS brightness when it quits.
- Volume is applied in software, using Telmi's dB curve. L1/R1 replace the volume keys because muOS keeps those keys for itself.
- Telmi holds muOS idle inhibit while it runs, so muOS does not dim the screen or suspend the console.
- Audio stored outside the app folder is loaded into RAM, because LÖVE can only stream files from its own folder.

## Credits & license

- Telmi OS, Telmi Sync, the images in `res/` and the Telmi name: [DantSu](https://github.com/DantSu) ([telmi.fr](https://telmi.fr)). Telmi OS is GPL-3.0.
- Exo 2 font: Natanael Gama, SIL Open Font License.
- This port is a derivative work of Telmi OS, released under the **GNU GPL v3.0** (see `LICENSE`).

This project is unofficial and not affiliated with Telmi.
