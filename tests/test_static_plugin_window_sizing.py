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


if __name__ == "__main__":
    unittest.main()
