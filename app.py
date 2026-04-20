from __future__ import annotations

import json
import os
import ipaddress
import logging
from logging.handlers import RotatingFileHandler
import re
import ssl
import subprocess
import sys
import webbrowser
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import parse_qs, urlparse


HOST = "127.0.0.1"
PORT = 8765
BASE_DIR = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
STATIC_DIR = BASE_DIR / "static"
UPDATE_FEED_URL = os.environ.get("FHPLAYER_UPDATE_FEED_URL", "https://api.github.com/repos/Honaro19/FHPlayer/releases/latest")
VERSION_PATTERN = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def read_app_version() -> str:
    candidate_paths = [
        BASE_DIR / "VERSION",
        Path(__file__).resolve().parent / "VERSION",
    ]
    for candidate_path in candidate_paths:
        if candidate_path.exists():
            app_version = candidate_path.read_text(encoding="utf-8").strip()
            if VERSION_PATTERN.fullmatch(app_version):
                return app_version.lstrip("v")
    return "0.0.0"


APP_VERSION = read_app_version()


def resolve_app_data_dir() -> Path:
    if sys.platform == "win32":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            return Path(local_app_data) / "FHPlayer"
    return Path.home() / ".fhplayer"


APP_DATA_DIR = resolve_app_data_dir()
LIBRARY_ROOT = APP_DATA_DIR / "Library"
SETTINGS_PATH = APP_DATA_DIR / "settings.json"
LOGS_DIR = APP_DATA_DIR / "Logs"
APP_LOG_PATH = LOGS_DIR / "fhplayer.log"
LIBRARY_DIRECTORIES = {
    "video": LIBRARY_ROOT / "Videos",
    "videos": LIBRARY_ROOT / "Videos",
    "funscript": LIBRARY_ROOT / "Funscripts",
    "funscripts": LIBRARY_ROOT / "Funscripts",
    "export": LIBRARY_ROOT / "Exports",
    "exports": LIBRARY_ROOT / "Exports",
}
LOGGER = logging.getLogger("fhplayer")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def normalize_update_result(result: Any) -> dict[str, Any] | None:
    if not isinstance(result, dict):
        return None

    return {
        "status": str(result.get("status", "")).strip() or "unknown",
        "checkedAt": str(result.get("checkedAt", "")).strip(),
        "currentVersion": str(result.get("currentVersion", "")).strip() or APP_VERSION,
        "latestVersion": str(result.get("latestVersion", "")).strip(),
        "updateAvailable": bool(result.get("updateAvailable", False)),
        "releaseUrl": str(result.get("releaseUrl", "")).strip(),
        "downloadUrl": str(result.get("downloadUrl", "")).strip(),
        "assetName": str(result.get("assetName", "")).strip(),
        "publishedAt": str(result.get("publishedAt", "")).strip(),
        "message": str(result.get("message", "")).strip(),
    }


def normalize_settings(payload: Any) -> dict[str, Any]:
    updates_payload = payload.get("updates", {}) if isinstance(payload, dict) else {}
    ui_payload = payload.get("ui", {}) if isinstance(payload, dict) else {}
    return {
        "updates": {
            "autoCheckEnabled": bool(updates_payload.get("autoCheckEnabled", False)),
            "lastResult": normalize_update_result(updates_payload.get("lastResult")),
        },
        "ui": {
            "showDiagnostics": bool(ui_payload.get("showDiagnostics", True)),
            "showFunscriptOverview": bool(ui_payload.get("showFunscriptOverview", True)),
            "showExecutionLog": bool(ui_payload.get("showExecutionLog", True)),
        },
    }


def load_settings() -> dict[str, Any]:
    if not SETTINGS_PATH.exists():
        return normalize_settings({})

    try:
        raw_settings = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return normalize_settings({})

    return normalize_settings(raw_settings)


def save_settings(settings: dict[str, Any]) -> dict[str, Any]:
    normalized_settings = normalize_settings(settings)
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS_PATH.write_text(json.dumps(normalized_settings, indent=2) + "\n", encoding="utf-8")
    return normalized_settings


def build_settings_payload() -> dict[str, Any]:
    settings = load_settings()
    return {
        "ok": True,
        "currentVersion": APP_VERSION,
        "settings": settings,
        "updateSupport": {
            "configured": bool(UPDATE_FEED_URL),
            "sourceUrl": UPDATE_FEED_URL,
        },
    }


def parse_version_parts(version: str) -> tuple[int, int, int] | None:
    match = VERSION_PATTERN.fullmatch(str(version or "").strip())
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def select_release_asset(assets: Any, platform: str) -> tuple[str, str]:
    if not isinstance(assets, list):
        return "", ""

    preferred_suffixes = [".apk", ".aab"] if platform == "android" else [".exe"]
    normalized_assets = [
        {
            "name": str(asset.get("name", "")).strip(),
            "downloadUrl": str(asset.get("browser_download_url", asset.get("downloadUrl", ""))).strip(),
        }
        for asset in assets
        if isinstance(asset, dict)
    ]
    for preferred_suffix in preferred_suffixes:
        for asset in normalized_assets:
            if asset["name"].lower().endswith(preferred_suffix) and asset["downloadUrl"]:
                return asset["downloadUrl"], asset["name"]
    return "", ""


def parse_release_payload(payload: Any, platform: str) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValueError("Update feed returned an invalid JSON payload")

    latest_version = str(payload.get("version") or payload.get("latestVersion") or payload.get("tag_name") or payload.get("name") or "").strip()
    latest_version_parts = parse_version_parts(latest_version)
    if latest_version_parts is None:
        raise ValueError("Update feed did not provide a valid semantic version")

    download_url, asset_name = select_release_asset(payload.get("assets", []), platform)
    current_version_parts = parse_version_parts(APP_VERSION) or (0, 0, 0)
    normalized_latest_version = ".".join(str(part) for part in latest_version_parts)
    update_available = latest_version_parts > current_version_parts
    status = "available" if update_available else "current"
    release_url = str(payload.get("releaseUrl") or payload.get("html_url") or payload.get("url") or "").strip()

    return {
        "status": status,
        "checkedAt": utc_now_iso(),
        "currentVersion": APP_VERSION,
        "latestVersion": normalized_latest_version,
        "updateAvailable": update_available,
        "releaseUrl": release_url,
        "downloadUrl": download_url,
        "assetName": asset_name,
        "publishedAt": str(payload.get("publishedAt") or payload.get("published_at") or payload.get("created_at") or "").strip(),
        "message": (
            f"Version {normalized_latest_version} is available."
            if update_available
            else f"You are already on the latest version ({APP_VERSION})."
        ),
    }


def fetch_update_result(platform: str) -> dict[str, Any]:
    if not UPDATE_FEED_URL:
        return {
            "status": "unconfigured",
            "checkedAt": utc_now_iso(),
            "currentVersion": APP_VERSION,
            "latestVersion": "",
            "updateAvailable": False,
            "releaseUrl": "",
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": "No update feed is configured.",
        }

    request = urlrequest.Request(
        UPDATE_FEED_URL,
        headers={
            "Accept": "application/json",
            "User-Agent": f"FHPlayer/{APP_VERSION}",
        },
        method="GET",
    )

    try:
        with urlrequest.urlopen(request, timeout=5.0) as response:
            body = response.read().decode("utf-8")
    except Exception as exc:
        return {
            "status": "error",
            "checkedAt": utc_now_iso(),
            "currentVersion": APP_VERSION,
            "latestVersion": "",
            "updateAvailable": False,
            "releaseUrl": "",
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": str(exc),
        }

    try:
        payload = json.loads(body)
        return parse_release_payload(payload, platform)
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "status": "error",
            "checkedAt": utc_now_iso(),
            "currentVersion": APP_VERSION,
            "latestVersion": "",
            "updateAvailable": False,
            "releaseUrl": "",
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": str(exc),
        }


def ensure_library_directories() -> None:
    for directory in {APP_DATA_DIR, LIBRARY_ROOT, LOGS_DIR, *LIBRARY_DIRECTORIES.values()}:
        directory.mkdir(parents=True, exist_ok=True)


def setup_logging() -> None:
    ensure_library_directories()
    if LOGGER.handlers:
        return

    LOGGER.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")

    file_handler = RotatingFileHandler(APP_LOG_PATH, maxBytes=512_000, backupCount=3, encoding="utf-8")
    file_handler.setFormatter(formatter)
    LOGGER.addHandler(file_handler)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)
    LOGGER.addHandler(stream_handler)

    LOGGER.propagate = False


def read_recent_log_text(path: Path, max_lines: int = 120, max_chars: int = 16_000) -> str:
    if not path.exists():
        return ""

    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""

    lines = content.splitlines()
    recent_text = "\n".join(lines[-max_lines:])
    if len(recent_text) > max_chars:
        recent_text = recent_text[-max_chars:]
    return recent_text


def build_diagnostics_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "platform": "desktop",
        "version": APP_VERSION,
        "paths": {
            "appData": str(APP_DATA_DIR),
            "libraryRoot": str(LIBRARY_ROOT),
            "settingsFile": str(SETTINGS_PATH),
            "logDirectory": str(LOGS_DIR),
            "logFile": str(APP_LOG_PATH),
        },
        "capabilities": {
            "openLogFolder": True,
        },
        "recentLog": read_recent_log_text(APP_LOG_PATH),
    }


def sanitize_library_filename(file_name: str) -> str:
    normalized = Path(str(file_name or "").replace("\\", "/")).name.strip()
    safe_name = "".join(character for character in normalized if character not in '<>:"/\\|?*').strip(" .")
    if not safe_name:
        raise ValueError("A valid filename is required")
    return safe_name


def resolve_library_directory(kind: str) -> Path:
    normalized_kind = str(kind or "").strip().lower()
    directory = LIBRARY_DIRECTORIES.get(normalized_kind)
    if directory is None:
        raise ValueError("Unsupported library kind")
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def build_library_payload() -> dict[str, Any]:
    return {
        "ok": True,
        "platform": "desktop",
        "rootPath": str(LIBRARY_ROOT),
        "directories": {
            "videos": str(LIBRARY_DIRECTORIES["videos"]),
            "funscripts": str(LIBRARY_DIRECTORIES["funscripts"]),
            "exports": str(LIBRARY_DIRECTORIES["exports"]),
        },
        "capabilities": {
            "import": True,
            "reveal": True,
        },
    }


def open_in_file_manager(path: Path) -> None:
    if sys.platform == "win32":
        os.startfile(str(path))  # type: ignore[attr-defined]
        return
    if sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
        return
    subprocess.Popen(["xdg-open", str(path)])

def parse_json_body(handler: SimpleHTTPRequestHandler) -> dict[str, Any]:
    try:
        length = int(handler.headers.get("Content-Length", "0"))
    except ValueError as exc:
        raise ValueError("Invalid Content-Length") from exc

    body = handler.rfile.read(length)
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise ValueError("Invalid JSON payload") from exc


def normalize_lovense_toys(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data", {})
    toys_raw = data.get("toys", "{}")

    if isinstance(toys_raw, str):
        toys_map = json.loads(toys_raw or "{}")
    elif isinstance(toys_raw, dict):
        toys_map = toys_raw
    else:
        toys_map = {}

    toys = []
    for toy_id, toy_data in toys_map.items():
        full_function_names = toy_data.get("fullFunctionNames") or []
        short_function_names = toy_data.get("shortFunctionNames") or []
        toy_type = (
            toy_data.get("type")
            or toy_data.get("toyType")
            or toy_data.get("name")
            or toy_data.get("nickName")
            or ""
        )
        toys.append(
            {
                "id": toy_data.get("id", toy_id),
                "name": toy_data.get("name", ""),
                "nickName": toy_data.get("nickName", ""),
                "type": toy_type,
                "battery": toy_data.get("battery"),
                "status": toy_data.get("status"),
                "version": toy_data.get("version", ""),
                "fullFunctionNames": full_function_names,
                "shortFunctionNames": short_function_names,
            }
        )

    return {
        "platform": data.get("platform", ""),
        "appType": data.get("appType", ""),
        "toys": toys,
    }


def extract_lovense_ipv4(host: str) -> str | None:
    normalized = str(host or "").strip().lower()
    if not normalized:
        return None

    candidate = normalized.removesuffix(".lovense.club")
    if "-" in candidate and "." not in candidate:
        candidate = candidate.replace("-", ".")

    try:
        parsed = ipaddress.ip_address(candidate)
    except ValueError:
        return None

    if parsed.version != 4:
        return None

    return str(parsed)


def build_lovense_request_candidates(config: dict[str, Any]) -> list[tuple[str, str, str]]:
    scheme = str(config.get("scheme", "https")).strip().lower() or "https"
    host = str(config.get("host", "")).strip()
    port = str(config.get("port", "")).strip()

    if not host:
        raise ValueError("Lovense host is required")
    if not port:
        raise ValueError("Lovense port is required")
    if scheme not in {"http", "https"}:
        raise ValueError("Lovense scheme must be http or https")

    ipv4 = extract_lovense_ipv4(host)
    seen: set[tuple[str, str, str]] = set()
    candidates: list[tuple[str, str, str]] = []

    def add_candidate(candidate_scheme: str, candidate_host: str, candidate_port: str) -> None:
        normalized_candidate = (candidate_scheme, candidate_host.strip(), str(candidate_port).strip())
        if not normalized_candidate[1] or not normalized_candidate[2] or normalized_candidate in seen:
            return
        seen.add(normalized_candidate)
        candidates.append(normalized_candidate)

    add_candidate(scheme, host, port)

    if ipv4:
        dashed_host = f"{ipv4.replace('.', '-')}.lovense.club"
        dotted_host = f"{ipv4}.lovense.club"
        for https_host in (dashed_host, dotted_host):
            add_candidate("https", https_host, port)
            add_candidate("https", https_host, "30010")
        add_candidate("https", ipv4, port)
        add_candidate("https", ipv4, "30010")
        add_candidate("http", ipv4, port)
        add_candidate("http", ipv4, "20010")

    return candidates


def execute_lovense_request(url: str, platform_name: str, payload: dict[str, Any], timeout_seconds: float) -> dict[str, Any]:
    request = urlrequest.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-platform": platform_name,
        },
        method="POST",
    )

    context = ssl._create_unverified_context() if url.startswith("https://") else None
    with urlrequest.urlopen(request, timeout=timeout_seconds, context=context) as response:
        body = response.read().decode("utf-8")

    return json.loads(body)


def lovense_request(
    config: dict[str, Any],
    payload: dict[str, Any],
    timeout_seconds: float = 5.0,
) -> tuple[dict[str, Any], str]:
    platform_name = str(config.get("platformName", "FHPlayer")).strip() or "FHPlayer"
    candidates = build_lovense_request_candidates(config)
    errors: list[str] = []
    last_error: Exception | None = None

    for scheme, host, port in candidates:
        url = f"{scheme}://{host}:{port}/command"
        try:
            return execute_lovense_request(url, platform_name, payload, timeout_seconds), url
        except Exception as exc:
            last_error = exc
            errors.append(f"{url}: {exc}")

    if last_error is None:
        raise RuntimeError("No Lovense request candidates were generated")

    error_summary = " | ".join(errors[-4:])
    if isinstance(last_error, TimeoutError):
        raise TimeoutError(f"{last_error}. Tried: {error_summary}") from last_error
    if isinstance(last_error, urlerror.URLError):
        raise urlerror.URLError(f"{last_error}. Tried: {error_summary}")
    raise RuntimeError(f"{last_error}. Tried: {error_summary}") from last_error


class FHPlayerHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/health":
            self._send_json(
                {
                    "ok": True,
                    "port": PORT,
                    "version": APP_VERSION,
                    "platform": "desktop",
                    "capabilities": {
                        "lovense": True,
                        "updates": True,
                        "diagnostics": True,
                    },
                }
            )
            return
        if parsed.path == "/api/library/info":
            self._send_json(build_library_payload())
            return
        if parsed.path == "/api/settings":
            self._send_json(build_settings_payload())
            return
        if parsed.path == "/api/diagnostics/info":
            self._send_json(build_diagnostics_payload())
            return

        if parsed.path == "/":
            self.path = "/index.html"

        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        route = parsed.path.rstrip("/") or "/"

        if route in {"/api/lovense/detect", "/api/lovense-detect"}:
            self._handle_lovense_detect()
            return

        if route in {"/api/lovense/command", "/api/lovense-command"}:
            self._handle_lovense_command()
            return
        if route == "/api/library/open":
            self._handle_library_open(parsed)
            return
        if route == "/api/settings":
            self._handle_settings_update()
            return
        if route == "/api/update/check":
            self._handle_update_check()
            return
        if route == "/api/diagnostics/open":
            self._handle_diagnostics_open()
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Unknown API route")

    def do_PUT(self) -> None:
        parsed = urlparse(self.path)
        route = parsed.path.rstrip("/") or "/"
        if route == "/api/library/import":
            self._handle_library_import(parsed)
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Unknown API route")

    def _handle_lovense_detect(self) -> None:
        try:
            payload = parse_json_body(self)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        config = payload.get("config", {})
        timeout_seconds = float(payload.get("timeoutSeconds", 5))
        try:
            result, resolved_endpoint = lovense_request(config, {"command": "GetToys"}, timeout_seconds=timeout_seconds)
            normalized = normalize_lovense_toys(result)
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        except urlerror.URLError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_GATEWAY)
            return
        except TimeoutError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.GATEWAY_TIMEOUT)
            return
        except Exception as exc:  # pragma: no cover
            LOGGER.exception("Lovense detection failed with an unexpected error.")
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json({"ok": True, "result": result, "normalized": normalized, "resolvedEndpoint": resolved_endpoint})

    def _handle_lovense_command(self) -> None:
        try:
            payload = parse_json_body(self)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        config = payload.get("config", {})
        commands = payload.get("commands", [])
        timeout_seconds = float(payload.get("timeoutSeconds", 5))
        if not isinstance(commands, list) or not commands:
            self._send_json({"ok": False, "error": "commands must be a non-empty array"}, status=HTTPStatus.BAD_REQUEST)
            return

        results = []
        try:
            for command_payload in commands:
                result, resolved_endpoint = lovense_request(config, command_payload, timeout_seconds=timeout_seconds)
                results.append({"request": command_payload, "response": result, "resolvedEndpoint": resolved_endpoint})
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc), "results": results}, status=HTTPStatus.BAD_REQUEST)
            return
        except urlerror.URLError as exc:
            self._send_json({"ok": False, "error": str(exc), "results": results}, status=HTTPStatus.BAD_GATEWAY)
            return
        except TimeoutError as exc:
            self._send_json({"ok": False, "error": str(exc), "results": results}, status=HTTPStatus.GATEWAY_TIMEOUT)
            return
        except Exception as exc:  # pragma: no cover
            LOGGER.exception("Lovense command execution failed with an unexpected error.")
            self._send_json({"ok": False, "error": str(exc), "results": results}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json({"ok": True, "results": results})

    def _handle_library_import(self, parsed: Any) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            target_directory = resolve_library_directory(query.get("kind", [""])[0])
            file_name = sanitize_library_filename(query.get("filename", [""])[0])
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return

        if content_length < 0:
            self._send_json({"ok": False, "error": "Invalid Content-Length"}, status=HTTPStatus.BAD_REQUEST)
            return

        destination = target_directory / file_name
        try:
            body = self.rfile.read(content_length)
            destination.write_bytes(body)
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json(
            {
                "ok": True,
                "path": str(destination),
                "fileName": destination.name,
                "sizeBytes": destination.stat().st_size,
            }
        )
        LOGGER.info("Imported %s into %s", destination.name, target_directory)

    def _handle_library_open(self, parsed: Any) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            target_directory = resolve_library_directory(query.get("kind", ["videos"])[0])
            open_in_file_manager(target_directory)
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json({"ok": True, "path": str(target_directory)})

    def _handle_diagnostics_open(self) -> None:
        try:
            open_in_file_manager(LOGS_DIR)
        except OSError as exc:
            LOGGER.exception("Could not open diagnostics folder.")
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json({"ok": True, "path": str(LOGS_DIR)})

    def _handle_settings_update(self) -> None:
        try:
            payload = parse_json_body(self)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        current_settings = load_settings()
        updates_payload = payload.get("updates", {}) if isinstance(payload, dict) else {}
        if isinstance(updates_payload, dict) and "autoCheckEnabled" in updates_payload:
            current_settings["updates"]["autoCheckEnabled"] = bool(updates_payload.get("autoCheckEnabled"))
        ui_payload = payload.get("ui", {}) if isinstance(payload, dict) else {}
        if isinstance(ui_payload, dict):
            if "showDiagnostics" in ui_payload:
                current_settings["ui"]["showDiagnostics"] = bool(ui_payload.get("showDiagnostics"))
            if "showFunscriptOverview" in ui_payload:
                current_settings["ui"]["showFunscriptOverview"] = bool(ui_payload.get("showFunscriptOverview"))
            if "showExecutionLog" in ui_payload:
                current_settings["ui"]["showExecutionLog"] = bool(ui_payload.get("showExecutionLog"))

        try:
            saved_settings = save_settings(current_settings)
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json(
            {
                "ok": True,
                "currentVersion": APP_VERSION,
                "settings": saved_settings,
                "updateSupport": {
                    "configured": bool(UPDATE_FEED_URL),
                    "sourceUrl": UPDATE_FEED_URL,
                },
            }
        )

    def _handle_update_check(self) -> None:
        update_result = fetch_update_result(platform="desktop")
        current_settings = load_settings()
        current_settings["updates"]["lastResult"] = update_result

        try:
            saved_settings = save_settings(current_settings)
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json(
            {
                "ok": update_result.get("status") != "error",
                "currentVersion": APP_VERSION,
                "result": update_result,
                "settings": saved_settings,
            },
            status=HTTPStatus.OK if update_result.get("status") != "error" else HTTPStatus.BAD_GATEWAY,
        )
        LOGGER.info("Update check finished with status=%s latest=%s", update_result.get("status"), update_result.get("latestVersion"))

    def log_message(self, format: str, *args: Any) -> None:
        LOGGER.info('%s - - [%s] %s', self.address_string(), self.log_date_time_string(), format % args)

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    try:
        setup_logging()
        ensure_library_directories()
        if not STATIC_DIR.exists():
            error_msg = f"Missing static assets in {STATIC_DIR}\nBASE_DIR: {BASE_DIR}\nCwd: {os.getcwd()}"
            raise SystemExit(error_msg)

        server = ThreadingHTTPServer((HOST, PORT), FHPlayerHandler)
        url = f"http://{HOST}:{PORT}"

        print(f"FHPlayer is running at {url}")
        print(f"Library root: {LIBRARY_ROOT}")
        print("Press Ctrl+C to stop.")
        LOGGER.info("FHPlayer desktop server starting at %s", url)
        LOGGER.info("Library root: %s", LIBRARY_ROOT)
        LOGGER.info("Log file: %s", APP_LOG_PATH)

        if not os.environ.get("FHPLAYER_NO_BROWSER"):
            webbrowser.open(url)

        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")
            LOGGER.info("FHPlayer desktop server interrupted by user.")
        finally:
            server.server_close()
            LOGGER.info("FHPlayer desktop server stopped.")
    except Exception as e:
        error_msg = f"Error: {type(e).__name__}: {e}"
        print(error_msg, flush=True)
        if LOGGER.handlers:
            LOGGER.exception("FHPlayer desktop server crashed.")

        error_log = Path.home() / "Desktop" / "FHPlayer_error.log"
        try:
            error_log.write_text(error_msg)
            print(f"Error log written to {error_log}", flush=True)
        except Exception:
            pass

        if sys.platform == "win32":
            import time
            time.sleep(5)
        raise


if __name__ == "__main__":
    main()
