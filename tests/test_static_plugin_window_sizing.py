import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class StaticPluginWindowSizingTests(unittest.TestCase):
    def test_all_runtime_sizing_paths_use_shared_plugin_size(self):
        for relative_path in (
            "DynamicIsland/ContentView.swift",
            "DynamicIsland/models/DynamicIslandViewModel.swift",
            "DynamicIsland/DynamicIslandApp.swift",
        ):
            with self.subTest(path=relative_path):
                source = (REPOSITORY_ROOT / relative_path).read_text()
                self.assertTrue(
                    "StaticPluginLayout.resolvedSize(" in source,
                    f"{relative_path} does not use the shared static-plugin window size",
                )

    def test_content_view_keeps_selected_plugin_lookup_for_rendering(self):
        source = (REPOSITORY_ROOT / "DynamicIsland/ContentView.swift").read_text()
        self.assertTrue(
            "private func currentStaticPlugin()" in source,
            "ContentView lost the selected-plugin lookup used by its render switch",
        )

    def test_plugin_reload_recreates_web_view_and_resizes_window(self):
        content_source = (REPOSITORY_ROOT / "DynamicIsland/ContentView.swift").read_text()
        self.assertTrue(
            "staticPluginManager.reloadRevision" in content_source,
            "ContentView does not key plugin rendering by the reload revision",
        )

        app_source = (REPOSITORY_ROOT / "DynamicIsland/DynamicIslandApp.swift").read_text()
        self.assertTrue(
            "StaticPluginManager.shared.$reloadRevision" in app_source,
            "AppDelegate does not observe plugin reloads for window resizing",
        )

    def test_runtime_sizing_uses_each_window_screen(self):
        for relative_path in (
            "DynamicIsland/ContentView.swift",
            "DynamicIsland/models/DynamicIslandViewModel.swift",
        ):
            with self.subTest(path=relative_path):
                source = (REPOSITORY_ROOT / relative_path).read_text()
                self.assertTrue(
                    "visibleScreenHeight: currentScreenVisibleHeight" in source,
                    f"{relative_path} does not use its view model's screen height",
                )

        app_source = (REPOSITORY_ROOT / "DynamicIsland/DynamicIslandApp.swift").read_text()
        self.assertTrue(
            "private func staticPluginAdjustedSize(_ size: CGSize, for screen: NSScreen)"
            in app_source,
            "AppDelegate has no per-window static-plugin sizing helper",
        )
        self.assertTrue(
            "visibleScreenHeight: screen.visibleFrame.height" in app_source,
            "AppDelegate does not clamp against each window screen",
        )
        self.assertTrue(
            "staticPluginAdjustedSize(size, for: screen)" in app_source,
            "AppDelegate does not apply per-window static-plugin sizing",
        )


if __name__ == "__main__":
    unittest.main()
