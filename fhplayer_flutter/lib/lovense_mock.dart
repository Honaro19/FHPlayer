import 'dart:math' as math;

class LovenseActionContext {
  const LovenseActionContext({
    required this.index,
    required this.atMs,
    required this.pos,
    required this.currentMs,
    required this.deltaMs,
    this.triggerGapMs = -1,
    this.burstStartResolver,
    this.burstDurationMsResolver,
    this.burstMemberResolver,
    this.burstIndexResolver,
    this.burstCountResolver,
  });

  final int index;
  final int atMs;
  final int pos;
  final int currentMs;
  final int deltaMs;
  final int triggerGapMs;
  final int Function(int maxGapMs, int maxTriggers)? burstStartResolver;
  final int Function(int maxGapMs, int maxTriggers)? burstDurationMsResolver;
  final int Function(int maxGapMs, int maxTriggers)? burstMemberResolver;
  final int Function(int maxGapMs, int maxTriggers)? burstIndexResolver;
  final int Function(int maxGapMs)? burstCountResolver;
}

class LovenseMockDevice {
  const LovenseMockDevice({
    required this.id,
    required this.name,
    required this.capabilities,
  });

  final String id;
  final String name;
  final Set<String> capabilities;

  bool supports(String action) => capabilities.contains(action);
}

enum LovenseMockCommandAction { vibrate, stop }

class LovenseMockCommand {
  LovenseMockCommand({
    required this.device,
    required this.action,
    required this.context,
    this.strength,
    this.durationMs,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final LovenseMockDevice device;
  final LovenseMockCommandAction action;
  final LovenseActionContext context;
  final int? strength;
  final int? durationMs;
  final DateTime createdAt;

  String get commandText {
    return switch (action) {
      LovenseMockCommandAction.vibrate => 'Vibrate:${strength ?? 0}',
      LovenseMockCommandAction.stop => 'Stop',
    };
  }

  Map<String, Object> toPayload() {
    final Map<String, Object> payload = <String, Object>{
      'toy': device.id,
      'command': commandText,
      'stopPrevious': true,
    };
    if (durationMs != null) {
      payload['durationMs'] = durationMs!;
    }
    return payload;
  }
}

enum LovenseMockEvaluationStatus {
  commandGenerated,
  noMatchingRule,
  ruleInvalid,
  noDevicesConfigured,
}

class LovenseMockEvaluationResult {
  const LovenseMockEvaluationResult({
    required this.status,
    required this.message,
    this.device,
    this.command,
  });

  final LovenseMockEvaluationStatus status;
  final String message;
  final LovenseMockDevice? device;
  final LovenseMockCommand? command;

  bool get hasCommand => command != null;
}

enum LovenseMockConditionOperator {
  greaterThan,
  greaterOrEqual,
  lessThan,
  lessOrEqual,
  equal,
  notEqual,
}

class LovenseMockNumberExpression {
  const LovenseMockNumberExpression.literal(this.value)
    : variableName = null,
      functionName = null,
      functionArg1 = null,
      functionArg2 = null;

  const LovenseMockNumberExpression.variable(this.variableName)
    : value = null,
      functionName = null,
      functionArg1 = null,
      functionArg2 = null;

  const LovenseMockNumberExpression.function({
    required this.functionName,
    required this.functionArg1,
    this.functionArg2,
  }) : value = null,
       variableName = null;

  final num? value;
  final String? variableName;
  final String? functionName;
  final int? functionArg1;
  final int? functionArg2;

  num resolve(LovenseActionContext context) {
    final String? function = functionName;
    if (function != null) {
      final int first = functionArg1 ?? 0;
      final int second = functionArg2 ?? 0;
      return switch (function) {
        'burststart' => context.burstStartResolver?.call(first, second) ?? 0,
        'burstduration' =>
          context.burstDurationMsResolver?.call(first, second) ?? 0,
        'burstmember' => context.burstMemberResolver?.call(first, second) ?? 0,
        'burstindex' => context.burstIndexResolver?.call(first, second) ?? 0,
        'burstcount' => context.burstCountResolver?.call(first) ?? 0,
        _ => 0,
      };
    }

    final String? variable = variableName;
    if (variable == null) {
      return value ?? 0;
    }
    return switch (variable) {
      'pos' || 'level' => context.pos,
      'index' => context.index,
      'at' || 'time' => context.atMs,
      'current' || 'currentms' => context.currentMs,
      'delta' || 'deltams' => context.deltaMs,
      'gap' ||
      'gapms' ||
      'triggergap' ||
      'triggergapms' => context.triggerGapMs,
      _ => 0,
    };
  }
}

class LovenseMockCondition {
  const LovenseMockCondition({
    required this.left,
    required this.operator,
    required this.right,
  });

  final LovenseMockNumberExpression left;
  final LovenseMockConditionOperator operator;
  final LovenseMockNumberExpression right;

  bool matches(LovenseActionContext context) {
    final num leftValue = left.resolve(context);
    final num rightValue = right.resolve(context);
    return switch (operator) {
      LovenseMockConditionOperator.greaterThan => leftValue > rightValue,
      LovenseMockConditionOperator.greaterOrEqual => leftValue >= rightValue,
      LovenseMockConditionOperator.lessThan => leftValue < rightValue,
      LovenseMockConditionOperator.lessOrEqual => leftValue <= rightValue,
      LovenseMockConditionOperator.equal => leftValue == rightValue,
      LovenseMockConditionOperator.notEqual => leftValue != rightValue,
    };
  }
}

class LovenseMockRuleCommand {
  const LovenseMockRuleCommand.stop()
    : action = LovenseMockCommandAction.stop,
      strength = null,
      durationMs = null;

  const LovenseMockRuleCommand.vibrate({
    required this.strength,
    this.durationMs,
  }) : action = LovenseMockCommandAction.vibrate;

  final LovenseMockCommandAction action;
  final LovenseMockNumberExpression? strength;
  final LovenseMockNumberExpression? durationMs;

  LovenseMockCommand toCommand(
    LovenseMockDevice device,
    LovenseActionContext context,
  ) {
    return switch (action) {
      LovenseMockCommandAction.stop => LovenseMockCommand(
        device: device,
        action: LovenseMockCommandAction.stop,
        context: context,
      ),
      LovenseMockCommandAction.vibrate =>
        device.supports('vibrate')
            ? LovenseMockCommand(
                device: device,
                action: LovenseMockCommandAction.vibrate,
                strength: _clampInt(strength?.resolve(context), 0, 20),
                durationMs: durationMs == null
                    ? null
                    : _clampInt(durationMs!.resolve(context), 0, 60000),
                context: context,
              )
            : LovenseMockCommand(
                device: device,
                action: LovenseMockCommandAction.stop,
                context: context,
              ),
    };
  }
}

class LovenseMockRuleBranch {
  const LovenseMockRuleBranch({required this.condition, required this.command});

  final LovenseMockCondition? condition;
  final LovenseMockRuleCommand command;

  bool matches(LovenseActionContext context) {
    return condition?.matches(context) ?? true;
  }
}

class LovenseMockRuleScript {
  const LovenseMockRuleScript._({
    required this.source,
    required this.branches,
    required this.error,
  });

  factory LovenseMockRuleScript.parse(String source) {
    final String trimmedSource = source.trim();
    if (trimmedSource.isEmpty) {
      return LovenseMockRuleScript._(
        source: source,
        branches: const <LovenseMockRuleBranch>[],
        error: 'Rule script is empty.',
      );
    }

    final List<LovenseMockRuleBranch> branches = <LovenseMockRuleBranch>[];
    final List<String> lines = trimmedSource.split(RegExp(r'\r?\n'));
    for (int index = 0; index < lines.length; index += 1) {
      final String line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }

      try {
        branches.add(_parseBranch(line));
      } on FormatException catch (error) {
        return LovenseMockRuleScript._(
          source: source,
          branches: const <LovenseMockRuleBranch>[],
          error: 'Line ${index + 1}: ${error.message}',
        );
      }
    }

    if (branches.isEmpty) {
      return LovenseMockRuleScript._(
        source: source,
        branches: const <LovenseMockRuleBranch>[],
        error: 'Rule script is empty.',
      );
    }

    return LovenseMockRuleScript._(
      source: source,
      branches: branches,
      error: null,
    );
  }

  static const String defaultSource =
      'if pos >= 15 then vibrate(10, 800)\nelse stop()';
  static const Set<String> _supportedVariables = <String>{
    'pos',
    'level',
    'index',
    'at',
    'time',
    'current',
    'currentms',
    'delta',
    'deltams',
    'gap',
    'gapms',
    'triggergap',
    'triggergapms',
  };
  static const Set<String> _supportedFunctions = <String>{
    'burststart',
    'burstduration',
    'burstmember',
    'burstindex',
    'burstcount',
  };

  final String source;
  final List<LovenseMockRuleBranch> branches;
  final String? error;

  bool get isValid => error == null;

  LovenseMockCommand? evaluate(
    LovenseActionContext context,
    LovenseMockDevice device,
  ) {
    if (!isValid) {
      return null;
    }
    for (final LovenseMockRuleBranch branch in branches) {
      if (branch.matches(context)) {
        return branch.command.toCommand(device, context);
      }
    }
    return null;
  }

  static LovenseMockRuleBranch _parseBranch(String line) {
    final RegExp ifPattern = RegExp(
      r'^if\s+(.+?)\s+then\s+(.+)$',
      caseSensitive: false,
    );
    final RegExp elseIfPattern = RegExp(
      r'^else\s+if\s+(.+?)\s+then\s+(.+)$',
      caseSensitive: false,
    );
    final RegExp elsePattern = RegExp(
      r'^else(?:\s+then)?\s+(.+)$',
      caseSensitive: false,
    );

    final RegExpMatch? ifMatch = ifPattern.firstMatch(line);
    final RegExpMatch? elseIfMatch = elseIfPattern.firstMatch(line);
    final RegExpMatch? elseMatch = elsePattern.firstMatch(line);
    if (elseIfMatch != null) {
      return LovenseMockRuleBranch(
        condition: _parseCondition(elseIfMatch.group(1)!),
        command: _parseCommand(elseIfMatch.group(2)!),
      );
    }
    if (ifMatch != null) {
      return LovenseMockRuleBranch(
        condition: _parseCondition(ifMatch.group(1)!),
        command: _parseCommand(ifMatch.group(2)!),
      );
    }
    if (elseMatch != null) {
      return LovenseMockRuleBranch(
        condition: null,
        command: _parseCommand(elseMatch.group(1)!),
      );
    }

    throw const FormatException(
      'Use "if ... then ..." or "else ..." branches.',
    );
  }

  static LovenseMockCondition _parseCondition(String source) {
    final RegExp conditionPattern = RegExp(
      r'^\s*(.+?)\s*(>=|<=|==|!=|>|<)\s*(.+?)\s*$',
    );
    final RegExpMatch? match = conditionPattern.firstMatch(source);
    if (match == null) {
      throw const FormatException('Invalid condition.');
    }
    return LovenseMockCondition(
      left: _parseNumberExpression(match.group(1)!),
      operator: _parseConditionOperator(match.group(2)!),
      right: _parseNumberExpression(match.group(3)!),
    );
  }

  static LovenseMockConditionOperator _parseConditionOperator(String source) {
    return switch (source) {
      '>' => LovenseMockConditionOperator.greaterThan,
      '>=' => LovenseMockConditionOperator.greaterOrEqual,
      '<' => LovenseMockConditionOperator.lessThan,
      '<=' => LovenseMockConditionOperator.lessOrEqual,
      '==' => LovenseMockConditionOperator.equal,
      '!=' => LovenseMockConditionOperator.notEqual,
      _ => throw const FormatException('Invalid condition operator.'),
    };
  }

  static LovenseMockRuleCommand _parseCommand(String source) {
    final RegExp commandPattern = RegExp(
      r'^\s*([A-Za-z][A-Za-z0-9]*)\s*\((.*)\)\s*$',
    );
    final RegExpMatch? match = commandPattern.firstMatch(source);
    if (match == null) {
      throw const FormatException('Invalid command.');
    }

    final String commandName = match.group(1)!.toLowerCase();
    final List<String> arguments = _splitTopLevelArguments(match.group(2)!);

    if (commandName == 'stop') {
      if (arguments.isNotEmpty) {
        throw const FormatException('stop() does not accept arguments.');
      }
      return const LovenseMockRuleCommand.stop();
    }

    if (commandName == 'vibrate') {
      if (arguments.isEmpty || arguments.length > 2) {
        throw const FormatException(
          'vibrate() expects strength and optional duration.',
        );
      }
      return LovenseMockRuleCommand.vibrate(
        strength: _parseNumberExpression(arguments[0]),
        durationMs: arguments.length == 2
            ? _parseNumberExpression(arguments[1])
            : null,
      );
    }

    throw FormatException('Unsupported command "$commandName".');
  }

  static LovenseMockNumberExpression _parseNumberExpression(String source) {
    final String trimmed = source.trim();
    final num? literal = num.tryParse(trimmed);
    if (literal != null) {
      return LovenseMockNumberExpression.literal(literal);
    }
    final RegExp functionPattern = RegExp(r'^([A-Za-z][A-Za-z0-9_]*)\((.*)\)$');
    final RegExpMatch? functionMatch = functionPattern.firstMatch(trimmed);
    if (functionMatch != null) {
      final String functionName = functionMatch.group(1)!.toLowerCase();
      if (!_supportedFunctions.contains(functionName)) {
        throw FormatException('Unsupported function "$functionName".');
      }
      final List<String> functionArgs = _splitTopLevelArguments(
        functionMatch.group(2)!,
      );
      if (functionName == 'burstcount') {
        if (functionArgs.length != 1) {
          throw const FormatException(
            'burstcount(maxGapMs) expects exactly one argument.',
          );
        }
        final int? maxGapMs = int.tryParse(functionArgs.first);
        if (maxGapMs == null || maxGapMs < 0) {
          throw const FormatException(
            'burstcount(maxGapMs) expects maxGapMs >= 0.',
          );
        }
        return LovenseMockNumberExpression.function(
          functionName: functionName,
          functionArg1: maxGapMs,
        );
      }
      if (functionArgs.length != 2) {
        throw FormatException(
          '$functionName(maxGapMs, maxTriggers) expects exactly two arguments.',
        );
      }
      final int? arg1 = int.tryParse(functionArgs[0]);
      final int? arg2 = int.tryParse(functionArgs[1]);
      if (arg1 == null || arg2 == null) {
        throw FormatException('Invalid function arguments in "$source".');
      }
      if (arg1 < 0 || arg2 < 2) {
        throw FormatException(
          '$functionName(maxGapMs, maxTriggers) expects maxGapMs >= 0 and maxTriggers >= 2.',
        );
      }
      return LovenseMockNumberExpression.function(
        functionName: functionName,
        functionArg1: arg1,
        functionArg2: arg2,
      );
    }
    if (RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(trimmed)) {
      final String variableName = trimmed.toLowerCase();
      if (!_supportedVariables.contains(variableName)) {
        throw FormatException('Unsupported variable "$source".');
      }
      return LovenseMockNumberExpression.variable(variableName);
    }
    throw FormatException('Invalid number expression "$source".');
  }

  static List<String> _splitTopLevelArguments(String source) {
    final String trimmed = source.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    final List<String> arguments = <String>[];
    final StringBuffer current = StringBuffer();
    int depth = 0;
    for (int i = 0; i < trimmed.length; i += 1) {
      final String char = trimmed[i];
      if (char == '(') {
        depth += 1;
        current.write(char);
        continue;
      }
      if (char == ')') {
        depth = math.max(0, depth - 1);
        current.write(char);
        continue;
      }
      if (char == ',' && depth == 0) {
        final String value = current.toString().trim();
        if (value.isNotEmpty) {
          arguments.add(value);
        }
        current.clear();
        continue;
      }
      current.write(char);
    }
    final String trailing = current.toString().trim();
    if (trailing.isNotEmpty) {
      arguments.add(trailing);
    }
    return arguments;
  }
}

class LovenseMockClient {
  LovenseMockClient({required this.devices, String? rulesText})
    : ruleScript = LovenseMockRuleScript.parse(
        rulesText ?? LovenseMockRuleScript.defaultSource,
      );

  factory LovenseMockClient.demo({String? rulesText}) {
    return LovenseMockClient(
      rulesText: rulesText,
      devices: const <LovenseMockDevice>[
        LovenseMockDevice(
          id: 'mock-nora',
          name: 'Nora Simulator',
          capabilities: <String>{'vibrate'},
        ),
        LovenseMockDevice(
          id: 'mock-edge',
          name: 'Edge Simulator',
          capabilities: <String>{'vibrate'},
        ),
        LovenseMockDevice(
          id: 'mock-hush',
          name: 'Hush Simulator',
          capabilities: <String>{},
        ),
      ],
    );
  }

  static const int defaultVibrateThreshold = 15;
  static const int defaultVibrateStrength = 10;
  static const int defaultVibrateDurationMs = 800;

  final List<LovenseMockDevice> devices;
  final List<LovenseMockCommand> history = <LovenseMockCommand>[];
  LovenseMockRuleScript ruleScript;

  LovenseMockCommand? get lastCommand => history.isEmpty ? null : history.first;

  String get rulesText => ruleScript.source;

  String? get ruleError => ruleScript.error;

  bool get hasActiveOutput {
    if (history.isEmpty || devices.isEmpty) {
      return false;
    }
    final Set<String> seenDevices = <String>{};
    for (final LovenseMockCommand command in history) {
      if (!seenDevices.add(command.device.id)) {
        continue;
      }
      if (command.action != LovenseMockCommandAction.stop) {
        return true;
      }
      if (seenDevices.length >= devices.length) {
        break;
      }
    }
    return false;
  }

  void updateRules(String rulesText) {
    ruleScript = LovenseMockRuleScript.parse(rulesText);
  }

  List<LovenseMockEvaluationResult> evaluateAction(
    LovenseActionContext context,
  ) {
    if (devices.isEmpty) {
      return const <LovenseMockEvaluationResult>[
        LovenseMockEvaluationResult(
          status: LovenseMockEvaluationStatus.noDevicesConfigured,
          message: 'No simulated devices configured.',
        ),
      ];
    }

    if (!ruleScript.isValid) {
      return <LovenseMockEvaluationResult>[
        for (final LovenseMockDevice device in devices)
          LovenseMockEvaluationResult(
            status: LovenseMockEvaluationStatus.ruleInvalid,
            device: device,
            message: ruleScript.error ?? 'Rule script invalid.',
          ),
      ];
    }

    final List<LovenseMockEvaluationResult> results =
        <LovenseMockEvaluationResult>[];
    for (final LovenseMockDevice device in devices) {
      final LovenseMockCommand? command = ruleScript.evaluate(context, device);
      if (command == null) {
        results.add(
          LovenseMockEvaluationResult(
            status: LovenseMockEvaluationStatus.noMatchingRule,
            device: device,
            message: 'No rule branch matched.',
          ),
        );
        continue;
      }

      _recordCommand(command);
      results.add(
        LovenseMockEvaluationResult(
          status: LovenseMockEvaluationStatus.commandGenerated,
          device: device,
          command: command,
          message: 'Command generated.',
        ),
      );
    }
    return results;
  }

  List<LovenseMockCommand> sendForAction(LovenseActionContext context) {
    final List<LovenseMockEvaluationResult> results = evaluateAction(context);
    return <LovenseMockCommand>[
      for (final LovenseMockEvaluationResult result in results)
        if (result.command != null) result.command!,
    ];
  }

  List<LovenseMockCommand> stopAllDevices(LovenseActionContext context) {
    if (devices.isEmpty) {
      return const <LovenseMockCommand>[];
    }

    final List<LovenseMockCommand> commands = <LovenseMockCommand>[
      for (final LovenseMockDevice device in devices)
        LovenseMockCommand(
          device: device,
          action: LovenseMockCommandAction.stop,
          context: context,
        ),
    ];
    for (final LovenseMockCommand command in commands) {
      _recordCommand(command);
    }
    return commands;
  }

  LovenseMockCommand? stopAll(LovenseActionContext context) {
    final List<LovenseMockCommand> commands = stopAllDevices(context);
    return commands.isEmpty ? null : commands.first;
  }

  void clear() {
    history.clear();
  }

  void _recordCommand(LovenseMockCommand command) {
    history.insert(0, command);
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
  }
}

int _clampInt(num? value, int min, int max) {
  final num safeValue = value ?? min;
  return safeValue.round().clamp(min, max).toInt();
}
