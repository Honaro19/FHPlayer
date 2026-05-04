package com.fhplayer.mobile

import org.json.JSONObject
import java.nio.charset.StandardCharsets
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class UpdateManifestParserTest {
    private val contract: JSONObject by lazy {
        val classLoader = checkNotNull(UpdateManifestParserTest::class.java.classLoader)
        val stream = checkNotNull(classLoader.getResourceAsStream("update-manifest-contract.json"))
        val jsonText = stream.bufferedReader(StandardCharsets.UTF_8).use { it.readText() }
        JSONObject(jsonText)
    }

    @Test
    fun `parse release payload matches contract fixtures`() {
        val cases = contract.getJSONArray("manifest_cases")
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val payload = case.getJSONObject("payload")
            val currentVersion = case.getString("current_version")
            val expectedByPlatform = case.getJSONObject("expected")
            val platformKeys = expectedByPlatform.keys()
            while (platformKeys.hasNext()) {
                val platform = platformKeys.next()
                val expected = expectedByPlatform.getJSONObject(platform)
                val result = UpdateManifestParser.parseReleasePayload(payload, platform, currentVersion, "2026-04-20T20:31:54Z")

                assertEquals(expected.getString("status"), result.getString("status"), "${case.getString("name")} [$platform] status")
                assertEquals(expected.getString("latestVersion"), result.getString("latestVersion"), "${case.getString("name")} [$platform] latestVersion")
                assertEquals(expected.getBoolean("updateAvailable"), result.getBoolean("updateAvailable"), "${case.getString("name")} [$platform] updateAvailable")
                assertEquals(expected.getString("releaseUrl"), result.getString("releaseUrl"), "${case.getString("name")} [$platform] releaseUrl")
                assertEquals(expected.getString("downloadUrl"), result.getString("downloadUrl"), "${case.getString("name")} [$platform] downloadUrl")
                assertEquals(expected.getString("assetName"), result.getString("assetName"), "${case.getString("name")} [$platform] assetName")
                assertTrue(result.getString("message").isNotBlank(), "${case.getString("name")} [$platform] message")
            }
        }
    }

    @Test
    fun `parse release payload rejects missing schema version`() {
        val error =
            assertFailsWith<IllegalArgumentException> {
                UpdateManifestParser.parseReleasePayload(
                    JSONObject(
                        """
                        {
                          "latest_version": "0.1.2",
                          "platforms": {
                            "windows": {
                              "folder_url": "https://example.com/windows"
                            }
                          }
                        }
                        """.trimIndent(),
                    ),
                    "desktop",
                    "0.1.1",
                    "2026-04-20T20:31:54Z",
                )
            }

        assertTrue(error.message.orEmpty().contains("schema_version must be 1"))
    }

    @Test
    fun `parse release payload rejects wrong schema version`() {
        val error =
            assertFailsWith<IllegalArgumentException> {
                UpdateManifestParser.parseReleasePayload(
                    JSONObject(
                        """
                        {
                          "schema_version": 2,
                          "latest_version": "0.1.2",
                          "platforms": {
                            "windows": {
                              "folder_url": "https://example.com/windows"
                            }
                          }
                        }
                        """.trimIndent(),
                    ),
                    "desktop",
                    "0.1.1",
                    "2026-04-20T20:31:54Z",
                )
            }

        assertTrue(error.message.orEmpty().contains("schema_version must be 1"))
    }
}
