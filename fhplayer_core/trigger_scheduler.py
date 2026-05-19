"""
Trigger scheduler for FHPlayer core.

This module handles scheduling and triggering of actions based on
funscript positions and rule evaluation.
"""

import threading
import time
from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Callable
from concurrent.futures import ThreadPoolExecutor

from .playlist_model import Playlist, PlaylistEntry
from .funscript_parser import Funscript
from .rule_engine import RuleEngine, Action as RuleAction
from .lovense_client import LovenseClient, LovenseCommand


@dataclass
class ScheduledAction:
    """
    A scheduled action to be executed at a specific time.

    Attributes:
        time_ms: Execution time in milliseconds.
        entry: The playlist entry.
        funscript_action: The funscript action data.
        rule_actions: List of actions from rule evaluation.
    """
    time_ms: int
    entry: PlaylistEntry
    funscript_action: Dict[str, Any]
    rule_actions: List[RuleAction]


class TriggerScheduler:
    """
    Scheduler for triggering Lovense actions based on video playback.

    Manages timing and execution of actions from funscripts and rules.
    """

    def __init__(self, lovense_client: LovenseClient, max_workers: int = 4):
        self.lovense_client = lovense_client
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.rule_engine = RuleEngine()
        self._scheduled_actions: List[ScheduledAction] = []
        self._timers: List[threading.Timer] = []
        self._lock = threading.Lock()
        self._running = False
        self._current_time_ms = 0
        self._on_action_triggered: Optional[Callable[[ScheduledAction], None]] = None

    def set_on_action_triggered(self, callback: Callable[[ScheduledAction], None]):
        """Set callback for when an action is triggered."""
        self._on_action_triggered = callback

    def start(self):
        """Start the scheduler."""
        with self._lock:
            self._running = True

    def stop(self):
        """Stop the scheduler and cancel all pending actions."""
        with self._lock:
            self._running = False
            for timer in self._timers:
                timer.cancel()
            self._timers.clear()
            self._scheduled_actions.clear()

    def update_current_time(self, time_ms: int):
        """
        Update the current playback time.

        This will reschedule actions based on the new time.
        """
        with self._lock:
            self._current_time_ms = time_ms
            if self._running:
                self._reschedule_actions()

    def load_playlist(self, playlist: Playlist, funscripts: Dict[str, Funscript]):
        """
        Load a playlist and associated funscripts.

        Args:
            playlist: The playlist to load.
            funscripts: Dict mapping entry titles to funscript objects.
        """
        with self._lock:
            self._scheduled_actions.clear()
            for entry in playlist.entries:
                funscript = funscripts.get(entry.title)
                if funscript:
                    self._schedule_entry_actions(entry, funscript)

    def _schedule_entry_actions(self, entry: PlaylistEntry, funscript: Funscript):
        """Schedule actions for a single entry."""
        # Parse rules once
        try:
            rule_script = self.rule_engine.parse_script(entry.rules_text)
        except Exception:
            # Skip invalid rules
            return

        for action in funscript.actions:
            # Evaluate rules for this position
            context = {
                'pos': action.pos,
                'index': action.index,
                'atMs': action.at,
                'currentMs': action.at,  # For evaluation
                'deltaMs': 0
            }
            rule_actions = self.rule_engine.evaluate_script(rule_script, context)

            if rule_actions:
                scheduled = ScheduledAction(
                    time_ms=action.at,
                    entry=entry,
                    funscript_action={'at': action.at, 'pos': action.pos, 'index': action.index},
                    rule_actions=rule_actions
                )
                self._scheduled_actions.append(scheduled)

        # Sort by time
        self._scheduled_actions.sort(key=lambda a: a.time_ms)

    def _reschedule_actions(self):
        """Reschedule timers based on current time."""
        # Cancel existing timers
        for timer in self._timers:
            timer.cancel()
        self._timers.clear()

        if not self._running:
            return

        # Schedule future actions
        for action in self._scheduled_actions:
            if action.time_ms >= self._current_time_ms:
                delay_sec = (action.time_ms - self._current_time_ms) / 1000.0
                timer = threading.Timer(delay_sec, self._trigger_action, args=[action])
                timer.start()
                self._timers.append(timer)

    def _trigger_action(self, action: ScheduledAction):
        """Trigger a scheduled action."""
        if not self._running:
            return

        # Execute in thread pool
        self.executor.submit(self._execute_action, action)

        # Callback
        if self._on_action_triggered:
            self._on_action_triggered(action)

    def _execute_action(self, action: ScheduledAction):
        """Execute the action by sending commands to Lovense."""
        commands = []
        for rule_action in action.rule_actions:
            cmd = LovenseCommand(
                action=rule_action.to_command(),
                stop_previous=True
            )
            commands.append(cmd)

        if commands:
            response = self.lovense_client.send_commands(commands)
            # Log or handle response as needed

    def get_next_action_time(self) -> Optional[int]:
        """Get the time of the next scheduled action in ms."""
        with self._lock:
            for action in self._scheduled_actions:
                if action.time_ms >= self._current_time_ms:
                    return action.time_ms
        return None

    def get_scheduled_actions_count(self) -> int:
        """Get the number of scheduled actions."""
        with self._lock:
            return len([a for a in self._scheduled_actions if a.time_ms >= self._current_time_ms])

    def shutdown(self):
        """Shutdown the scheduler and executor."""
        self.stop()
        self.executor.shutdown(wait=True)