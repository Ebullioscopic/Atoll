# Upstream and attribution

## Source project

This repository is an independent open-source derivative of **Atoll**
(originally known as DynamicIsland) by **Ebullioscopic**:

- Official repository: <https://github.com/Ebullioscopic/Atoll>
- Upstream license: GNU General Public License v3.0
- Upstream acknowledgements: the original Atoll `ReadMe.md`, `NOTICE`, and
  `LICENSE` files are retained as part of this source tree.

The project also preserves Atoll's existing acknowledgements for upstream
work such as Boring.Notch and other listed open-source dependencies. Those
projects remain credited by the upstream notices and README.

## What this repository adds

The main purpose of this repository is the **built-in Codex utility** for
Atoll. It connects local Codex Hook events to Atoll's existing notch and Live
Activity presentation surfaces so users can: 

- see running, approval-waiting, and recently completed Codex tasks;
- open the related Codex conversation from the expanded task view;
- configure Codex visibility and notification behavior from Atoll Settings;
- keep the feature inside the single Atoll application rather than installing
  a separate CodexAtoll menu-bar app.

The integration is local-first. It is designed around Codex Hooks and local
state, does not parse transcripts, does not upload prompts or source code, and
does not start a network service for the Atoll integration.

## Relationship to upstream

This project is not an official Atoll release and changes here may diverge
from upstream Atoll. When synchronizing future changes, keep the upstream
copyright, license, notices, and third-party attributions intact. Issues that
are unrelated to the Codex integration should generally be checked against
the upstream project first.
