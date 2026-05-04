from __future__ import annotations

import json
from pathlib import Path
import unittest

import app


class UpdateManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        contract_path = Path(__file__).parent / "fixtures" / "update-manifest-contract.json"
        cls.contract = json.loads(contract_path.read_text(encoding="utf-8"))

    def test_resolve_update_feed_request_url_matches_contract(self) -> None:
        for case in self.contract["resolve_update_feed_request_url"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(
                    app.resolve_update_feed_request_url(case["source"]),
                    case["expected"],
                )

    def test_parse_release_payload_matches_contract(self) -> None:
        for case in self.contract["manifest_cases"]:
            payload = case["payload"]
            for platform, expected in case["expected"].items():
                with self.subTest(case=case["name"], platform=platform):
                    result = app.parse_release_payload(payload, platform, case["current_version"])
                    self.assertEqual(result["status"], expected["status"])
                    self.assertEqual(result["latestVersion"], expected["latestVersion"])
                    self.assertEqual(result["updateAvailable"], expected["updateAvailable"])
                    self.assertEqual(result["releaseUrl"], expected["releaseUrl"])
                    self.assertEqual(result["downloadUrl"], expected["downloadUrl"])
                    self.assertEqual(result["assetName"], expected["assetName"])
                    self.assertTrue(result["message"])

    def test_normalize_update_result_cleans_null_like_strings(self) -> None:
        case = self.contract["normalize_update_result"]
        result = app.normalize_update_result(case["input"])

        self.assertIsNotNone(result)
        assert result is not None
        for key, expected_value in case["expected"].items():
            with self.subTest(field=key):
                self.assertEqual(result[key], expected_value)

    def test_parse_release_payload_rejects_missing_schema_version(self) -> None:
        with self.assertRaisesRegex(ValueError, "schema_version must be 1"):
            app.parse_release_payload(
                {
                    "latest_version": "0.1.2",
                    "platforms": {
                        "windows": {
                            "folder_url": "https://example.com/windows",
                        }
                    },
                },
                "desktop",
            )

    def test_parse_release_payload_rejects_wrong_schema_version(self) -> None:
        with self.assertRaisesRegex(ValueError, "schema_version must be 1"):
            app.parse_release_payload(
                {
                    "schema_version": 2,
                    "latest_version": "0.1.2",
                    "platforms": {
                        "windows": {
                            "folder_url": "https://example.com/windows",
                        }
                    },
                },
                "desktop",
            )


if __name__ == "__main__":
    unittest.main()
