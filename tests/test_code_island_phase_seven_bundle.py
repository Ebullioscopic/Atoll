import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"
VERIFIER = ROOT / "scripts" / "verify-code-island-bundle.sh"


class CodeIslandPhaseSevenBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary_directory.name)
        self.app = self.root / "Atoll.app"
        self.resources = self.app / "Contents" / "Resources"
        self.package_bundle = self.resources / "CodeIsland_CodeIslandUI.bundle"

        (self.app / "Contents" / "MacOS").mkdir(parents=True)
        (self.app / "Contents" / "Helpers").mkdir(parents=True)
        (self.package_bundle / "Sounds").mkdir(parents=True)
        (self.package_bundle / "en.lproj").mkdir(parents=True)
        (self.package_bundle / "ThirdPartyNotices").mkdir(parents=True)

        self._write_executable(self.app / "Contents" / "MacOS" / "Atoll")
        self._write_executable(
            self.app / "Contents" / "Helpers" / "codeisland-bridge"
        )
        for sound in (
            "8bit_approval.wav",
            "8bit_complete.wav",
            "8bit_error.wav",
            "8bit_start.wav",
        ):
            source = (
                PACKAGE / "Sources" / "CodeIslandUI" / "Resources" / "Sounds" / sound
            )
            (self.package_bundle / "Sounds" / sound).write_bytes(source.read_bytes())
        (self.package_bundle / "CodeIsland.xcstrings").write_text(
            '{"sourceLanguage":"en","strings":{"Code Island":{}},"version":"1.0"}\n'
        )
        (
            self.package_bundle
            / "ThirdPartyNotices"
            / "CodeIsland-LICENSE.txt"
        ).write_text((PACKAGE / "LICENSE").read_text())

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_structural_release_bundle_passes(self):
        result = self._verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Code Island bundle verification passed", result.stdout)

    def test_missing_selected_sound_fails(self):
        (self.package_bundle / "Sounds" / "8bit_error.wav").unlink()
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("selected Code Island sounds", result.stderr)

    def test_modified_selected_sound_fails(self):
        (self.package_bundle / "Sounds" / "8bit_error.wav").write_bytes(b"RIFFchanged")
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("selected Code Island sound is not the audited upstream asset", result.stderr)

    def test_nested_standalone_app_fails(self):
        nested = self.app / "Contents" / "Resources" / "CodeIsland.app"
        nested.mkdir()
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("standalone CodeIsland application", result.stderr)

    def test_nested_standalone_code_island_executable_fails(self):
        nested = self.app / "Contents" / "Frameworks" / "Legacy" / "CodeIslandUpdater"
        nested.parent.mkdir(parents=True)
        self._write_executable(nested)
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("forbidden standalone CodeIsland executable", result.stderr)

    def test_dependency_helper_app_does_not_count_as_a_second_product(self):
        nested = (
            self.app
            / "Contents"
            / "Frameworks"
            / "Sparkle.framework"
            / "Resources"
            / "Updater.app"
        )
        nested.mkdir(parents=True)
        result = self._verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_bundled_attribution_fails(self):
        (
            self.package_bundle
            / "ThirdPartyNotices"
            / "CodeIsland-LICENSE.txt"
        ).unlink()
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CodeIsland MIT license", result.stderr)

    def test_truncated_bundled_attribution_fails(self):
        (
            self.package_bundle
            / "ThirdPartyNotices"
            / "CodeIsland-LICENSE.txt"
        ).write_text("MIT License\n\nCopyright (c) 2026 wxtsky\n")
        result = self._verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CodeIsland MIT license is incomplete", result.stderr)

    def test_release_and_ci_invoke_the_artifact_verifier(self):
        ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
        release = (ROOT / ".github" / "workflows" / "release.yml").read_text()

        self.assertIn("scripts/verify-code-island-bundle.sh", ci)
        self.assertIn("scripts/verify-code-island-bundle.sh", release)
        self.assertIn("--require-signature", release)
        self.assertIn("spctl --assess --type open", release)
        self.assertIn("--context context:primary-signature", release)

    def test_upgrade_and_rollback_gates_remain_in_ci(self):
        ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
        release_regression = (
            ROOT / "tests" / "CodeIslandPhaseSevenReleaseRegression.swift"
        ).read_text()
        rollback_regression = (
            ROOT / "tests" / "CodeIslandPhaseFiveAdoptionRegression.swift"
        ).read_text()

        self.assertIn("Validate Code Island Phase 5 contracts", ci)
        self.assertIn("Validate Code Island Phase 7 release contracts", ci)
        self.assertIn("phaseSixMetadataArchiveStillDecodesWithoutMigration", release_regression)
        self.assertIn("verifyReversibleLegacyAdoption", rollback_regression)
        self.assertIn(
            "verifyMissingConfigurationStillRestoresAdoptedHooks",
            rollback_regression,
        )

    def _verify(self):
        return subprocess.run(
            [str(VERIFIER), str(self.app)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    @staticmethod
    def _write_executable(path):
        path.write_text("#!/bin/sh\nexit 0\n")
        os.chmod(path, 0o755)


if __name__ == "__main__":
    unittest.main()
