import Darwin

// Phase 1 intentionally ships an inert helper target. Atoll does not embed,
// install, or invoke it until a provider-specific pass-through contract has
// been implemented and verified.
exit(EXIT_SUCCESS)
