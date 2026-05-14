import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fhplayer_flutter/lovense_mock.dart';

class LovenseLiveConnectionConfig {
  const LovenseLiveConnectionConfig({
    required this.scheme,
    required this.host,
    required this.port,
    required this.platformName,
    this.timeoutSeconds = 5,
  });

  final String scheme;
  final String host;
  final int port;
  final String platformName;
  final int timeoutSeconds;

  Uri get commandUri => Uri(
    scheme: scheme.trim().toLowerCase(),
    host: host.trim(),
    port: port,
    path: '/command',
  );
}

class LovenseLiveDevice {
  const LovenseLiveDevice({
    required this.id,
    required this.name,
    required this.nickName,
    required this.type,
    required this.fullFunctionNames,
    required this.shortFunctionNames,
  });

  final String id;
  final String name;
  final String nickName;
  final String type;
  final List<String> fullFunctionNames;
  final List<String> shortFunctionNames;

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }
    if (nickName.trim().isNotEmpty) {
      return nickName.trim();
    }
    return id;
  }

  Set<String> get ruleCapabilities {
    return inferLovenseRuleCapabilities(this);
  }
}

class LovenseRuleCatalogEntry {
  const LovenseRuleCatalogEntry({
    required this.key,
    required this.aliases,
    required this.requiredCapabilities,
    required this.parameterRanges,
    required this.allowDuration,
    required this.buildAction,
  });

  final String key;
  final Set<String> aliases;
  final Set<String> requiredCapabilities;
  final List<({int min, int max, String label})> parameterRanges;
  final bool allowDuration;
  final String Function(List<int> params) buildAction;
}

class LovenseLiveRuleIssue {
  const LovenseLiveRuleIssue(this.message, {this.lineNumber});

  final String message;
  final int? lineNumber;

  @override
  String toString() =>
      lineNumber == null ? message : 'Line $lineNumber: $message';
}

class LovenseLiveDispatchCommand {
  const LovenseLiveDispatchCommand({
    required this.delayMs,
    required this.command,
    required this.durationMs,
  });

  final int delayMs;
  final LovenseLiveCommand command;
  final int durationMs;
}

class LovenseLiveRuleEvaluation {
  const LovenseLiveRuleEvaluation({
    required this.commands,
    required this.issues,
  });

  final List<LovenseLiveDispatchCommand> commands;
  final List<LovenseLiveRuleIssue> issues;

  bool get hasErrors => issues.isNotEmpty;
}

class LovenseLiveRuleEngine {
  const LovenseLiveRuleEngine();

  LovenseLiveRuleEvaluation evaluate({
    required String rulesText,
    required LovenseActionContext context,
    required List<LovenseLiveDevice> selectedDevices,
  }) {
    final List<LovenseLiveRuleIssue> issues = <LovenseLiveRuleIssue>[];
    final List<_RuleBranch> branches = _parseBranches(
      rulesText,
      issues: issues,
    );
    if (issues.isNotEmpty) {
      return LovenseLiveRuleEvaluation(commands: const [], issues: issues);
    }

    final _RuleBranch matched = branches.firstWhere(
      (_RuleBranch branch) =>
          branch.condition == null || branch.condition!.matches(context),
      orElse: () => _RuleBranch(
        lineNumber: -1,
        condition: null,
        commands: const <_ParsedRuleCommand>[],
      ),
    );
    if (matched.lineNumber == -1) {
      return LovenseLiveRuleEvaluation(
        commands: const [],
        issues: const <LovenseLiveRuleIssue>[],
      );
    }

    final List<LovenseLiveDispatchCommand> commands =
        <LovenseLiveDispatchCommand>[];
    int delayMs = 0;
    int commandIndex = 0;
    for (final _ParsedRuleCommand parsedCommand in matched.commands) {
      if (parsedCommand.actionKey == 'delay') {
        delayMs += parsedCommand.parameters.first;
        continue;
      }

      final LovenseRuleCatalogEntry? entry =
          _ruleCatalog[parsedCommand.actionKey];
      if (entry == null) {
        issues.add(
          LovenseLiveRuleIssue(
            'Unsupported command "${parsedCommand.actionKey}".',
            lineNumber: parsedCommand.lineNumber,
          ),
        );
        continue;
      }

      final List<LovenseLiveDevice> supportedDevices = selectedDevices.where((
        LovenseLiveDevice device,
      ) {
        return entry.requiredCapabilities.every(
          device.ruleCapabilities.contains,
        );
      }).toList();
      if (supportedDevices.isEmpty) {
        issues.add(
          LovenseLiveRuleIssue(
            'No selected device supports "${entry.key}".',
            lineNumber: parsedCommand.lineNumber,
          ),
        );
        continue;
      }

      final List<int> actionParameters = parsedCommand.parameters
          .take(entry.parameterRanges.length)
          .toList();
      final String actionText = entry.buildAction(actionParameters);
      final int durationMs = parsedCommand.durationMs;
      final int timeSec = durationMs <= 0
          ? 0
          : mathMax(1, (durationMs / 1000).ceil());

      for (final LovenseLiveDevice device in supportedDevices) {
        commands.add(
          LovenseLiveDispatchCommand(
            delayMs: delayMs,
            durationMs: durationMs,
            command: LovenseLiveCommand.function(
              action: actionText,
              toy: device.id,
              stopPrevious: commandIndex == 0,
              timeSec: timeSec,
            ),
          ),
        );
        commandIndex += 1;
      }
    }

    return LovenseLiveRuleEvaluation(commands: commands, issues: issues);
  }

  List<LovenseLiveRuleIssue> validate({
    required String rulesText,
    required List<LovenseLiveDevice> selectedDevices,
  }) {
    final LovenseActionContext probe = const LovenseActionContext(
      index: 0,
      atMs: 0,
      pos: 15,
      currentMs: 0,
      deltaMs: 0,
    );
    return evaluate(
      rulesText: rulesText,
      context: probe,
      selectedDevices: selectedDevices,
    ).issues;
  }

  List<_RuleBranch> _parseBranches(
    String rulesText, {
    required List<LovenseLiveRuleIssue> issues,
  }) {
    final List<_RuleBranch> branches = <_RuleBranch>[];
    final List<String> lines = rulesText.split(RegExp(r'\r?\n'));
    for (int index = 0; index < lines.length; index += 1) {
      final int lineNumber = index + 1;
      final String line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }

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

      if (ifMatch != null) {
        branches.add(
          _RuleBranch(
            lineNumber: lineNumber,
            condition: _RuleCondition.parse(
              ifMatch.group(1)!,
              lineNumber: lineNumber,
              issues: issues,
            ),
            commands: _parseCommandList(
              ifMatch.group(2)!,
              lineNumber: lineNumber,
              issues: issues,
            ),
          ),
        );
        continue;
      }

      if (elseIfMatch != null) {
        branches.add(
          _RuleBranch(
            lineNumber: lineNumber,
            condition: _RuleCondition.parse(
              elseIfMatch.group(1)!,
              lineNumber: lineNumber,
              issues: issues,
            ),
            commands: _parseCommandList(
              elseIfMatch.group(2)!,
              lineNumber: lineNumber,
              issues: issues,
            ),
          ),
        );
        continue;
      }

      if (elseMatch != null) {
        branches.add(
          _RuleBranch(
            lineNumber: lineNumber,
            condition: null,
            commands: _parseCommandList(
              elseMatch.group(1)!,
              lineNumber: lineNumber,
              issues: issues,
            ),
          ),
        );
        continue;
      }

      issues.add(
        LovenseLiveRuleIssue(
          'Use "if ... then ...", "else if ... then ...", or "else ...".',
          lineNumber: lineNumber,
        ),
      );
    }

    if (branches.isEmpty) {
      issues.add(const LovenseLiveRuleIssue('Rule script is empty.'));
    }
    return branches;
  }

  List<_ParsedRuleCommand> _parseCommandList(
    String source, {
    required int lineNumber,
    required List<LovenseLiveRuleIssue> issues,
  }) {
    final List<_ParsedRuleCommand> commands = <_ParsedRuleCommand>[];
    for (final String rawPart in source.split('+')) {
      final String part = rawPart.trim();
      if (part.isEmpty) {
        continue;
      }
      final RegExp pattern = RegExp(r'^([A-Za-z][A-Za-z0-9_]*)\s*\((.*)\)\s*$');
      final RegExpMatch? match = pattern.firstMatch(part);
      if (match == null) {
        issues.add(
          LovenseLiveRuleIssue(
            'Invalid command "$part".',
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      final String actionName = match.group(1)!.toLowerCase();
      final String actionKey = _resolveActionKey(actionName);
      if (actionKey.isEmpty) {
        issues.add(
          LovenseLiveRuleIssue(
            'Unsupported command "$actionName".',
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      final List<String> rawArguments = match
          .group(2)!
          .split(',')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList();

      if (actionKey == 'stop') {
        if (rawArguments.isNotEmpty) {
          issues.add(
            LovenseLiveRuleIssue(
              'stop() does not accept arguments.',
              lineNumber: lineNumber,
            ),
          );
        }
        commands.add(
          _ParsedRuleCommand(
            actionKey: actionKey,
            parameters: const <int>[],
            durationMs: 0,
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      if (actionKey == 'delay') {
        if (rawArguments.length != 1) {
          issues.add(
            LovenseLiveRuleIssue(
              'delay(ms) expects exactly one argument.',
              lineNumber: lineNumber,
            ),
          );
          continue;
        }
        final int? delayMs = _parseIntArg(rawArguments.first);
        if (delayMs == null || delayMs < 0) {
          issues.add(
            LovenseLiveRuleIssue(
              'delay(ms) expects a value >= 0.',
              lineNumber: lineNumber,
            ),
          );
          continue;
        }
        commands.add(
          _ParsedRuleCommand(
            actionKey: actionKey,
            parameters: <int>[delayMs],
            durationMs: 0,
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      final LovenseRuleCatalogEntry entry = _ruleCatalog[actionKey]!;
      final int expectedArgsMin = entry.parameterRanges.length;
      final int expectedArgsMax = entry.allowDuration
          ? entry.parameterRanges.length + 1
          : entry.parameterRanges.length;
      if (rawArguments.length < expectedArgsMin ||
          rawArguments.length > expectedArgsMax) {
        issues.add(
          LovenseLiveRuleIssue(
            '${entry.key} expects ${entry.parameterRanges.length}'
            '${entry.allowDuration ? ' or ${entry.parameterRanges.length + 1}' : ''} argument(s).',
            lineNumber: lineNumber,
          ),
        );
        continue;
      }

      final List<int> parameters = <int>[];
      bool hasArgError = false;
      for (
        int argIndex = 0;
        argIndex < entry.parameterRanges.length;
        argIndex += 1
      ) {
        final int? value = _parseIntArg(rawArguments[argIndex]);
        final ({int min, int max, String label}) range =
            entry.parameterRanges[argIndex];
        if (value == null || value < range.min || value > range.max) {
          issues.add(
            LovenseLiveRuleIssue(
              '${entry.key} ${range.label} must be ${range.min}-${range.max}.',
              lineNumber: lineNumber,
            ),
          );
          hasArgError = true;
          break;
        }
        parameters.add(value);
      }
      if (hasArgError) {
        continue;
      }

      int durationMs = 0;
      if (rawArguments.length > entry.parameterRanges.length) {
        final int? parsedDuration = _parseIntArg(rawArguments.last);
        if (parsedDuration == null || parsedDuration < 0) {
          issues.add(
            LovenseLiveRuleIssue(
              'Duration must be >= 0.',
              lineNumber: lineNumber,
            ),
          );
          continue;
        }
        if (parsedDuration > 0 && parsedDuration < 200) {
          issues.add(
            LovenseLiveRuleIssue(
              'Duration must be 0 or >= 200 ms.',
              lineNumber: lineNumber,
            ),
          );
          continue;
        }
        durationMs = parsedDuration;
      }

      commands.add(
        _ParsedRuleCommand(
          actionKey: actionKey,
          parameters: parameters,
          durationMs: durationMs,
          lineNumber: lineNumber,
        ),
      );
    }
    return commands;
  }

  static int? _parseIntArg(String source) {
    final num? numeric = num.tryParse(source);
    if (numeric == null) {
      return null;
    }
    return numeric.round();
  }

  static String _resolveActionKey(String source) {
    final String normalized = source.trim().toLowerCase();
    for (final LovenseRuleCatalogEntry entry in _ruleCatalog.values) {
      if (entry.aliases.contains(normalized)) {
        return entry.key;
      }
    }
    return '';
  }
}

class _RuleBranch {
  const _RuleBranch({
    required this.lineNumber,
    required this.condition,
    required this.commands,
  });

  final int lineNumber;
  final _RuleCondition? condition;
  final List<_ParsedRuleCommand> commands;
}

class _ParsedRuleCommand {
  const _ParsedRuleCommand({
    required this.actionKey,
    required this.parameters,
    required this.durationMs,
    required this.lineNumber,
  });

  final String actionKey;
  final List<int> parameters;
  final int durationMs;
  final int lineNumber;
}

class _RuleCondition {
  const _RuleCondition({
    required this.leftVariable,
    required this.operator,
    required this.rightLiteral,
    required this.rightVariable,
  });

  final String leftVariable;
  final String operator;
  final num rightLiteral;
  final String? rightVariable;

  bool matches(LovenseActionContext context) {
    final num left = _contextValue(context, leftVariable);
    final num right = rightVariable == null
        ? rightLiteral
        : _contextValue(context, rightVariable!);
    return switch (operator) {
      '>' => left > right,
      '>=' => left >= right,
      '<' => left < right,
      '<=' => left <= right,
      '==' => left == right,
      '!=' => left != right,
      _ => false,
    };
  }

  static _RuleCondition parse(
    String source, {
    required int lineNumber,
    required List<LovenseLiveRuleIssue> issues,
  }) {
    final RegExp pattern = RegExp(
      r'^\s*([A-Za-z][A-Za-z0-9]*)\s*(>=|<=|==|!=|>|<)\s*(-?\d+(?:\.\d+)?|[A-Za-z][A-Za-z0-9]*)\s*$',
    );
    final RegExpMatch? match = pattern.firstMatch(source);
    if (match == null) {
      issues.add(
        LovenseLiveRuleIssue(
          'Invalid condition "$source".',
          lineNumber: lineNumber,
        ),
      );
      return const _RuleCondition(
        leftVariable: 'pos',
        operator: '>=',
        rightLiteral: 0,
        rightVariable: null,
      );
    }

    final String left = match.group(1)!.toLowerCase();
    final String operator = match.group(2)!;
    final String rightRaw = match.group(3)!.toLowerCase();
    if (!_conditionVariables.contains(left)) {
      issues.add(
        LovenseLiveRuleIssue(
          'Unsupported variable "$left".',
          lineNumber: lineNumber,
        ),
      );
    }

    final num? rightNumeric = num.tryParse(rightRaw);
    final bool usesRightVariable = rightNumeric == null;
    if (usesRightVariable && !_conditionVariables.contains(rightRaw)) {
      issues.add(
        LovenseLiveRuleIssue(
          'Unsupported variable "$rightRaw".',
          lineNumber: lineNumber,
        ),
      );
    }
    return _RuleCondition(
      leftVariable: left,
      operator: operator,
      rightLiteral: rightNumeric ?? 0,
      rightVariable: usesRightVariable ? rightRaw : null,
    );
  }

  static num _contextValue(LovenseActionContext context, String variable) {
    return switch (variable) {
      'pos' || 'level' => context.pos,
      'index' => context.index,
      'at' || 'time' => context.atMs,
      'current' || 'currentms' => context.currentMs,
      'delta' || 'deltams' => context.deltaMs,
      _ => 0,
    };
  }
}

class LovenseLiveCommand {
  const LovenseLiveCommand({
    required this.command,
    required this.action,
    required this.toy,
    required this.apiVer,
    required this.stopPrevious,
    required this.timeSec,
  });

  final String command;
  final String action;
  final String toy;
  final int apiVer;
  final int stopPrevious;
  final int timeSec;

  factory LovenseLiveCommand.function({
    required String action,
    required String toy,
    required bool stopPrevious,
    required int timeSec,
  }) {
    return LovenseLiveCommand(
      command: 'Function',
      action: action,
      toy: toy,
      apiVer: 1,
      stopPrevious: stopPrevious ? 1 : 0,
      timeSec: timeSec,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'command': command,
      'action': action,
      'toy': toy,
      'apiVer': apiVer,
      'stopPrevious': stopPrevious,
      'timeSec': timeSec,
    };
  }
}

class LovenseLiveDetectResult {
  const LovenseLiveDetectResult({
    required this.devices,
    required this.rawPayload,
  });

  final List<LovenseLiveDevice> devices;
  final Map<String, dynamic> rawPayload;
}

class LovenseLiveResponse {
  const LovenseLiveResponse({required this.rawPayload});

  final Map<String, dynamic> rawPayload;
}

class LovenseLiveClient {
  Future<LovenseLiveDetectResult> detectDevices(
    LovenseLiveConnectionConfig config,
  ) async {
    final Map<String, dynamic> payload = await _postCommand(
      config: config,
      payload: const <String, Object>{'command': 'GetToys'},
    );
    return LovenseLiveDetectResult(
      devices: _parseDevices(payload),
      rawPayload: payload,
    );
  }

  Future<LovenseLiveResponse> sendCommands({
    required LovenseLiveConnectionConfig config,
    required List<LovenseLiveCommand> commands,
  }) async {
    if (commands.isEmpty) {
      return const LovenseLiveResponse(rawPayload: <String, dynamic>{});
    }

    final List<Map<String, Object>> results = <Map<String, Object>>[];
    for (final LovenseLiveCommand command in commands) {
      final Map<String, dynamic> payload = await _postCommand(
        config: config,
        payload: command.toJson(),
      );
      results.add(<String, Object>{
        'command': command.toJson(),
        'response': payload,
      });
    }
    return LovenseLiveResponse(
      rawPayload: <String, dynamic>{'results': results},
    );
  }

  Future<LovenseLiveResponse> stopDevices({
    required LovenseLiveConnectionConfig config,
    required List<String> toyIds,
  }) {
    final List<LovenseLiveCommand> commands = <LovenseLiveCommand>[
      for (int index = 0; index < toyIds.length; index += 1)
        LovenseLiveCommand.function(
          action: 'Stop',
          toy: toyIds[index],
          stopPrevious: index == 0,
          timeSec: 0,
        ),
    ];
    return sendCommands(config: config, commands: commands);
  }

  Future<Map<String, dynamic>> _postCommand({
    required LovenseLiveConnectionConfig config,
    required Map<String, Object> payload,
  }) async {
    final Uri uri = config.commandUri;
    final HttpClient client = HttpClient();
    client.connectionTimeout = Duration(seconds: config.timeoutSeconds);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          if (uri.scheme != 'https') {
            return false;
          }
          if (host != uri.host) {
            return false;
          }
          return _isLocalHost(host);
        };

    try {
      final HttpClientRequest request = await client
          .postUrl(uri)
          .timeout(Duration(seconds: config.timeoutSeconds));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('X-platform', config.platformName);
      request.write(jsonEncode(payload));
      final HttpClientResponse response = await request.close().timeout(
        Duration(seconds: config.timeoutSeconds),
      );
      final String responseText = await utf8.decodeStream(response);
      if (response.statusCode >= 400) {
        throw LovenseLiveException(
          'Lovense request failed with HTTP ${response.statusCode}.',
        );
      }
      if (responseText.trim().isEmpty) {
        return const <String, dynamic>{};
      }
      final Object? decoded = jsonDecode(responseText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'data': decoded};
    } on TimeoutException {
      throw LovenseLiveException('Lovense request timed out.');
    } on SocketException catch (error) {
      throw LovenseLiveException('Connection failed: ${error.message}');
    } on FormatException catch (error) {
      throw LovenseLiveException('Invalid Lovense response: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  List<LovenseLiveDevice> _parseDevices(Map<String, dynamic> payload) {
    final Object? dataRaw = payload['data'];
    final Map<String, dynamic> data = dataRaw is Map<String, dynamic>
        ? dataRaw
        : const <String, dynamic>{};

    Object? toysRaw = data['toys'];
    if (toysRaw is String && toysRaw.trim().isNotEmpty) {
      final Object? decoded = jsonDecode(toysRaw);
      toysRaw = decoded;
    }
    final Map<String, dynamic> toys = toysRaw is Map<String, dynamic>
        ? toysRaw
        : const <String, dynamic>{};

    final List<LovenseLiveDevice> devices = <LovenseLiveDevice>[];
    for (final MapEntry<String, dynamic> entry in toys.entries) {
      final Map<String, dynamic> toy = entry.value is Map<String, dynamic>
          ? entry.value as Map<String, dynamic>
          : const <String, dynamic>{};
      final String id = _firstNonEmpty(_toStringOrEmpty(toy['id']), entry.key);
      if (id.isEmpty) {
        continue;
      }
      devices.add(
        LovenseLiveDevice(
          id: id,
          name: _toStringOrEmpty(toy['name']),
          nickName: _toStringOrEmpty(toy['nickName']),
          type: _firstNonEmpty(
            _toStringOrEmpty(toy['type']),
            _toStringOrEmpty(toy['toyType']),
            _toStringOrEmpty(toy['name']),
            _toStringOrEmpty(toy['nickName']),
          ),
          fullFunctionNames: _toStringList(toy['fullFunctionNames']),
          shortFunctionNames: _toStringList(toy['shortFunctionNames']),
        ),
      );
    }
    return devices;
  }

  static String _firstNonEmpty(
    String first,
    String second, [
    String third = '',
    String fourth = '',
  ]) {
    for (final String candidate in <String>[first, second, third, fourth]) {
      final String value = candidate.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _toStringOrEmpty(Object? value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  static List<String> _toStringList(Object? value) {
    if (value is List<Object?>) {
      return value
          .map((Object? item) => item?.toString().trim() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const <String>[];
      }
      try {
        final Object? decoded = jsonDecode(trimmed);
        if (decoded is List<Object?>) {
          return decoded
              .map((Object? item) => item?.toString().trim() ?? '')
              .where((String item) => item.isNotEmpty)
              .toList();
        }
      } on FormatException {
        return <String>[trimmed];
      }
    }
    return const <String>[];
  }

  static bool _isLocalHost(String host) {
    final String normalized = host.trim().toLowerCase();
    if (normalized == 'localhost') {
      return true;
    }
    final InternetAddress? address = InternetAddress.tryParse(normalized);
    if (address == null) {
      return false;
    }
    if (address.isLoopback || address.isLinkLocal) {
      return true;
    }
    if (address.type == InternetAddressType.IPv4) {
      final List<int> octets = address.rawAddress;
      if (octets.length == 4) {
        if (octets[0] == 10) {
          return true;
        }
        if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) {
          return true;
        }
        if (octets[0] == 192 && octets[1] == 168) {
          return true;
        }
      }
    }
    return false;
  }
}

const Set<String> _conditionVariables = <String>{
  'pos',
  'level',
  'index',
  'at',
  'time',
  'current',
  'currentms',
  'delta',
  'deltams',
};

const Map<String, String> _shortCapabilityMap = <String, String>{
  'v': 'vibrate',
  'v2': 'vibrate',
  'r': 'rotate',
  'a': 'air',
  'p': 'pump',
  'sl': 'setlevel',
  't': 'thrusting',
  'f': 'fingering',
  's': 'suction',
  'd': 'depth',
  'o': 'oscillate',
};

final List<({RegExp pattern, Set<String> capabilities})> _typeCapabilityHints =
    <({RegExp pattern, Set<String> capabilities})>[
      (
        pattern: RegExp(r'solace\s*pro', caseSensitive: false),
        capabilities: <String>{'thrusting', 'stroke'},
      ),
      (
        pattern: RegExp(r'solace', caseSensitive: false),
        capabilities: <String>{'thrusting', 'depth'},
      ),
      (
        pattern: RegExp(r'\bmax(?:\s*2)?\b', caseSensitive: false),
        capabilities: <String>{'pump', 'air'},
      ),
      (
        pattern: RegExp(r'\bnora\b', caseSensitive: false),
        capabilities: <String>{'vibrate', 'rotate'},
      ),
      (
        pattern: RegExp(r'\bedge(?:\s*2)?\b|\blapis\b', caseSensitive: false),
        capabilities: <String>{'vibrate', 'oscillate'},
      ),
      (
        pattern: RegExp(r'\bhush\b|\blush\b|\bferri\b', caseSensitive: false),
        capabilities: <String>{'vibrate'},
      ),
      (
        pattern: RegExp(r'\bdomi\b', caseSensitive: false),
        capabilities: <String>{'setlevel'},
      ),
      (
        pattern: RegExp(r'\bflexer\b', caseSensitive: false),
        capabilities: <String>{'fingering'},
      ),
      (
        pattern: RegExp(r'\btenera\b', caseSensitive: false),
        capabilities: <String>{'suction'},
      ),
      (
        pattern: RegExp(r'\bosci\b', caseSensitive: false),
        capabilities: <String>{'oscillate'},
      ),
    ];

final Map<String, LovenseRuleCatalogEntry> _ruleCatalog =
    <String, LovenseRuleCatalogEntry>{
      'delay': LovenseRuleCatalogEntry(
        key: 'delay',
        aliases: const <String>{'delay'},
        requiredCapabilities: const <String>{},
        parameterRanges: const <({int min, int max, String label})>[],
        allowDuration: false,
        buildAction: (_) => '',
      ),
      'stop': LovenseRuleCatalogEntry(
        key: 'stop',
        aliases: const <String>{'stop'},
        requiredCapabilities: const <String>{},
        parameterRanges: const <({int min, int max, String label})>[],
        allowDuration: false,
        buildAction: (_) => 'Stop',
      ),
      'vibrate': LovenseRuleCatalogEntry(
        key: 'vibrate',
        aliases: const <String>{'vibrate', 'vibration', 'all'},
        requiredCapabilities: const <String>{'vibrate'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 20, label: 'strength'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Vibrate:${params.first}',
      ),
      'rotate': LovenseRuleCatalogEntry(
        key: 'rotate',
        aliases: const <String>{'rotate', 'rotation'},
        requiredCapabilities: const <String>{'rotate'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 20, label: 'strength'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Rotate:${params.first}',
      ),
      'pump': LovenseRuleCatalogEntry(
        key: 'pump',
        aliases: const <String>{'pump'},
        requiredCapabilities: const <String>{'pump'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 3, label: 'level'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Pump:${params.first}',
      ),
      'thrusting': LovenseRuleCatalogEntry(
        key: 'thrusting',
        aliases: const <String>{'thrusting', 'thrust'},
        requiredCapabilities: const <String>{'thrusting'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 20, label: 'strength'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Thrusting:${params.first}',
      ),
      'fingering': LovenseRuleCatalogEntry(
        key: 'fingering',
        aliases: const <String>{'fingering', 'finger'},
        requiredCapabilities: const <String>{'fingering'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 20, label: 'strength'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Fingering:${params.first}',
      ),
      'suction': LovenseRuleCatalogEntry(
        key: 'suction',
        aliases: const <String>{'suction'},
        requiredCapabilities: const <String>{'suction'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 20, label: 'strength'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Suction:${params.first}',
      ),
      'depth': LovenseRuleCatalogEntry(
        key: 'depth',
        aliases: const <String>{'depth'},
        requiredCapabilities: const <String>{'depth'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 3, label: 'level'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Depth:${params.first}',
      ),
      'stroke': LovenseRuleCatalogEntry(
        key: 'stroke',
        aliases: const <String>{'stroke'},
        requiredCapabilities: const <String>{'stroke'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 100, label: 'value'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Stroke:${params.first}',
      ),
      'oscillate': LovenseRuleCatalogEntry(
        key: 'oscillate',
        aliases: const <String>{'oscillate', 'oscillation'},
        requiredCapabilities: const <String>{'oscillate'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 0, max: 20, label: 'strength'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'Oscillate:${params.first}',
      ),
      'setlevel': LovenseRuleCatalogEntry(
        key: 'setlevel',
        aliases: const <String>{'setlevel', 'set_level'},
        requiredCapabilities: const <String>{'setlevel'},
        parameterRanges: const <({int min, int max, String label})>[
          (min: 1, max: 3, label: 'button'),
          (min: 0, max: 20, label: 'level'),
        ],
        allowDuration: true,
        buildAction: (List<int> params) => 'SetLevel:${params[0]}:${params[1]}',
      ),
    };

Set<String> inferLovenseRuleCapabilities(LovenseLiveDevice device) {
  final Set<String> capabilities = <String>{};
  final Set<String> normalized = <String>{
    ...device.fullFunctionNames.map(
      (String value) => value.trim().toLowerCase(),
    ),
    ...device.shortFunctionNames.map(
      (String value) => value.trim().toLowerCase(),
    ),
  };

  for (final String function in normalized) {
    if (function.isEmpty) {
      continue;
    }
    if (_shortCapabilityMap.containsKey(function)) {
      capabilities.add(_shortCapabilityMap[function]!);
      continue;
    }
    final String compact = function.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (_shortCapabilityMap.containsKey(compact)) {
      capabilities.add(_shortCapabilityMap[compact]!);
      continue;
    }
    final String mapped = switch (compact) {
      'vibrate' || 'vibrate2' => 'vibrate',
      'rotate' || 'rotatechange' => 'rotate',
      'pump' => 'pump',
      'air' || 'airin' || 'airout' || 'airlevel' => 'air',
      'thrusting' => 'thrusting',
      'fingering' => 'fingering',
      'suction' => 'suction',
      'depth' => 'depth',
      'stroke' => 'stroke',
      'oscillate' => 'oscillate',
      'setlevel' => 'setlevel',
      _ => '',
    };
    if (mapped.isNotEmpty) {
      capabilities.add(mapped);
      if (mapped == 'air') {
        capabilities.add('pump');
      }
    }
  }

  final String typeText = '${device.type} ${device.name} ${device.nickName}'
      .toLowerCase();
  for (final ({RegExp pattern, Set<String> capabilities}) hint
      in _typeCapabilityHints) {
    if (hint.pattern.hasMatch(typeText)) {
      capabilities.addAll(hint.capabilities);
    }
  }
  return capabilities;
}

int mathMax(int left, int right) => left > right ? left : right;

class LovenseLiveException implements Exception {
  const LovenseLiveException(this.message);

  final String message;

  @override
  String toString() => message;
}
