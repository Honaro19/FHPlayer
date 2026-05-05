from __future__ import annotations
from concurrent.futures import ThreadPoolExecutor, as_completed

import json
import mimetypes
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
DEFAULT_UPDATE_FEED_URL = "https://api.github.com/repos/Honaro19/FHPlayer/releases/latest"
DEFAULT_RELEASE_PAGE_URL = "https://github.com/Honaro19/FHPlayer/releases"
UPDATE_FEED_URL = os.environ.get("FHPLAYER_UPDATE_FEED_URL", DEFAULT_UPDATE_FEED_URL)
RELEASE_PAGE_URL = os.environ.get("FHPLAYER_RELEASE_PAGE_URL", DEFAULT_RELEASE_PAGE_URL)
VERSION_PATTERN = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
UPDATE_URL_OPENER = urlrequest.build_opener(urlrequest.ProxyHandler({}))


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
VIDEO_FILE_EXTENSIONS = {".mp4", ".webm", ".m4v", ".mov", ".mkv", ".avi"}
FUNSCRIPT_FILE_EXTENSIONS = {".funscript", ".json"}
LOGGER = logging.getLogger("fhplayer")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def normalize_optional_string(value: Any) -> str:
    normalized = str(value or "").strip()
    if normalized.lower() in {"", "null", "none"}:
        return ""
    return normalized


def normalize_update_result(result: Any) -> dict[str, Any] | None:
    if not isinstance(result, dict):
        return None

    source_url = normalize_optional_string(result.get("sourceUrl"))
    if source_url != UPDATE_FEED_URL:
        return None

    return {
        "status": normalize_optional_string(result.get("status")) or "unknown",
        "checkedAt": normalize_optional_string(result.get("checkedAt")),
        "currentVersion": normalize_optional_string(result.get("currentVersion")) or APP_VERSION,
        "latestVersion": normalize_optional_string(result.get("latestVersion")),
        "updateAvailable": bool(result.get("updateAvailable", False)),
        "releaseUrl": normalize_optional_string(result.get("releaseUrl")),
        "downloadUrl": normalize_optional_string(result.get("downloadUrl")),
        "assetName": normalize_optional_string(result.get("assetName")),
        "publishedAt": normalize_optional_string(result.get("publishedAt")),
        "message": normalize_optional_string(result.get("message")),
        "sourceUrl": source_url,
    }


def normalize_settings(payload: Any) -> dict[str, Any]:
    updates_payload = payload.get("updates", {}) if isinstance(payload, dict) else {}
    ui_payload = payload.get("ui", {}) if isinstance(payload, dict) else {}
    legal_payload = payload.get("legal", {}) if isinstance(payload, dict) else {}
    return {
        "updates": {
            "autoCheckEnabled": bool(updates_payload.get("autoCheckEnabled", False)),
            "lastResult": normalize_update_result(updates_payload.get("lastResult")),
            "manualDisclosureAcknowledgedVersion": normalize_optional_string(
                updates_payload.get("manualDisclosureAcknowledgedVersion")
            ),
            "releaseDisclosureSuppressedVersion": normalize_optional_string(
                updates_payload.get("releaseDisclosureSuppressedVersion")
            ),
        },
        "ui": {
            "showDiagnostics": bool(ui_payload.get("showDiagnostics", True)),
            "showFunscriptOverview": bool(ui_payload.get("showFunscriptOverview", True)),
            "showExecutionLog": bool(ui_payload.get("showExecutionLog", True)),
            "showUpdates": bool(ui_payload.get("showUpdates", True)),
        },
        "legal": {
            "lastAcknowledgedVersion": normalize_optional_string(legal_payload.get("lastAcknowledgedVersion")),
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
            "releaseUrl": RELEASE_PAGE_URL,
        },
    }


def parse_version_parts(version: str) -> tuple[int, int, int] | None:
    match = VERSION_PATTERN.fullmatch(str(version or "").strip())
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def require_manifest_schema_version(payload: dict[str, Any]) -> None:
    schema_version = payload.get("schema_version")
    if isinstance(schema_version, bool):
        raise ValueError("Update manifest schema_version must be 1")
    if isinstance(schema_version, int):
        normalized_schema_version = schema_version
    else:
        normalized_schema_value = normalize_optional_string(schema_version)
        try:
            normalized_schema_version = int(normalized_schema_value)
        except (TypeError, ValueError):
            normalized_schema_version = None
    if normalized_schema_version != 1:
        raise ValueError("Update manifest schema_version must be 1")


def is_github_release_payload(payload: dict[str, Any]) -> bool:
    html_url = get_string_value(payload, "html_url")
    tag_name = get_string_value(payload, "tag_name")
    parsed_url = urlparse(html_url)
    return (
        parsed_url.scheme == "https"
        and parsed_url.netloc == "github.com"
        and "/releases/tag/" in parsed_url.path
        and bool(tag_name)
    )


def first_non_blank(*values: Any) -> str:
    for value in values:
        normalized = normalize_optional_string(value)
        if normalized:
            return normalized
    return ""


def normalize_update_platform(platform: str) -> str:
    normalized_platform = str(platform or "").strip().lower()
    if normalized_platform in {"android"}:
        return "android"
    return "windows"


def get_string_value(payload: Any, *keys: str) -> str:
    if not isinstance(payload, dict):
        return ""

    for key in keys:
        value = payload.get(key)
        if value is None:
            continue
        normalized = normalize_optional_string(value)
        if normalized:
            return normalized
    return ""


def extract_platform_payload(payload: dict[str, Any], platform: str) -> dict[str, Any]:
    platform_payload = payload.get("platforms")
    if isinstance(platform_payload, dict):
        selected_payload = platform_payload.get(platform)
        if isinstance(selected_payload, dict):
            return selected_payload

    selected_payload = payload.get(platform)
    if isinstance(selected_payload, dict):
        return selected_payload

    return {}


def asset_name_from_url(url: str) -> str:
    path = urlparse(str(url or "").strip()).path.rstrip("/")
    if not path:
        return ""
    return path.split("/")[-1]


def select_release_asset(assets: Any, platform: str) -> tuple[str, str]:
    if not isinstance(assets, list):
        return "", ""

    preferred_suffixes = [".apk", ".aab"] if normalize_update_platform(platform) == "android" else [".exe", ".zip"]
    normalized_assets = [
        {
            "name": str(asset.get("name", "")).strip(),
            "downloadUrl": first_non_blank(
                asset.get("browser_download_url"),
                asset.get("downloadUrl"),
                asset.get("download_url"),
                asset.get("url"),
            ),
        }
        for asset in assets
        if isinstance(asset, dict)
    ]
    for preferred_suffix in preferred_suffixes:
        for asset in normalized_assets:
            if asset["name"].lower().endswith(preferred_suffix) and asset["downloadUrl"]:
                return asset["downloadUrl"], asset["name"]
    return "", ""


def parse_release_payload(payload: Any, platform: str, current_version: str | None = None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValueError("Update feed returned an invalid JSON payload")

    if not is_github_release_payload(payload):
        require_manifest_schema_version(payload)
    normalized_current_version = normalize_optional_string(current_version) or APP_VERSION
    normalized_platform = normalize_update_platform(platform)
    platform_payload = extract_platform_payload(payload, normalized_platform)
    latest_version = first_non_blank(
        get_string_value(platform_payload, "latest_version", "latestVersion", "version", "tag_name", "name"),
        get_string_value(payload, "latest_version", "latestVersion", "version", "tag_name", "name"),
    )
    latest_version_parts = parse_version_parts(latest_version)
    if latest_version_parts is None:
        raise ValueError("Update feed did not provide a valid semantic version")

    preferred_download_keys = (
        ("apk_url", "apkUrl", "aab_url", "aabUrl", "download_url", "downloadUrl")
        if normalized_platform == "android"
        else ("installer_url", "installerUrl", "portable_url", "portableUrl", "download_url", "downloadUrl")
    )
    download_url = first_non_blank(
        get_string_value(platform_payload, *preferred_download_keys),
        get_string_value(payload, *preferred_download_keys),
    )
    asset_name = asset_name_from_url(download_url)
    if not download_url:
        download_url, asset_name = select_release_asset(platform_payload.get("assets"), normalized_platform)
    if not download_url:
        download_url, asset_name = select_release_asset(payload.get("assets"), normalized_platform)

    current_version_parts = parse_version_parts(normalized_current_version) or (0, 0, 0)
    normalized_latest_version = ".".join(str(part) for part in latest_version_parts)
    update_available = latest_version_parts > current_version_parts
    status = "available" if update_available else "current"
    release_url = first_non_blank(
        get_string_value(platform_payload, "folder_url", "folderUrl", "release_url", "releaseUrl", "html_url", "url"),
        get_string_value(payload, "folder_url", "folderUrl", "release_url", "releaseUrl", "html_url", "url"),
    )

    return {
        "status": status,
        "checkedAt": utc_now_iso(),
        "currentVersion": normalized_current_version,
        "latestVersion": normalized_latest_version,
        "updateAvailable": update_available,
        "releaseUrl": release_url,
        "downloadUrl": download_url,
        "assetName": asset_name,
        "publishedAt": first_non_blank(
            get_string_value(platform_payload, "published_at", "publishedAt", "created_at", "createdAt"),
            get_string_value(payload, "published_at", "publishedAt", "created_at", "createdAt"),
        ),
        "message": (
            f"Version {normalized_latest_version} is available."
            if update_available
            else f"You are already on the latest version ({normalized_current_version})."
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
            "releaseUrl": RELEASE_PAGE_URL,
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": "No update feed is configured.",
            "sourceUrl": UPDATE_FEED_URL,
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
        with UPDATE_URL_OPENER.open(request, timeout=5.0) as response:
            body = response.read().decode("utf-8")
    except urlerror.HTTPError as exc:
        if UPDATE_FEED_URL == DEFAULT_UPDATE_FEED_URL and exc.code == HTTPStatus.NOT_FOUND:
            return {
                "status": "unavailable",
                "checkedAt": utc_now_iso(),
                "currentVersion": APP_VERSION,
                "latestVersion": "",
                "updateAvailable": False,
                "releaseUrl": RELEASE_PAGE_URL,
                "downloadUrl": "",
                "assetName": "",
                "publishedAt": "",
                "message": "No GitHub release has been published yet.",
                "sourceUrl": UPDATE_FEED_URL,
            }
        return {
            "status": "error",
            "checkedAt": utc_now_iso(),
            "currentVersion": APP_VERSION,
            "latestVersion": "",
            "updateAvailable": False,
            "releaseUrl": RELEASE_PAGE_URL,
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": str(exc),
            "sourceUrl": UPDATE_FEED_URL,
        }
    except Exception as exc:
        return {
            "status": "error",
            "checkedAt": utc_now_iso(),
            "currentVersion": APP_VERSION,
            "latestVersion": "",
            "updateAvailable": False,
            "releaseUrl": RELEASE_PAGE_URL,
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": str(exc),
            "sourceUrl": UPDATE_FEED_URL,
        }

    try:
        payload = json.loads(body)
        result = parse_release_payload(payload, platform)
        result["sourceUrl"] = UPDATE_FEED_URL
        return result
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "status": "error",
            "checkedAt": utc_now_iso(),
            "currentVersion": APP_VERSION,
            "latestVersion": "",
            "updateAvailable": False,
            "releaseUrl": RELEASE_PAGE_URL,
            "downloadUrl": "",
            "assetName": "",
            "publishedAt": "",
            "message": str(exc),
            "sourceUrl": UPDATE_FEED_URL,
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
            "serve": True,
            "localFiles": True,
            "delete": True,
        },
    }


def build_library_file_list(kind: str) -> dict[str, Any]:
    target_directory = resolve_library_directory(kind)
    files: list[dict[str, Any]] = []
    for target_file in sorted(target_directory.iterdir(), key=lambda path: path.name.lower()):
        if not target_file.is_file():
            continue
        stat = target_file.stat()
        files.append(
            {
                "name": target_file.name,
                "path": str(target_file),
                "sizeBytes": stat.st_size,
                "modifiedMs": int(stat.st_mtime * 1000),
            }
        )
    return {
        "ok": True,
        "kind": str(kind or "").strip().lower(),
        "files": files,
    }


def resolve_library_file(kind: str, file_name: str) -> Path:
    target_directory = resolve_library_directory(kind)
    safe_file_name = sanitize_library_filename(file_name)
    target_file = target_directory / safe_file_name
    if not target_file.is_file():
        raise FileNotFoundError(f"Library file was not found: {safe_file_name}")
    return target_file


def resolve_local_media_file(kind: str, file_path: str) -> Path:
    normalized_kind = str(kind or "").strip().lower()
    allowed_extensions = {
        "video": VIDEO_FILE_EXTENSIONS,
        "videos": VIDEO_FILE_EXTENSIONS,
        "funscript": FUNSCRIPT_FILE_EXTENSIONS,
        "funscripts": FUNSCRIPT_FILE_EXTENSIONS,
    }.get(normalized_kind)
    if allowed_extensions is None:
        raise ValueError("Unsupported local file kind")

    normalized_path = normalize_optional_string(file_path)
    if not normalized_path:
        raise ValueError("A local file path is required")

    target_file = Path(normalized_path).expanduser()
    if not target_file.is_absolute():
        raise ValueError("Local file path must be absolute")
    if target_file.suffix.lower() not in allowed_extensions:
        raise ValueError("Unsupported local file extension")
    if not target_file.is_file():
        raise FileNotFoundError(f"Local file was not found: {target_file}")
    return target_file


def parse_http_range(range_header: str, file_size: int) -> tuple[int, int] | None:
    normalized_header = str(range_header or "").strip()
    if not normalized_header:
        return None

    match = re.fullmatch(r"bytes=(\d*)-(\d*)", normalized_header)
    if not match or file_size <= 0:
        raise ValueError("Invalid Range header")

    start_text, end_text = match.groups()
    if not start_text and not end_text:
        raise ValueError("Invalid Range header")

    if not start_text:
        suffix_length = int(end_text)
        if suffix_length <= 0:
            raise ValueError("Invalid Range header")
        start = max(0, file_size - suffix_length)
        end = file_size - 1
    else:
        start = int(start_text)
        end = int(end_text) if end_text else file_size - 1

    end = min(end, file_size - 1)
    if start < 0 or start >= file_size or end < start:
        raise ValueError("Invalid Range header")
    return start, end


def open_in_file_manager(path: Path) -> str:
    resolved_path = path.resolve()
    resolved_path.mkdir(parents=True, exist_ok=True)
    if sys.platform == "win32":
        startfile = getattr(os, "startfile", None)
        if startfile is not None:
            try:
                startfile(str(resolved_path))
                return "os.startfile"
            except OSError:
                LOGGER.warning("os.startfile failed for %s; trying explorer.exe fallback.", resolved_path, exc_info=True)

        explorer_path = Path(os.environ.get("WINDIR", r"C:\Windows")) / "explorer.exe"
        explorer_command = str(explorer_path) if explorer_path.exists() else "explorer.exe"
        process = subprocess.Popen(
            [explorer_command, str(resolved_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            return_code = process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            return "explorer.exe"
        if return_code != 0:
            raise OSError(f"explorer.exe exited with status {return_code}")
        return "explorer.exe"
    if sys.platform == "darwin":
        subprocess.Popen(["open", str(resolved_path)])
        return "open"
    subprocess.Popen(["xdg-open", str(resolved_path)])
    return "xdg-open"

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

def validate_lovense_url(url: str) -> None:
    parsed = urlparse(str(url or "").strip())

    # Nur HTTP/HTTPS erlauben
    if parsed.scheme not in ("http", "https"):
        raise ValueError("Invalid URL scheme")

    host = (parsed.hostname or "").strip()
    if not host:
        raise ValueError("Invalid URL host")

    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        # Domain → optional einschränken
        if not host.endswith(".lovense.club"):
            raise ValueError("Only Lovense domains are allowed")
        return

    # IP → nur bestimmte erlauben
    if not (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
    ):
        raise ValueError("Public IPs are not allowed for Lovense requests")

def execute_lovense_request(url: str, platform_name: str, payload: dict[str, Any], timeout_seconds: float) -> dict[str, Any]:
    validate_lovense_url(url)

    request = urlrequest.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-platform": platform_name,
        },
        method="POST",
    )

    with urlrequest.urlopen(request, timeout=timeout_seconds) as response:
        body = response.read().decode("utf-8")

    return json.loads(body)


def should_use_unverified_lovense_tls(url: str) -> bool:
    parsed = urlparse(str(url or "").strip())
    if parsed.scheme.lower() != "https":
        return False

    host = (parsed.hostname or "").strip()
    if not host:
        return False

    try:
        parsed_ip = ipaddress.ip_address(host)
    except ValueError:
        return False

    return parsed_ip.version == 4 and (
        parsed_ip.is_private
        or parsed_ip.is_loopback
        or parsed_ip.is_link_local
    )


def lovense_request(
    config: dict[str, Any],
    payload: dict[str, Any],
    timeout_seconds: float = 5.0,
) -> tuple[dict[str, Any], str]:
    platform_name = str(config.get("platformName", "FHPlayer")).strip() or "FHPlayer"
    candidates = build_lovense_request_candidates(config)

    if not candidates:
        raise RuntimeError("No Lovense request candidates were generated")

    def try_candidate(candidate: tuple[str, str, str]) -> tuple[dict[str, Any], str]:
        scheme, host, port = candidate
        url = f"{scheme}://{host}:{port}/command"
        result = execute_lovense_request(url, platform_name, payload, timeout_seconds)
        return result, url

    errors: list[str] = []
    last_error: Exception | None = None

    max_workers = min(len(candidates), 8)

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_candidate = {
            executor.submit(try_candidate, candidate): candidate
            for candidate in candidates
        }

        for future in as_completed(future_to_candidate):
            scheme, host, port = future_to_candidate[future]
            url = f"{scheme}://{host}:{port}/command"

            try:
                return future.result()
            except Exception as exc:
                last_error = exc
                errors.append(f"{url}: {exc}")

    if last_error is None:
        raise RuntimeError("No Lovense request candidates were generated")

    error_summary = " | ".join(errors[-4:])
    error_text = str(last_error).lower()

    if any(keyword in error_text for keyword in ["10061", "connection refused", "getaddrinfo", "failed to establish"]):
        raise RuntimeError(
            "No Lovense device or app reachable. Please start the Lovense app and try again."
        ) from last_error

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
        if parsed.path == "/api/library/list":
            self._handle_library_list(parsed)
            return
        if parsed.path == "/api/library/file":
            self._handle_library_file(parsed)
            return
        if parsed.path == "/api/local-file":
            self._handle_local_file(parsed)
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

    def do_HEAD(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/library/file":
            self._handle_library_file(parsed, send_body=False)
            return
        if parsed.path == "/api/local-file":
            self._handle_local_file(parsed, send_body=False)
            return
        super().do_HEAD()

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

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        route = parsed.path.rstrip("/") or "/"
        if route == "/api/library/file":
            self._handle_library_delete(parsed)
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

    def _handle_library_list(self, parsed: Any) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            self._send_json(build_library_file_list(query.get("kind", [""])[0]))
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)

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

    def _handle_library_delete(self, parsed: Any) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            target_file = resolve_library_file(query.get("kind", [""])[0], query.get("filename", [""])[0])
            file_size = target_file.stat().st_size
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        except FileNotFoundError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.NOT_FOUND)
            return
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        try:
            target_file.unlink()
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json(
            {
                "ok": True,
                "path": str(target_file),
                "fileName": target_file.name,
                "sizeBytes": file_size,
            }
        )
        LOGGER.info("Deleted library file %s", target_file)

    def _handle_library_file(self, parsed: Any, send_body: bool = True) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            target_file = resolve_library_file(query.get("kind", [""])[0], query.get("filename", [""])[0])
            file_size = target_file.stat().st_size
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        except FileNotFoundError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.NOT_FOUND)
            return
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        requested_range = bool(self.headers.get("Range"))
        try:
            byte_range = parse_http_range(self.headers.get("Range", ""), file_size) if requested_range else None
        except ValueError:
            self._send_range_not_satisfiable(file_size)
            return

        start, end = byte_range if byte_range else (0, max(file_size - 1, 0))
        content_length = 0 if file_size == 0 else end - start + 1
        content_type = self._guess_library_content_type(target_file)
        status = HTTPStatus.PARTIAL_CONTENT if byte_range else HTTPStatus.OK

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-store")
        if byte_range:
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.end_headers()

        if not send_body or content_length <= 0:
            return

        try:
            with target_file.open("rb") as file_handle:
                file_handle.seek(start)
                remaining = content_length
                while remaining > 0:
                    chunk = file_handle.read(min(64 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
            LOGGER.debug("Client closed library file stream early: %s", target_file)
        except OSError:
            LOGGER.exception("Could not stream library file %s.", target_file)

    def _handle_local_file(self, parsed: Any, send_body: bool = True) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            target_file = resolve_local_media_file(query.get("kind", [""])[0], query.get("path", [""])[0])
            file_size = target_file.stat().st_size
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        except FileNotFoundError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.NOT_FOUND)
            return
        except OSError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        requested_range = bool(self.headers.get("Range"))
        try:
            byte_range = parse_http_range(self.headers.get("Range", ""), file_size) if requested_range else None
        except ValueError:
            self._send_range_not_satisfiable(file_size)
            return

        start, end = byte_range if byte_range else (0, max(file_size - 1, 0))
        content_length = 0 if file_size == 0 else end - start + 1
        content_type = self._guess_library_content_type(target_file)
        status = HTTPStatus.PARTIAL_CONTENT if byte_range else HTTPStatus.OK

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-store")
        if byte_range:
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.end_headers()

        if not send_body or content_length <= 0:
            return

        try:
            with target_file.open("rb") as file_handle:
                file_handle.seek(start)
                remaining = content_length
                while remaining > 0:
                    chunk = file_handle.read(min(64 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
            LOGGER.debug("Client closed local file stream early: %s", target_file)
        except OSError:
            LOGGER.exception("Could not stream local file %s.", target_file)

    def _send_range_not_satisfiable(self, file_size: int) -> None:
        self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
        self.send_header("Content-Range", f"bytes */{file_size}")
        self.send_header("Content-Length", "0")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

    def _guess_library_content_type(self, target_file: Path) -> str:
        if target_file.suffix.lower() in {".funscript", ".json"}:
            return "application/json; charset=utf-8"
        return mimetypes.guess_type(target_file.name)[0] or "application/octet-stream"

    def _handle_library_open(self, parsed: Any) -> None:
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            target_directory = resolve_library_directory(query.get("kind", ["videos"])[0])
            LOGGER.info("Opening library folder: %s", target_directory)
            opener = open_in_file_manager(target_directory)
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        except OSError as exc:
            LOGGER.exception("Could not open library folder: %s", query.get("kind", ["videos"])[0])
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json({"ok": True, "path": str(target_directory), "opener": opener})

    def _handle_diagnostics_open(self) -> None:
        try:
            opener = open_in_file_manager(LOGS_DIR)
        except OSError as exc:
            LOGGER.exception("Could not open diagnostics folder.")
            self._send_json({"ok": False, "error": str(exc)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json({"ok": True, "path": str(LOGS_DIR), "opener": opener})

    def _handle_settings_update(self) -> None:
        try:
            payload = parse_json_body(self)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        current_settings = load_settings()
        updates_payload = payload.get("updates", {}) if isinstance(payload, dict) else {}
        if isinstance(updates_payload, dict):
            if "autoCheckEnabled" in updates_payload:
                current_settings["updates"]["autoCheckEnabled"] = bool(updates_payload.get("autoCheckEnabled"))
            if "manualDisclosureAcknowledgedVersion" in updates_payload:
                current_settings["updates"]["manualDisclosureAcknowledgedVersion"] = normalize_optional_string(
                    updates_payload.get("manualDisclosureAcknowledgedVersion")
                )
            if "releaseDisclosureSuppressedVersion" in updates_payload:
                current_settings["updates"]["releaseDisclosureSuppressedVersion"] = normalize_optional_string(
                    updates_payload.get("releaseDisclosureSuppressedVersion")
                )
        ui_payload = payload.get("ui", {}) if isinstance(payload, dict) else {}
        if isinstance(ui_payload, dict):
            if "showDiagnostics" in ui_payload:
                current_settings["ui"]["showDiagnostics"] = bool(ui_payload.get("showDiagnostics"))
            if "showFunscriptOverview" in ui_payload:
                current_settings["ui"]["showFunscriptOverview"] = bool(ui_payload.get("showFunscriptOverview"))
            if "showExecutionLog" in ui_payload:
                current_settings["ui"]["showExecutionLog"] = bool(ui_payload.get("showExecutionLog"))
            if "showUpdates" in ui_payload:
                current_settings["ui"]["showUpdates"] = bool(ui_payload.get("showUpdates"))
        legal_payload = payload.get("legal", {}) if isinstance(payload, dict) else {}
        if isinstance(legal_payload, dict) and "lastAcknowledgedVersion" in legal_payload:
            current_settings["legal"]["lastAcknowledgedVersion"] = normalize_optional_string(
                legal_payload.get("lastAcknowledgedVersion")
            )

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
                    "releaseUrl": RELEASE_PAGE_URL,
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
                "updateSupport": {
                    "configured": bool(UPDATE_FEED_URL),
                    "sourceUrl": UPDATE_FEED_URL,
                    "releaseUrl": RELEASE_PAGE_URL,
                },
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
