---
status: accepted
---

# Use an Atoll tab and an agent live activity

Code Island will have two Atoll-hosted presentations. Its persistent tab uses Atoll's sizing, navigation, typography, and interaction patterns for the session dashboard. While any agent session is running or processing, a compact agent live activity uses CodeIsland's mascots, status language, and motion whenever no higher-priority Atoll activity owns the notch. The compact activity does not select the Code Island tab or steal focus. Event-driven expansions retain CodeIsland's visual identity within Atoll's geometry and lifecycle. We chose this dual-mode design to preserve CodeIsland's ambient character without embedding its standalone notch window inside another notch application.

## Consequences

- Atoll remains the only surface and window coordinator; CodeIsland's `PanelWindowController` is not reused.
- Code Island supplies reusable state and visual components, while Atoll owns placement, sizing, transitions, and activity priority.
- Original CodeIsland styling is a feature-state presentation, not an independent application shell.
- Cross-feature priority follows the cooperative activity-arbitration policy below rather than either application's existing behavior.

## Event policy

- A session start produces only a brief mascot animation.
- An approval or question opens Code Island and keeps the minimal attention handoff visible until the user hands off or the provider resolves it.
- A completion produces an original-styled pop-out for about five seconds.
- A tool failure produces a brief original-styled error pop-out.
- Routine tool activity remains in the compact live activity.

## Activity arbitration

- System and privacy indicators take priority over Code Island.
- A blocking agent handoff may interrupt noncritical content and select the Code Island tab.
- A processing agent uses a secondary indicator when the active layout supports one and otherwise yields to music, timers, recording, and similar live activities.
- Completion and failure pop-outs queue behind higher-priority activity and appear when that activity clears.

## Smart suppression

- Atoll suppresses an agent pop-out only after positively matching the exact visible terminal tab or native agent window to the originating session.
- A frontmost terminal or agent application without an exact session match does not suppress presentation.
- When matching is unavailable or uncertain, Atoll presents the event.
- Suppression affects the pop-out, not session-state updates or the compact live activity.
