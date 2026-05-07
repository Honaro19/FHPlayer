import 'package:flutter_test/flutter_test.dart';

import 'package:fhplayer_flutter/lovense_mock.dart';

void main() {
  group('LovenseMockClient', () {
    test('creates a vibrate command for positions at or above threshold', () {
      final LovenseMockClient client = LovenseMockClient.demo();

      final List<LovenseMockCommand> commands = client.sendForAction(
        const LovenseActionContext(
          index: 1,
          atMs: 750,
          pos: 90,
          currentMs: 760,
          deltaMs: 10,
        ),
      );

      expect(commands, hasLength(3));
      expect(
        commands.map((LovenseMockCommand command) => command.device.id),
        <String>['mock-nora', 'mock-edge', 'mock-hush'],
      );
      expect(commands[0].action, LovenseMockCommandAction.vibrate);
      expect(
        commands[0].strength,
        LovenseMockClient.defaultVibrateStrength,
      );
      expect(
        commands[0].durationMs,
        LovenseMockClient.defaultVibrateDurationMs,
      );
      expect(commands[1].action, LovenseMockCommandAction.vibrate);
      expect(commands[2].action, LovenseMockCommandAction.stop);
      expect(client.lastCommand, same(commands.last));
    });

    test('creates a stop command below the default threshold', () {
      final LovenseMockClient client = LovenseMockClient.demo();

      final List<LovenseMockCommand> commands = client.sendForAction(
        const LovenseActionContext(
          index: 0,
          atMs: 0,
          pos: 10,
          currentMs: 0,
          deltaMs: 0,
        ),
      );

      expect(commands, hasLength(3));
      expect(
        commands.every(
          (LovenseMockCommand command) =>
              command.action == LovenseMockCommandAction.stop,
        ),
        isTrue,
      );
      expect(commands.first.commandText, 'Stop');
      expect(commands.first.toPayload(), <String, Object>{
        'toy': 'mock-nora',
        'command': 'Stop',
        'stopPrevious': true,
      });
    });

    test('clear removes command history', () {
      final LovenseMockClient client = LovenseMockClient.demo();
      client.sendForAction(
        const LovenseActionContext(
          index: 2,
          atMs: 1500,
          pos: 20,
          currentMs: 1504,
          deltaMs: 4,
        ),
      );

      expect(client.history, isNotEmpty);

      client.clear();

      expect(client.history, isEmpty);
      expect(client.lastCommand, isNull);
    });

    test('uses editable rule script values', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText: 'if pos >= 50 then vibrate(7, 1200)\nelse stop()',
      );

      final List<LovenseMockCommand> commands = client.sendForAction(
        const LovenseActionContext(
          index: 3,
          atMs: 2500,
          pos: 80,
          currentMs: 2504,
          deltaMs: 4,
        ),
      );

      expect(client.ruleError, isNull);
      expect(commands, hasLength(3));
      expect(commands[0].action, LovenseMockCommandAction.vibrate);
      expect(commands[0].strength, 7);
      expect(commands[0].durationMs, 1200);
      expect(commands[1].action, LovenseMockCommandAction.vibrate);
      expect(commands[2].action, LovenseMockCommandAction.stop);
      expect(commands.first.toPayload(), <String, Object>{
        'toy': 'mock-nora',
        'command': 'Vibrate:7',
        'stopPrevious': true,
        'durationMs': 1200,
      });
    });

    test('invalid rule script suppresses commands', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText: 'if pos >= 15 vibrate(10)',
      );

      final List<LovenseMockCommand> commands = client.sendForAction(
        const LovenseActionContext(
          index: 1,
          atMs: 750,
          pos: 90,
          currentMs: 760,
          deltaMs: 10,
        ),
      );

      expect(client.ruleError, isNotNull);
      expect(commands, isEmpty);
      expect(client.history, isEmpty);
    });

    test('invalid variables are rejected', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText: 'if poss >= 15 then vibrate(10)',
      );

      expect(client.ruleError, contains('Unsupported variable'));
    });

    test('evaluateAction reports rule errors per device', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText: 'if pos > then stop()',
      );

      final List<LovenseMockEvaluationResult> results = client.evaluateAction(
        const LovenseActionContext(
          index: 5,
          atMs: 3200,
          pos: 70,
          currentMs: 3210,
          deltaMs: 10,
        ),
      );

      expect(results, hasLength(3));
      expect(
        results.every(
          (LovenseMockEvaluationResult result) =>
              result.status == LovenseMockEvaluationStatus.ruleInvalid &&
              !result.hasCommand,
        ),
        isTrue,
      );
      expect(client.history, isEmpty);
    });

    test('evaluateAction reports missing device configuration', () {
      final LovenseMockClient client = LovenseMockClient(
        rulesText: 'else stop()',
        devices: const <LovenseMockDevice>[],
      );

      final List<LovenseMockEvaluationResult> results = client.evaluateAction(
        const LovenseActionContext(
          index: 0,
          atMs: 0,
          pos: 10,
          currentMs: 0,
          deltaMs: 0,
        ),
      );

      expect(results, hasLength(1));
      expect(
        results.single.status,
        LovenseMockEvaluationStatus.noDevicesConfigured,
      );
      expect(results.single.message, contains('No simulated devices'));
      expect(client.history, isEmpty);
    });
  });
}
