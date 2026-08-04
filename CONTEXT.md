# Atoll

Atoll is the single macOS command surface around the display notch, including built-in capabilities for media, utilities, and AI coding-agent work.

## Language

**Code Island**:
The Atoll capability for observing and interacting with AI coding-agent sessions. It is part of Atoll, not a separately installed or running application.
_Avoid_: CodeIsland app, companion app, second application

**Code Island subsystem**:
The independently maintained part of the Atoll source tree that implements Code Island. Its boundary preserves CodeIsland provenance and supports deliberate upstream syncing while shipping only within Atoll.
_Avoid_: vendored app, external app, copied source dump

**Code Island tab**:
The stable built-in entry in Atoll's tab row whenever Code Island is enabled. Selecting it reveals Code Island's session dashboard; it is not a separate application to open or close. The subsystem continues monitoring while other Atoll tabs are selected, and the tab remains present during idle periods.
_Avoid_: dynamic tab, extension tab, temporary panel

**Code Island activation**:
The user's explicit consent to connect selected local coding tools to Atoll. Before activation, the tab provides read-only discovery and setup guidance but performs no hook, plugin, repair, or coding-tool configuration writes.
_Avoid_: first launch, automatic enrollment, implicit consent

**Code Island adoption**:
The guided, consent-based transfer from a separately installed CodeIsland to Atoll. Atoll detects existing preferences and integrations read-only, asks the user to quit the old app if needed, and imports only confirmed compatible state without deleting the old application.
_Avoid_: automatic migration, forced uninstall, silent takeover

**Code Island settings**:
The Atoll-owned settings area for activation, integrations, hook health, session behavior, mascots, and sounds. Shared application concerns and shortcuts remain in their existing Atoll settings areas.
_Avoid_: CodeIsland settings window, duplicated app settings

**Session dashboard**:
The primary view shown when the Code Island tab is selected. It presents a compact list of concurrent sessions ordered by urgency: waiting, working, then recently completed. Each row identifies the agent, project or session, status, and origin handoff without exposing prompt content.
_Avoid_: single-session view, approval queue

**Agent live activity**:
The Atoll-hosted compact presentation shown while at least one agent session is running or processing. It carries CodeIsland's mascots and motion, remains visible when no higher-priority Atoll activity needs the space, and never opens the full tab by itself.
_Avoid_: CodeIsland window, second panel, background dashboard

**Agent pop-out**:
An Atoll-hosted expansion for a meaningful agent transition. Starts receive a brief mascot animation, completions appear for about five seconds, failures receive a brief error treatment, and blocking requests remain visible as attention handoffs. Routine tool activity never produces a pop-out.
_Avoid_: notification window, standalone overlay, tool-call animation

**Activity arbitration**:
Atoll's policy for sharing the notch among live capabilities. System and privacy states win; blocking agent handoffs may interrupt noncritical content; processing agents share a secondary indicator where possible and otherwise yield; deferred agent pop-outs appear after higher-priority activity clears.
_Avoid_: agent-first mode, last-writer-wins

**Exact-origin suppression**:
The omission of an agent pop-out after Atoll positively matches the visible terminal tab or native agent window to that same session. An uncertain or application-only match never suppresses presentation.
_Avoid_: terminal-frontmost suppression, application-level suppression

**Provider capability**:
The highest verified behavior Atoll can safely offer for one coding tool. Monitoring covers session state and origin handoff; native attention additionally detects blocking requests without intercepting the provider's own prompt.
_Avoid_: supported, full support, parity

**Session metadata**:
The only agent-session information Atoll may retain: provider, project or session identity, origin-navigation handles, state, and timestamps. Prompt text, responses, commands, questions, and tool input are never stored at rest or exported.
_Avoid_: session history, transcript cache, message preview

**Agent session**:
An ongoing interaction between a user and one supported AI coding tool, including its activity, requests, and completion state.
_Avoid_: process, tab, panel

**Local agent workflow**:
The complete on-Mac experience for discovering supported coding tools, installing their hooks, observing sessions, noticing when input is required, and returning to the originating terminal or app.
_Avoid_: status widget, read-only monitor

**Origin surface**:
The terminal or native agent app where an agent session began. It remains the sole place for approving permissions and answering agent questions.
_Avoid_: response target, secondary client

**Attention handoff**:
Atoll's minimal presentation of a blocking agent state: agent, project or session, waiting reason, and an action that returns the user to its origin surface. It shows no command or question content and never submits the user's decision or answer.
_Avoid_: approval card, answer card, remote control

**Buddy**:
The optional iPhone and Apple Watch companion experience. Buddy is outside the first merged release, along with remote-host sessions.
_Avoid_: Code Island core, required companion
