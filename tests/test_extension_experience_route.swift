import Foundation

@main
struct ExtensionExperienceRouteTests {
    static func main() throws {
        let candidates = [
            ExtensionExperienceRouteCandidate(
                experienceID: "codex-dashboard",
                bundleIdentifier: "com.example.codex",
                hasTabConfiguration: true
            ),
            ExtensionExperienceRouteCandidate(
                experienceID: "minimal-only",
                bundleIdentifier: "com.example.codex",
                hasTabConfiguration: false
            ),
            ExtensionExperienceRouteCandidate(
                experienceID: "other-dashboard",
                bundleIdentifier: "com.example.other",
                hasTabConfiguration: true
            )
        ]

        try expect(
            ExtensionExperienceRouteResolver.resolveTargetExperienceID(
                liveActivityBundleIdentifier: "com.example.codex",
                metadata: [ExtensionExperienceRouteResolver.targetExperienceMetadataKey: "codex-dashboard"],
                extensionTabsEnabled: true,
                candidates: candidates
            ) == "codex-dashboard",
            "valid linked tab resolves"
        )

        try expect(
            ExtensionExperienceRouteResolver.resolveTargetExperienceID(
                liveActivityBundleIdentifier: "com.example.codex",
                metadata: [:],
                extensionTabsEnabled: true,
                candidates: candidates
            ) == nil,
            "missing metadata preserves default routing"
        )

        try expect(
            ExtensionExperienceRouteResolver.resolveTargetExperienceID(
                liveActivityBundleIdentifier: "com.example.codex",
                metadata: [ExtensionExperienceRouteResolver.targetExperienceMetadataKey: "codex-dashboard"],
                extensionTabsEnabled: false,
                candidates: candidates
            ) == nil,
            "disabled extension tabs preserve default routing"
        )

        try expect(
            ExtensionExperienceRouteResolver.resolveTargetExperienceID(
                liveActivityBundleIdentifier: "com.example.codex",
                metadata: [ExtensionExperienceRouteResolver.targetExperienceMetadataKey: "other-dashboard"],
                extensionTabsEnabled: true,
                candidates: candidates
            ) == nil,
            "bundle mismatch is rejected"
        )

        try expect(
            ExtensionExperienceRouteResolver.resolveTargetExperienceID(
                liveActivityBundleIdentifier: "com.example.codex",
                metadata: [ExtensionExperienceRouteResolver.targetExperienceMetadataKey: "minimal-only"],
                extensionTabsEnabled: true,
                candidates: candidates
            ) == nil,
            "minimalistic-only experiences are not treated as tabs"
        )

        try expect(
            ExtensionExperienceRouteResolver.resolveTargetExperienceID(
                liveActivityBundleIdentifier: "com.example.codex",
                metadata: [ExtensionExperienceRouteResolver.targetExperienceMetadataKey: "missing"],
                extensionTabsEnabled: true,
                candidates: candidates
            ) == nil,
            "stale target identifiers preserve default routing"
        )

        let threadURL = CodexThreadActionResolver.url(
            sectionID: "recent-0",
            elementIndex: 0,
            metadata: [
                "\(CodexThreadActionResolver.metadataPrefix)recent-0.0": "codex://threads/session-1"
            ]
        )
        try expect(threadURL?.absoluteString == "codex://threads/session-1", "Codex thread action resolves")
        try expect(
            CodexThreadActionResolver.sectionURL(
                sectionID: "recent-0",
                elementCount: 1,
                metadata: [
                    "\(CodexThreadActionResolver.metadataPrefix)recent-0.0": "codex://threads/session-1"
                ]
            )?.absoluteString == "codex://threads/session-1",
            "single-conversation section promotes its thread action to the whole card"
        )
        try expect(
            CodexThreadActionResolver.sectionURL(
                sectionID: "recent-0",
                elementCount: 2,
                metadata: [
                    "\(CodexThreadActionResolver.metadataPrefix)recent-0.0": "codex://threads/session-1"
                ]
            ) == nil,
            "multi-element sections keep element-level interaction"
        )
        try expect(
            CodexThreadActionResolver.url(
                sectionID: "recent-0",
                elementIndex: 1,
                metadata: [
                    "\(CodexThreadActionResolver.metadataPrefix)recent-0.0": "codex://threads/session-1"
                ]
            ) == nil,
            "missing element action remains inert"
        )
        try expect(
            !CodexThreadActionResolver.isCodexThreadURL(URL(string: "https://example.com")!),
            "non-Codex URLs are rejected"
        )

        try expect(
            ExtensionExperienceHeightResolver.preferredHeight(
                requestedHeight: 420,
                baseHeight: 200,
                standardMaximumHeight: 332,
                builtInMaximumHeight: 420,
                isBuiltInExperience: true
            ) == 420,
            "built-in Codex can use the taller expanded height"
        )
        try expect(
            ExtensionExperienceHeightResolver.preferredHeight(
                requestedHeight: 420,
                baseHeight: 200,
                standardMaximumHeight: 332,
                builtInMaximumHeight: 420,
                isBuiltInExperience: false
            ) == 332,
            "third-party experiences keep the existing height clamp"
        )

        print("ExtensionExperienceRouteTests: PASS")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw TestFailure(message: message)
        }
    }
}

private struct TestFailure: Error {
    let message: String
}
