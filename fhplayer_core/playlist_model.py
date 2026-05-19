"""
Playlist model for FHPlayer core.

This module provides data structures and operations for managing playlists,
independent of UI, web frameworks, or platform-specific code.
"""

from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional, Dict, Any
import json


@dataclass
class PlaylistEntry:
    """
    Represents a single entry in a playlist.

    Attributes:
        title: Display title for the entry.
        video_path: Path to the video file.
        funscript_path: Optional path to the funscript file.
        execution_mode: Mode for execution (e.g., 'lovense-live').
        rules_text: Text of rules for stimulation.
        lovense_config: Configuration for Lovense connections.
    """
    title: str
    video_path: str
    funscript_path: Optional[str]
    execution_mode: str
    rules_text: str
    lovense_config: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        """Serialize the entry to a dictionary."""
        data = asdict(self)
        # Ensure funscript_path is not included if None
        if self.funscript_path is None:
            data.pop('funscript_path', None)
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'PlaylistEntry':
        """Deserialize an entry from a dictionary."""
        # Handle missing funscript_path
        funscript_path = data.get('funscript_path')
        return cls(
            title=data['title'],
            video_path=data['video_path'],
            funscript_path=funscript_path,
            execution_mode=data['execution_mode'],
            rules_text=data['rules_text'],
            lovense_config=data['lovense_config']
        )

    def validate(self) -> List[str]:
        """
        Validate the entry.

        Returns a list of error messages. Empty list means valid.
        """
        errors = []
        if not self.title.strip():
            errors.append("Title cannot be empty")
        if not self.video_path.strip():
            errors.append("Video path cannot be empty")
        # TODO: Integrate with rule_engine for rules_text validation
        # TODO: Integrate with funscript_parser for funscript_path validation
        return errors


@dataclass
class Playlist:
    """
    Represents a playlist containing multiple entries.

    Attributes:
        entries: List of playlist entries.
        playback_mode: Mode for playback (e.g., 'sequential').
        lovense_global_config: Global Lovense configuration.
        schema_version: Version of the schema for compatibility.
        created_at: Timestamp when the playlist was created.
    """
    entries: List[PlaylistEntry]
    playback_mode: str
    lovense_global_config: Dict[str, Any]
    schema_version: int = 1
    created_at: Optional[datetime] = None

    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.now(timezone.utc)

    def add_entry(self, entry: PlaylistEntry) -> None:
        """Add an entry to the playlist."""
        self.entries.append(entry)

    def remove_entry(self, index: int) -> None:
        """Remove an entry at the given index."""
        if 0 <= index < len(self.entries):
            self.entries.pop(index)

    def get_entry(self, index: int) -> Optional[PlaylistEntry]:
        """Get an entry at the given index."""
        if 0 <= index < len(self.entries):
            return self.entries[index]
        return None

    def move_entry(self, from_index: int, to_index: int) -> None:
        """Move an entry from one index to another."""
        if 0 <= from_index < len(self.entries) and 0 <= to_index < len(self.entries):
            entry = self.entries.pop(from_index)
            self.entries.insert(to_index, entry)

    def clear(self) -> None:
        """Clear all entries from the playlist."""
        self.entries.clear()

    def to_dict(self) -> Dict[str, Any]:
        """Serialize the playlist to a dictionary."""
        return {
            'schemaVersion': self.schema_version,
            'type': 'fhplayer-playlist',
            'createdAt': self.created_at.isoformat(),
            'playbackMode': self.playback_mode,
            'lovense': self.lovense_global_config,
            'entries': [entry.to_dict() for entry in self.entries]
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Playlist':
        """Deserialize a playlist from a dictionary."""
        if data.get('schemaVersion') != 1:
            raise ValueError("Unsupported schema version")
        if data.get('type') != 'fhplayer-playlist':
            raise ValueError("Invalid playlist type")
        created_at = datetime.fromisoformat(data['createdAt'])
        entries = [PlaylistEntry.from_dict(e) for e in data['entries']]
        return cls(
            entries=entries,
            playback_mode=data['playbackMode'],
            lovense_global_config=data['lovense'],
            schema_version=data['schemaVersion'],
            created_at=created_at
        )

    def save_to_file(self, file_path: str) -> None:
        """Save the playlist to a JSON file."""
        path = Path(file_path)
        data = self.to_dict()
        with path.open('w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    @classmethod
    def load_from_file(cls, file_path: str) -> 'Playlist':
        """Load a playlist from a JSON file."""
        path = Path(file_path)
        with path.open('r', encoding='utf-8') as f:
            data = json.load(f)
        return cls.from_dict(data)

    def validate_entries(self) -> List[str]:
        """
        Validate all entries.

        Returns a list of error messages. Empty list means all valid.
        """
        errors = []
        for i, entry in enumerate(self.entries):
            entry_errors = entry.validate()
            for error in entry_errors:
                errors.append(f"Entry {i+1}: {error}")
        return errors