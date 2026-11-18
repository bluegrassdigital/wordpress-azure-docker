#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WorkflowSecurity(unittest.TestCase):
    def run_step(self, step, directory, **env):
        workflow = (ROOT / ".github/workflows/publish-release.yml").read_text()
        block = workflow.split(f"      - name: {step}\n", 1)[1]
        block = block.split("      - name:", 1)[0].split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in block.splitlines() if line.startswith("          "))
        return subprocess.run(
            ["bash", "-e", "-c", script],
            cwd=directory,
            env={**os.environ, **env},
            capture_output=True,
            text=True,
        )

    def test_release_tag_selection_and_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            for ref_type, ref_name, input_tag, expected in [
                ("tag", "v2026.11.18", "", "v2026.11.18"),
                ("branch", "master", "v2026.11.19", "v2026.11.19"),
                ("branch", "master", "release", None),
                ("branch", "master", "v spaced", None),
            ]:
                with self.subTest(ref_type=ref_type, ref_name=ref_name, input_tag=input_tag):
                    output.write_text("")
                    result = self.run_step(
                        "Determine tag", directory, REF_TYPE=ref_type, REF_NAME=ref_name,
                        INPUT_TAG=input_tag, GITHUB_OUTPUT=str(output),
                    )
                    if expected is None:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(output.read_text(), "")
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(output.read_text(), f"tag={expected}\n")

    def test_release_notes_match_one_exact_heading(self):
        with tempfile.TemporaryDirectory() as directory:
            changelog = Path(directory) / "CHANGELOG.md"
            changelog.write_text(
                "#### v2026.11.18\nSelected release\n"
                "#### v2026x11y18\nAnother release\n"
            )
            result = self.run_step(
                "Extract release notes from CHANGELOG", directory, TAG="v2026.11.18",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((Path(directory) / "RELEASE_NOTES.md").read_text(), "Selected release\n")


class EnvironmentSecurity(unittest.TestCase):
    def write_profile(self, profile, **values):
        writer = os.environ.get("ENV_WRITER", str(ROOT / "scripts/write-container-env.sh"))
        subprocess.run(
            ["bash", writer, str(profile)],
            env={"PATH": os.defpath, **values},
            check=True,
        )

    def test_snapshot_round_trips_literal_values(self):
        values = {
            "WP_LABEL": "O'Brien \"WordPress\"",
            "WP_MESSAGE": "first line\nsecond line",
            "WP_EMPTY": "",
        }
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "env.sh"
            self.write_profile(profile, **values)
            self.assertEqual(profile.stat().st_mode & 0o777, 0o600)
            for shell in ("sh", "bash"):
                with self.subTest(shell=shell):
                    result = subprocess.run(
                        [shell, "-ec", '. "$1"; env -0', "_", str(profile)],
                        env={"PATH": os.defpath},
                        capture_output=True,
                        check=True,
                    )
                    exports = dict(
                        entry.split("=", 1) for entry in result.stdout.decode().split("\0") if entry
                    )
                    self.assertEqual({name: exports[name] for name in values}, values)

    def test_snapshot_replaces_stale_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "env.sh"
            self.write_profile(profile, WP_REMOVED="old", WP_LABEL="old")
            self.write_profile(profile, WP_LABEL="new")
            self.assertIn("export WP_LABEL='new'", profile.read_text())
            self.assertNotIn("WP_REMOVED", profile.read_text())


class ConfigSecurity(unittest.TestCase):
    def run_config(self, **settings):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copyfile(ROOT / "file-templates/wp-config-docker.php", root / "wp-config.php")
            (root / "wp-settings.php").write_text(
                "<?php echo json_encode(["
                "defined('DISALLOW_FILE_EDIT') ? DISALLOW_FILE_EDIT : null, "
                "defined('WP_MEMORY_LIMIT') ? WP_MEMORY_LIMIT : null"
                "]);"
            )
            settings_file = settings.pop("file_contents", None)
            if settings_file is not None:
                file_path = root / "settings.json"
                file_path.write_text(settings_file)
                settings["WORDPRESS_CONFIG_CONSTANTS_FILE"] = str(file_path)
            return subprocess.run(
                ["php", str(root / "wp-config.php")],
                env={
                    **os.environ,
                    "HOST_DOMAIN": "wordpress.example",
                    "MYSQLCONNSTR_defaultConnection": "Data Source=db;Database=wordpress;",
                    **settings,
                },
                capture_output=True,
                text=True,
            )

    def test_valid_inline_and_mounted_settings(self):
        values = {"DISALLOW_FILE_EDIT": False, "WP_MEMORY_LIMIT": "256M"}
        for settings in (
            {"WORDPRESS_CONFIG_CONSTANTS": json.dumps(values)},
            {
                "WORDPRESS_CONFIG_CONSTANTS": "{}",
                "file_contents": json.dumps(values),
            },
        ):
            with self.subTest(settings=settings):
                result = self.run_config(**settings)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), [False, "256M"])

    def test_invalid_settings_stop_bootstrap(self):
        for settings, error in (
            ({"WORDPRESS_CONFIG_CONSTANTS": "[]"}, "must be a JSON object"),
            ({"WORDPRESS_CONFIG_CONSTANTS": "0"}, "must be a JSON object"),
            ({"WORDPRESS_CONFIG_CONSTANTS": '{"DISALLOW_FILE_EDIT":"true"}'}, "require JSON true or false"),
            ({"WORDPRESS_CONFIG_CONSTANTS": '{"WP_MEMORY_LIMIT":"4M"}'}, "between 16M and 2G"),
            ({"WORDPRESS_CONFIG_CONSTANTS": '{"UNSUPPORTED":true}'}, "unsupported or already defined"),
            ({"WORDPRESS_CONFIG_CONSTANTS_FILE": "settings.json"}, "readable local file"),
            ({"WORDPRESS_CONFIG_EXTRA": "legacy setting"}, "is no longer supported"),
        ):
            with self.subTest(settings=settings):
                result = self.run_config(**settings)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(error, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
