"""
Funscript parser for FHPlayer core.

This module provides parsing and handling of Funscript files,
which contain timed actions for synchronized stimulation.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Dict, Any
import json


@dataclass
class FunscriptAction:
    """
    Represents a single action in a funscript.

    Attributes:
        at: Time in milliseconds.
        pos: Position value (typically 0-100).
        index: Index in the actions list.
    """
    at: int
    pos: int
    index: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary."""
        return {'at': self.at, 'pos': self.pos}

    @classmethod
    def from_dict(cls, data: Dict[str, Any], index: int = 0) -> 'FunscriptAction':
        """Deserialize from dictionary."""
        return cls(at=int(data['at']), pos=int(data['pos']), index=index)


@dataclass
class FunscriptMetadata:
    """
    Metadata for a funscript.

    Attributes:
        title: Optional title.
        creator: Optional creator.
        description: Optional description.
        duration: Optional duration in milliseconds.
        range: Optional range (e.g., 90 for 0-90).
        inverted: Whether the script is inverted.
        fhplayer: FHPlayer-specific metadata.
    """
    title: Optional[str] = None
    creator: Optional[str] = None
    description: Optional[str] = None
    duration: Optional[int] = None
    range: Optional[int] = None
    inverted: bool = False
    fhplayer: Optional[Dict[str, Any]] = None

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary."""
        data = {}
        if self.title:
            data['title'] = self.title
        if self.creator:
            data['creator'] = self.creator
        if self.description:
            data['description'] = self.description
        if self.duration is not None:
            data['duration'] = self.duration
        if self.range is not None:
            data['range'] = self.range
        if self.inverted:
            data['inverted'] = self.inverted
        if self.fhplayer:
            data['fhplayer'] = self.fhplayer
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'FunscriptMetadata':
        """Deserialize from dictionary."""
        return cls(
            title=data.get('title'),
            creator=data.get('creator'),
            description=data.get('description'),
            duration=data.get('duration'),
            range=data.get('range'),
            inverted=bool(data.get('inverted', False)),
            fhplayer=data.get('fhplayer')
        )


@dataclass
class Funscript:
    """
    Represents a parsed funscript.

    Attributes:
        actions: List of actions, sorted by time.
        metadata: Metadata of the script.
        version: Version of the funscript format.
    """
    actions: List[FunscriptAction]
    metadata: FunscriptMetadata
    version: Optional[str] = None

    def __post_init__(self):
        # Ensure actions are sorted
        self.actions.sort(key=lambda a: a.at)

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dictionary."""
        data = {
            'actions': [action.to_dict() for action in self.actions]
        }
        if self.version:
            data['version'] = self.version
        metadata_dict = self.metadata.to_dict()
        if metadata_dict:
            data['metadata'] = metadata_dict
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Funscript':
        """Deserialize from dictionary."""
        actions = [FunscriptAction.from_dict(a, i) for i, a in enumerate(data.get('actions', []))]
        metadata = FunscriptMetadata.from_dict(data.get('metadata', {}))
        return cls(
            actions=actions,
            metadata=metadata,
            version=data.get('version')
        )

    @classmethod
    def load_from_file(cls, file_path: str) -> 'Funscript':
        """Load and parse a funscript from file."""
        path = Path(file_path)
        with path.open('r', encoding='utf-8') as f:
            data = json.load(f)
        return cls.from_dict(data)

    def save_to_file(self, file_path: str) -> None:
        """Save the funscript to file."""
        path = Path(file_path)
        data = self.to_dict()
        with path.open('w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    def validate(self) -> List[str]:
        """
        Validate the funscript.

        Returns a list of error messages. Empty list means valid.
        """
        errors = []
        if not self.actions:
            errors.append("No actions found")
            return errors

        # Check for duplicate times
        times = set()
        for action in self.actions:
            if action.at in times:
                errors.append(f"Duplicate time: {action.at}ms")
            times.add(action.at)

        # Check position range
        for action in self.actions:
            if not (0 <= action.pos <= 100):
                errors.append(f"Invalid position {action.pos} at {action.at}ms (must be 0-100)")

        # Check monotonic time
        prev_time = -1
        for action in self.actions:
            if action.at <= prev_time:
                errors.append(f"Non-monotonic time: {action.at}ms after {prev_time}ms")
            prev_time = action.at

        return errors

    def get_position_at(self, time_ms: int) -> int:
        """
        Get the position at a specific time using linear interpolation.

        Args:
            time_ms: Time in milliseconds.

        Returns:
            Position value (0-100).
        """
        if not self.actions:
            return 0

        # Find the actions before and after the time
        prev_action = None
        next_action = None
        for action in self.actions:
            if action.at <= time_ms:
                prev_action = action
            elif action.at > time_ms:
                next_action = action
                break

        if prev_action is None:
            return self.actions[0].pos
        if next_action is None:
            return prev_action.pos

        # Linear interpolation
        time_diff = next_action.at - prev_action.at
        pos_diff = next_action.pos - prev_action.pos
        if time_diff == 0:
            return prev_action.pos

        ratio = (time_ms - prev_action.at) / time_diff
        interpolated_pos = prev_action.pos + int(pos_diff * ratio)
        return max(0, min(100, interpolated_pos))

    def get_duration(self) -> int:
        """Get the total duration in milliseconds."""
        if not self.actions:
            return 0
        return self.actions[-1].at