# Third-party notices

Mac Steam Setup's source code and small installer application do not contain Steam, Windows games, Sikarugir engines/templates, Wine, or D3DMetal. The installer downloads fixed upstream releases directly to the user's Mac.

- The setup orchestration was informed by `mirpo/windows-steam-on-apple-silicon`, released under CC0-1.0. The CC0 grant covers that repository's files only.
- Sikarugir components have their own mixed licensing. Its modified Configure component is described as LGPL-2.1, while its launcher, creator, master wrapper, engines, and renderer payloads are not covered by that LGPL grant. They are not relicensed by this project.
- D3DMetal is proprietary Apple software. The included Apple license in the upstream Sikarugir template restricts distribution to non-commercial purposes and limits permitted use. This project's MIT license grants no rights to D3DMetal.
- Steam and games are proprietary to Valve and their respective publishers. They are not redistributed. Users download Steam from Valve and must own or otherwise be licensed to use each game.

Upstream references:

- https://github.com/mirpo/windows-steam-on-apple-silicon
- https://github.com/Sikarugir-App/Sikarugir
- https://store.steampowered.com/subscriber_agreement/
