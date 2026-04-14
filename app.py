from __future__ import annotations

import json
import os
import shlex
import ssl
import subprocess
import time
import webbrowser
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import urlparse


HOST = "127.0.0.1"
PORT = 8765
STATIC_DIR = Path(__file__).parent / "static"


def run_command(command: str, shell_name: str, timeout_seconds: float) -> dict[str, Any]:
    started = time.perf_counter()

    if shell_name == "powershell":
        process = subprocess.run(
            ["powershell", "-NoProfile", "-Command", command],
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    elif shell_name == "cmd":
        process = subprocess.run(
            ["cmd", "/c", command],
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    else:
        process = subprocess.run(
            shlex.split(command),
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )

    duration_ms = round((time.perf_counter() - started) * 1000, 1)
    return {
        "returnCode": process.returncode,
        "stdout": process.stdout.strip(),
        "stderr": process.stderr.strip(),
        "durationMs": duration_ms,
    }


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


def lovense_request(config: dict[str, Any], payload: dict[str, Any], timeout_seconds: float = 5.0) -> dict[str, Any]:
    scheme = str(config.get("scheme", "https")).strip().lower() or "https"
    host = str(config.get("host", "")).strip()
    port = str(config.get("port", "")).strip()
    platform_name = str(config.get("platformName", "FHPlayer")).strip() or "FHPlayer"

    if not host:
        raise ValueError("Lovense host is required")
    if not port:
        raise ValueError("Lovense port is required")
    if scheme not in {"http", "https"}:
        raise ValueError("Lovense scheme must be http or https")

    url = f"{scheme}://{host}:{port}/command"
    request = urlrequest.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-platform": platform_name,
        },
        method="POST",
    )

    context = ssl._create_unverified_context() if scheme == "https" else None
    with urlrequest.urlopen(request, timeout=timeout_seconds, context=context) as response:
        body = response.read().decode("utf-8")

    return json.loads(body)


class FHPlayerHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/health":
            self._send_json({"ok": True, "port": PORT})
            return

        if parsed.path == "/":
            self.path = "/index.html"

        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        route = parsed.path.rstrip("/") or "/"

        if route == "/api/execute":
            self._handle_execute()
            return

        if route in {"/api/lovense/detect", "/api/lovense-detect"}:
            self._handle_lovense_detect()
            return

        if route in {"/api/lovense/command", "/api/lovense-command"}:
            self._handle_lovense_command()
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Unknown API route")

    def _handle_execute(self) -> None:
        try:
            payload = parse_json_body(self)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        command = str(payload.get("command", "")).strip()
        shell_name = str(payload.get("shell", "powershell")).strip().lower()
        dry_run = bool(payload.get("dryRun", False))
        timeout_seconds = float(payload.get("timeoutSeconds", 5))
        event = payload.get("event", {})

        if not command:
            self.send_error(HTTPStatus.BAD_REQUEST, "Command is required")
            return

        if timeout_seconds <= 0 or timeout_seconds > 60:
            self.send_error(HTTPStatus.BAD_REQUEST, "timeoutSeconds must be between 0 and 60")
            return

        response: dict[str, Any] = {
            "ok": True,
            "dryRun": dry_run,
            "shell": shell_name,
            "command": command,
            "event": event,
        }

        if dry_run:
            response["result"] = {
                "returnCode": 0,
                "stdout": "Dry run enabled. Command was not executed.",
                "stderr": "",
                "durationMs": 0,
            }
            self._send_json(response)
            return

        try:
            response["result"] = run_command(command, shell_name, timeout_seconds)
        except subprocess.TimeoutExpired:
            response["ok"] = False
            response["result"] = {
                "returnCode": -1,
                "stdout": "",
                "stderr": f"Command exceeded timeout of {timeout_seconds} seconds.",
                "durationMs": round(timeout_seconds * 1000, 1),
            }
            self._send_json(response, status=HTTPStatus.REQUEST_TIMEOUT)
            return
        except FileNotFoundError as exc:
            response["ok"] = False
            response["result"] = {
                "returnCode": -1,
                "stdout": "",
                "stderr": str(exc),
                "durationMs": 0,
            }
            self._send_json(response, status=HTTPStatus.BAD_REQUEST)
            return
        except Exception as exc:  # pragma: no cover - last-resort guard for UI errors
            response["ok"] = False
            response["result"] = {
                "returnCode": -1,
                "stdout": "",
                "stderr": str(exc),
                "durationMs": 0,
            }
            self._send_json(response, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return

        self._send_json(response)

    def _handle_lovense_detect(self) -> None:
        try:
            payload = parse_json_body(self)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        config = payload.get("config", {})
        timeout_seconds = float(payload.get("timeoutSeconds", 5))
        try:
            result = lovense_request(config, {"command": "GetToys"}, timeout_seconds=timeout_seconds)
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

        self._send_json({"ok": True, "result": result, "normalized": normalized})

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
                result = lovense_request(config, command_payload, timeout_seconds=timeout_seconds)
                results.append({"request": command_payload, "response": result})
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
    if not STATIC_DIR.exists():
        raise SystemExit(f"Missing static assets in {STATIC_DIR}")

    server = ThreadingHTTPServer((HOST, PORT), FHPlayerHandler)
    url = f"http://{HOST}:{PORT}"

    print(f"FHPlayer is running at {url}")
    print("Press Ctrl+C to stop.")

    if not os.environ.get("FHPLAYER_NO_BROWSER"):
        webbrowser.open(url)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
