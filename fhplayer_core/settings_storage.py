"""
Settings storage for FHPlayer core.

This module handles loading, saving, and validating application settings.
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict


@dataclass
class UpdateSettings:
    """Settings for update checking."""
    auto_check_enabled: bool = False
    last_result: Optional[Dict[str, Any]] = None
    manual_disclosure_acknowledged_version: str = ""
    release_disclosure_suppressed_version: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "autoCheckEnabled": self.auto_check_enabled,
            "lastResult": self.last_result,
            "manualDisclosureAcknowledgedVersion": self.manual_disclosure_acknowledged_version,
            "releaseDisclosureSuppressedVersion": self.release_disclosure_suppressed_version,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'UpdateSettings':
        return cls(
            auto_check_enabled=bool(data.get("autoCheckEnabled", False)),
            last_result=data.get("lastResult"),
            manual_disclosure_acknowledged_version=data.get("manualDisclosureAcknowledgedVersion", ""),
            release_disclosure_suppressed_version=data.get("releaseDisclosureSuppressedVersion", "")
        )


@dataclass
class UiSettings:
    """Settings for user interface."""
    show_diagnostics: bool = True
    show_funscript_overview: bool = True
    show_execution_log: bool = True
    show_updates: bool = True

    def to_dict(self) -> Dict[str, Any]:
        return {
            "showDiagnostics": self.show_diagnostics,
            "showFunscriptOverview": self.show_funscript_overview,
            "showExecutionLog": self.show_execution_log,
            "showUpdates": self.show_updates,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'UiSettings':
        return cls(
            show_diagnostics=bool(data.get("showDiagnostics", True)),
            show_funscript_overview=bool(data.get("showFunscriptOverview", True)),
            show_execution_log=bool(data.get("showExecutionLog", True)),
            show_updates=bool(data.get("showUpdates", True))
        )


@dataclass
class LegalSettings:
    """Settings for legal acknowledgments."""
    last_acknowledged_version: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "lastAcknowledgedVersion": self.last_acknowledged_version,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'LegalSettings':
        return cls(
            last_acknowledged_version=data.get("lastAcknowledgedVersion", "")
        )


@dataclass
class AppSettings:
    """Complete application settings."""
    updates: UpdateSettings
    ui: UiSettings
    legal: LegalSettings

    def to_dict(self) -> Dict[str, Any]:
        return {
            "updates": self.updates.to_dict(),
            "ui": self.ui.to_dict(),
            "legal": self.legal.to_dict()
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'AppSettings':
        return cls(
            updates=UpdateSettings.from_dict(data.get("updates", {})),
            ui=UiSettings.from_dict(data.get("ui", {})),
            legal=LegalSettings.from_dict(data.get("legal", {}))
        )

    @classmethod
    def defaults(cls) -> 'AppSettings':
        return cls(
            updates=UpdateSettings(),
            ui=UiSettings(),
            legal=LegalSettings()
        )


class SettingsStorage:
    """
    Handles storage of application settings to/from JSON file.
    """

    def __init__(self, settings_path: str):
        self.settings_path = Path(settings_path)

    def load(self) -> AppSettings:
        """
        Load settings from file.

        Returns default settings if file doesn't exist or is invalid.
        """
        if not self.settings_path.exists():
            return AppSettings.defaults()

        try:
            with self.settings_path.open('r', encoding='utf-8') as f:
                data = json.load(f)
            return AppSettings.from_dict(data)
        except (OSError, json.JSONDecodeError, KeyError):
            return AppSettings.defaults()

    def save(self, settings: AppSettings) -> None:
        """
        Save settings to file.

        Creates parent directories if needed.
        """
        self.settings_path.parent.mkdir(parents=True, exist_ok=True)
        data = settings.to_dict()
        with self.settings_path.open('w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')

    def update(self, updates: Dict[str, Any]) -> AppSettings:
        """
        Update settings with partial data and save.

        Args:
            updates: Partial settings dict to merge.

        Returns:
            Updated settings.
        """
        current = self.load()
        # Simple merge - in real app, might need deeper merging
        if "updates" in updates:
            for key, value in updates["updates"].items():
                if hasattr(current.updates, key):
                    setattr(current.updates, key, value)
        if "ui" in updates:
            for key, value in updates["ui"].items():
                if hasattr(current.ui, key):
                    setattr(current.ui, key, value)
        if "legal" in updates:
            for key, value in updates["legal"].items():
                if hasattr(current.legal, key):
                    setattr(current.legal, key, value)
        self.save(current)
        return current