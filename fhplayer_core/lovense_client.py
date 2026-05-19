"""
Lovense client for FHPlayer core.

This module provides communication with Lovense devices via HTTP API.
"""

import requests
import json
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
from urllib.parse import urljoin


@dataclass
class LovenseConnection:
    """
    Configuration for a Lovense connection.

    Attributes:
        id: Unique identifier.
        label: Display label.
        scheme: HTTP scheme (http/https).
        host: Hostname or IP.
        port: Port number.
        platform_name: Platform identifier.
    """
    id: str
    label: str
    scheme: str
    host: str
    port: int
    platform_name: str

    def get_base_url(self) -> str:
        """Get the base URL for API calls."""
        return f"{self.scheme}://{self.host}:{self.port}/"


@dataclass
class LovenseCommand:
    """
    A command to send to Lovense devices.

    Attributes:
        action: Action string (e.g., "Vibrate:10").
        toy: Optional toy ID to target specific device.
        stop_previous: Whether to stop previous actions.
        time_sec: Optional duration in seconds.
    """
    action: str
    toy: Optional[str] = None
    stop_previous: bool = True
    time_sec: Optional[int] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for API."""
        data = {"command": self.action, "stopPrevious": self.stop_previous}
        if self.toy:
            data["toy"] = self.toy
        if self.time_sec is not None:
            data["timeSec"] = self.time_sec
        return data


@dataclass
class LovenseResponse:
    """
    Response from Lovense API.

    Attributes:
        ok: Whether the request was successful.
        error: Error message if not ok.
        data: Additional response data.
    """
    ok: bool
    error: Optional[str] = None
    data: Optional[Dict[str, Any]] = None


class LovenseClient:
    """
    Client for communicating with Lovense devices.

    Handles sending commands to configured connections.
    """

    def __init__(self, connection: LovenseConnection, timeout_seconds: int = 5):
        self.connection = connection
        self.timeout_seconds = timeout_seconds

    def send_commands(self, commands: List[LovenseCommand]) -> LovenseResponse:
        """
        Send multiple commands to Lovense.

        Args:
            commands: List of commands to send.

        Returns:
            Response from the API.
        """
        url = urljoin(self.connection.get_base_url(), "api/lovense/command")
        payload = {
            "config": {
                "scheme": self.connection.scheme,
                "host": self.connection.host,
                "port": self.connection.port,
                "platformName": self.connection.platform_name,
            },
            "timeoutSeconds": self.timeout_seconds,
            "commands": [cmd.to_dict() for cmd in commands],
        }

        try:
            response = requests.post(url, json=payload, timeout=self.timeout_seconds)
            data = response.json()
            if response.ok and data.get("ok"):
                return LovenseResponse(ok=True, data=data)
            else:
                error = data.get("error", f"HTTP {response.status_code}")
                return LovenseResponse(ok=False, error=error, data=data)
        except Exception as e:
            return LovenseResponse(ok=False, error=str(e))

    def send_command(self, command: LovenseCommand) -> LovenseResponse:
        """
        Send a single command.

        Args:
            command: Command to send.

        Returns:
            Response from the API.
        """
        return self.send_commands([command])

    def stop_all(self) -> LovenseResponse:
        """
        Stop all actions on all devices.

        Returns:
            Response from the API.
        """
        stop_command = LovenseCommand(action="Stop", stop_previous=True)
        return self.send_command(stop_command)

    def detect_devices(self) -> LovenseResponse:
        """
        Detect available Lovense devices.

        Returns:
            Response with detected devices.
        """
        url = urljoin(self.connection.get_base_url(), "api/lovense/detect")

        try:
            response = requests.get(url, timeout=self.timeout_seconds)
            data = response.json()
            if response.ok and data.get("ok"):
                return LovenseResponse(ok=True, data=data)
            else:
                error = data.get("error", f"HTTP {response.status_code}")
                return LovenseResponse(ok=False, error=error, data=data)
        except Exception as e:
            return LovenseResponse(ok=False, error=str(e))