"""
Rule engine for FHPlayer core.

This module provides parsing and evaluation of rule scripts for
synchronized stimulation based on funscript positions.
"""

import re
from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Union
from enum import Enum


class Operator(Enum):
    EQ = "=="
    NE = "!="
    LT = "<"
    LE = "<="
    GT = ">"
    GE = ">="
    AND = "and"
    OR = "or"


class ActionType(Enum):
    VIBRATE = "vibrate"
    ROTATE = "rotate"
    PUMP = "pump"
    AIR = "air"
    THRUSTING = "thrusting"
    FINGERING = "fingering"
    SUCTION = "suction"
    SETLEVEL = "setlevel"
    STOP = "stop"


@dataclass
class Condition:
    """Represents a condition in a rule."""
    left: str
    op: Operator
    right: Union[str, int, float]

    def evaluate(self, context: Dict[str, Any]) -> bool:
        """Evaluate the condition with given context."""
        left_val = self._get_value(self.left, context)
        right_val = self._get_value(self.right, context)

        if self.op == Operator.EQ:
            return left_val == right_val
        elif self.op == Operator.NE:
            return left_val != right_val
        elif self.op == Operator.LT:
            return left_val < right_val
        elif self.op == Operator.LE:
            return left_val <= right_val
        elif self.op == Operator.GT:
            return left_val > right_val
        elif self.op == Operator.GE:
            return left_val >= right_val
        elif self.op == Operator.AND:
            return bool(left_val) and bool(right_val)
        elif self.op == Operator.OR:
            return bool(left_val) or bool(right_val)
        return False

    def _get_value(self, expr: Union[str, int, float], context: Dict[str, Any]) -> Union[int, float, bool]:
        """Get the value of an expression."""
        if isinstance(expr, (int, float)):
            return expr
        if isinstance(expr, str):
            if expr in context:
                return context[expr]
            try:
                return float(expr)
            except ValueError:
                return expr  # string
        return expr


@dataclass
class Action:
    """Represents an action command."""
    type: ActionType
    params: List[Union[str, int, float]]  # Allow strings for variables

    def to_command(self, context: Optional[Dict[str, Any]] = None) -> str:
        """Convert to command string."""
        if self.type == ActionType.STOP:
            return "stop"
        eval_params = []
        for p in self.params:
            if isinstance(p, str) and context and p in context:
                eval_params.append(context[p])
            else:
                eval_params.append(p)
        params_str = ",".join(str(p) for p in eval_params)
        return f"{self.type.value}({params_str})"


@dataclass
class RuleBranch:
    """Represents a branch in the rule script."""
    condition: Optional[Condition]
    actions: List[Action]


@dataclass
class RuleScript:
    """Represents a parsed rule script."""
    assignments: Dict[str, str]  # variable assignments
    branches: List[RuleBranch]

    def evaluate(self, context: Dict[str, Any]) -> List[Action]:
        """Evaluate the script with given context and return actions."""
        # Apply assignments
        eval_context = context.copy()
        for var, expr in self.assignments.items():
            eval_context[var] = self._evaluate_expression(expr, eval_context)

        # Evaluate branches
        for branch in self.branches:
            if branch.condition is None or branch.condition.evaluate(eval_context):
                # Evaluate action parameters
                evaluated_actions = []
                for action in branch.actions:
                    eval_params = []
                    for p in action.params:
                        if isinstance(p, str) and p in eval_context:
                            eval_params.append(eval_context[p])
                        else:
                            eval_params.append(p)
                    evaluated_actions.append(Action(type=action.type, params=eval_params))
                return evaluated_actions
        return []

    def _evaluate_expression(self, expr: str, context: Dict[str, Any]) -> Union[int, float]:
        """Evaluate a simple expression."""
        # For now, just return the value if it's a number or variable
        if expr in context:
            return context[expr]
        try:
            return float(expr)
        except ValueError:
            raise ValueError(f"Cannot evaluate expression: {expr}")


class RuleEngine:
    """
    Engine for parsing and evaluating rule scripts.

    Supported syntax:
    - let var = expression
    - if condition then action1, action2
    - else if condition then action
    - else action
    """

    BASE_VARIABLES = {"pos", "index", "atMs", "currentMs", "deltaMs"}

    def __init__(self):
        self._compiled_scripts: Dict[str, RuleScript] = {}

    def parse_script(self, script_text: str) -> RuleScript:
        """Parse a rule script text into a RuleScript object."""
        lines = self._normalize_script(script_text)
        assignments = {}
        branches = []
        known_vars = set(self.BASE_VARIABLES)

        for line_num, line in enumerate(lines, 1):
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('//'):
                continue

            if line.startswith('let '):
                var, expr = self._parse_assignment(line, line_num)
                if var in known_vars:
                    raise ValueError(f"Variable {var} already defined or reserved")
                assignments[var] = expr
                known_vars.add(var)
            elif line.startswith('if '):
                condition, actions = self._parse_if(line, line_num, known_vars)
                branches.append(RuleBranch(condition=condition, actions=actions))
            elif line.startswith('else if '):
                condition, actions = self._parse_else_if(line, line_num, known_vars)
                branches.append(RuleBranch(condition=condition, actions=actions))
            elif line.startswith('else '):
                actions = self._parse_else(line, line_num, known_vars)
                branches.append(RuleBranch(condition=None, actions=actions))
            else:
                # Default branch
                actions = self._parse_actions(line, line_num, known_vars)
                branches.append(RuleBranch(condition=None, actions=actions))

        if not branches:
            raise ValueError("No executable branches found")

        return RuleScript(assignments=assignments, branches=branches)

    def evaluate_script(self, script: RuleScript, context: Dict[str, Any]) -> List[Action]:
        """Evaluate a parsed script with context."""
        return script.evaluate(context)

    def compile_and_evaluate(self, script_text: str, context: Dict[str, Any]) -> List[Action]:
        """Parse and evaluate a script in one step."""
        script = self.parse_script(script_text)
        return self.evaluate_script(script, context)

    def _normalize_script(self, text: str) -> List[str]:
        """Normalize script text to lines."""
        return [line.strip() for line in text.split('\n') if line.strip()]

    def _parse_assignment(self, line: str, line_num: int) -> tuple[str, str]:
        """Parse let var = expr."""
        match = re.match(r'let\s+(\w+)\s*=\s*(.+)', line)
        if not match:
            raise ValueError(f"Invalid assignment on line {line_num}")
        return match.group(1), match.group(2)

    def _parse_if(self, line: str, line_num: int, known_vars: set) -> tuple[Condition, List[Action]]:
        """Parse if condition then actions."""
        match = re.match(r'if\s+(.+?)\s+then\s+(.+)', line)
        if not match:
            raise ValueError(f"Invalid if on line {line_num}")
        condition = self._parse_condition(match.group(1), line_num, known_vars)
        actions = self._parse_actions(match.group(2), line_num, known_vars)
        return condition, actions

    def _parse_else_if(self, line: str, line_num: int, known_vars: set) -> tuple[Condition, List[Action]]:
        """Parse else if condition then actions."""
        match = re.match(r'else\s+if\s+(.+?)\s+then\s+(.+)', line)
        if not match:
            raise ValueError(f"Invalid else if on line {line_num}")
        condition = self._parse_condition(match.group(1), line_num, known_vars)
        actions = self._parse_actions(match.group(2), line_num, known_vars)
        return condition, actions

    def _parse_else(self, line: str, line_num: int, known_vars: set) -> List[Action]:
        """Parse else actions."""
        match = re.match(r'else\s+(.+)', line)
        if not match:
            raise ValueError(f"Invalid else on line {line_num}")
        return self._parse_actions(match.group(1), line_num, known_vars)

    def _parse_condition(self, expr: str, line_num: int, known_vars: set) -> Condition:
        """Parse a condition expression."""
        # Simple parsing for now: left op right
        for op in ['>=', '<=', '!=', '==', '>', '<']:
            if op in expr:
                left, right = expr.split(op, 1)
                operator = Operator(op)
                break
        else:
            raise ValueError(f"Invalid condition on line {line_num}")

        left = left.strip()
        right = self._parse_value(right.strip())

        if left not in known_vars:
            raise ValueError(f"Unknown variable {left} on line {line_num}")

        return Condition(left=left, op=operator, right=right)

    def _parse_actions(self, expr: str, line_num: int, known_vars: set) -> List[Action]:
        """Parse action list: action1, action2."""
        actions = []
        for action_str in expr.split(','):
            action_str = action_str.strip()
            if not action_str:
                continue
            actions.append(self._parse_action(action_str, line_num))
        return actions

    def _parse_action(self, expr: str, line_num: int) -> Action:
        """Parse a single action."""
        if expr == 'stop':
            return Action(type=ActionType.STOP, params=[])

        match = re.match(r'(\w+)\((.*?)\)', expr)
        if not match:
            raise ValueError(f"Invalid action on line {line_num}")

        action_type = ActionType(match.group(1))
        params_str = match.group(2)
        params = []
        if params_str:
            for p in params_str.split(','):
                params.append(self._parse_value(p.strip()))

        return Action(type=action_type, params=params)

    def _parse_value(self, expr: str) -> Union[str, int, float]:
        """Parse a value expression."""
        try:
            return int(expr)
        except ValueError:
            try:
                return float(expr)
            except ValueError:
                return expr

    def _evaluate_expression(self, expr: str, context: Dict[str, Any]) -> Union[int, float]:
        """Evaluate a simple expression."""
        # For now, just return the value if it's a number or variable
        if expr in context:
            return context[expr]
        try:
            return float(expr)
        except ValueError:
            raise ValueError(f"Cannot evaluate expression: {expr}")