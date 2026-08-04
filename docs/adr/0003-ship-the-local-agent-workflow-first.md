---
status: accepted
---

# Ship the local agent workflow first

The first Atoll release containing Code Island will preserve the complete local agent workflow: supported local coding-tool integrations, hook installation and repair, live session status, attention signals for permissions and questions, terminal or native-app activation, notifications, sounds, mascots, and relevant settings. Permission decisions and question responses remain in the originating coding tool. Remote-host sessions and the iPhone or Apple Watch Buddy are deferred. We chose this boundary because remote SSH management and companion networking add separate security, entitlement, lifecycle, and test surfaces without being required for a useful local Code Island panel.

## Consequences

- Deferral does not remove remote hosts or Buddy from the longer-term product direction.
- The first release does not require Code Island's Bluetooth or companion-networking integration.
- The local workflow must provide a reliable handoff to the originating tool; a passive status list without attention routing is not sufficient.
