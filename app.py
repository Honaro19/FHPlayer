from __future__ import annotations

import json
import os
import ipaddress
import ssl
import subprocess
import sys
import webbrowser
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


def resolve_app_data_dir() -> Path:
    if sys.platform == "win32":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            return Path(local_app_data) / "FHPlayer"
    return Path.home() / ".fhplayer"


APP_DATA_DIR = resolve_app_data_dir()
LIBRARY_ROOT = APP_DATA_DIR / "Library"
LIBRARY_DIRECTORIES = {
    "video": LIBRARY_ROOT / "Videos",
    "videos": LIBRARY_ROOT / "Videos",
    "funscript": LIBRARY_ROOT / "Funscripts",
    "funscripts": LIBRARY_ROOT / "Funscripts",
    "export": LIBRARY_ROOT / "Exports",
    "exports": LIBRARY_ROOT / "Exports",
}


def ensure_library_directories() -> None:
    for directory in {APP_DATA_DIR, LIBRARY_ROOT, *LIBRARY_DIRECTORIES.values()}:
        directory.mkdir(parents=True, exist_ok=True)


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
                    "platform": "desktop",
                    "capabilities": {
                        "lovense": True,
                    },
                }
            )
            return
        if parsed.path == "/api/library/info":
            self._send_json(build_library_payload())
            return

        if parsed.path == "/":
            self.path = "/index.html"
        elif parsed.path == "/app.js":
            self.path = "/playlist-app.js"

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

    def log_message(self, format: str, *args: Any) -> None:
        message = "%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), format % args)
        print(message, end="")

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
        ensure_library_directories()
        if not STATIC_DIR.exists():
            error_msg = f"Missing static assets in {STATIC_DIR}\nBASE_DIR: {BASE_DIR}\nCwd: {os.getcwd()}"
            raise SystemExit(error_msg)

        server = ThreadingHTTPServer((HOST, PORT), FHPlayerHandler)
        url = f"http://{HOST}:{PORT}"

        print(f"FHPlayer is running at {url}")
        print(f"Library root: {LIBRARY_ROOT}")
        print("Press Ctrl+C to stop.")

        if not os.environ.get("FHPLAYER_NO_BROWSER"):
            webbrowser.open(url)

        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")
        finally:
            server.server_close()
    except Exception as e:
        error_msg = f"Error: {type(e).__name__}: {e}"
        print(error_msg, flush=True)

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
