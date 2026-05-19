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
      expect(commands[0].strength, LovenseMockClient.defaultVibrateStrength);
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

    test('supports multi-branch rules and context variables', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText:
            'if delta >= 20 then stop()\n'
            'else if pos >= 50 then vibrate(pos, current)\n'
            'else vibrate(index, delta)',
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

      expect(commands, hasLength(3));
      expect(commands[0].device.id, 'mock-nora');
      expect(commands[0].action, LovenseMockCommandAction.vibrate);
      expect(commands[0].strength, 20);
      expect(commands[0].durationMs, 2504);
      expect(commands[1].device.id, 'mock-edge');
      expect(commands[1].action, LovenseMockCommandAction.vibrate);
      expect(commands[2].device.id, 'mock-hush');
      expect(commands[2].action, LovenseMockCommandAction.stop);
    });

    test('supports trigger gap variable aliases', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText:
            'if gapms < 90 then stop()\n'
            'else if triggergapms < 140 then vibrate(6, 500)\n'
            'else vibrate(12, 500)',
      );

      final List<LovenseMockCommand> rapidCommands = client.sendForAction(
        const LovenseActionContext(
          index: 7,
          atMs: 3000,
          pos: 60,
          currentMs: 3003,
          deltaMs: 3,
          triggerGapMs: 80,
        ),
      );
      expect(rapidCommands.first.action, LovenseMockCommandAction.stop);

      final List<LovenseMockCommand> mediumCommands = client.sendForAction(
        const LovenseActionContext(
          index: 8,
          atMs: 3120,
          pos: 60,
          currentMs: 3124,
          deltaMs: 4,
          triggerGapMs: 120,
        ),
      );
      expect(mediumCommands.first.action, LovenseMockCommandAction.vibrate);
      expect(mediumCommands.first.strength, 6);

      final List<LovenseMockCommand> slowCommands = client.sendForAction(
        const LovenseActionContext(
          index: 9,
          atMs: 3400,
          pos: 60,
          currentMs: 3405,
          deltaMs: 5,
          triggerGapMs: 280,
        ),
      );
      expect(slowCommands.first.action, LovenseMockCommandAction.vibrate);
      expect(slowCommands.first.strength, 12);
    });

    test('supports burststart and burstduration functions', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText:
            'if burststart(90, 3) >= 1 then vibrate(10, burstduration(90, 3))\n'
            'else stop()',
      );

      final List<LovenseMockCommand> burstStartCommands = client.sendForAction(
        LovenseActionContext(
          index: 20,
          atMs: 4000,
          pos: 70,
          currentMs: 4002,
          deltaMs: 2,
          triggerGapMs: 40,
          burstStartResolver: (int maxGapMs, int minTriggers) => 1,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 260,
        ),
      );
      expect(burstStartCommands.first.action, LovenseMockCommandAction.vibrate);
      expect(burstStartCommands.first.durationMs, 260);

      final List<LovenseMockCommand> nonStartCommands = client.sendForAction(
        LovenseActionContext(
          index: 21,
          atMs: 4040,
          pos: 70,
          currentMs: 4044,
          deltaMs: 4,
          triggerGapMs: 40,
          burstStartResolver: (int maxGapMs, int minTriggers) => 0,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 0,
        ),
      );
      expect(nonStartCommands.first.action, LovenseMockCommandAction.stop);
    });

    test('supports burstmember and burstindex to guard follow-up triggers', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText:
            'if burststart(90, 3) >= 1 then vibrate(10, 900)\n'
            'else if burstmember(90, 3) >= 1 then stop()\n'
            'else if burstindex(90, 3) >= 1 then vibrate(4, 300)\n'
            'else vibrate(6, 300)',
      );

      final List<LovenseMockCommand> startCommands = client.sendForAction(
        LovenseActionContext(
          index: 30,
          atMs: 5000,
          pos: 65,
          currentMs: 5002,
          deltaMs: 2,
          triggerGapMs: 40,
          burstStartResolver: (int maxGapMs, int minTriggers) => 1,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 900,
          burstMemberResolver: (int maxGapMs, int minTriggers) => 1,
          burstIndexResolver: (int maxGapMs, int minTriggers) => 1,
        ),
      );
      expect(startCommands.first.action, LovenseMockCommandAction.vibrate);
      expect(startCommands.first.durationMs, 900);

      final List<LovenseMockCommand> memberCommands = client.sendForAction(
        LovenseActionContext(
          index: 31,
          atMs: 5045,
          pos: 65,
          currentMs: 5049,
          deltaMs: 4,
          triggerGapMs: 45,
          burstStartResolver: (int maxGapMs, int minTriggers) => 0,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 0,
          burstMemberResolver: (int maxGapMs, int minTriggers) => 1,
          burstIndexResolver: (int maxGapMs, int minTriggers) => 2,
        ),
      );
      expect(memberCommands.first.action, LovenseMockCommandAction.stop);
    });

    test('supports burstcount function for exact burst length checks', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText:
            'if burstcount(90) == 5 then vibrate(9, 700)\n'
            'else stop()',
      );

      final List<LovenseMockCommand> exactCommands = client.sendForAction(
        LovenseActionContext(
          index: 40,
          atMs: 7000,
          pos: 68,
          currentMs: 7004,
          deltaMs: 4,
          triggerGapMs: 40,
          burstCountResolver: (int maxGapMs) => 5,
        ),
      );
      expect(exactCommands.first.action, LovenseMockCommandAction.vibrate);
      expect(exactCommands.first.strength, 9);

      final List<LovenseMockCommand> nonExactCommands = client.sendForAction(
        LovenseActionContext(
          index: 41,
          atMs: 7080,
          pos: 68,
          currentMs: 7084,
          deltaMs: 4,
          triggerGapMs: 40,
          burstCountResolver: (int maxGapMs) => 6,
        ),
      );
      expect(nonExactCommands.first.action, LovenseMockCommandAction.stop);
    });

    test('reports no matching rule branches when no else exists', () {
      final LovenseMockClient client = LovenseMockClient.demo(
        rulesText: 'if pos > 95 then vibrate(10)',
      );

      final List<LovenseMockEvaluationResult> results = client.evaluateAction(
        const LovenseActionContext(
          index: 2,
          atMs: 1200,
          pos: 40,
          currentMs: 1210,
          deltaMs: 10,
        ),
      );

      expect(results, hasLength(3));
      expect(
        results.every(
          (LovenseMockEvaluationResult result) =>
              result.status == LovenseMockEvaluationStatus.noMatchingRule &&
              !result.hasCommand,
        ),
        isTrue,
      );
      expect(client.history, isEmpty);
    });
  });
}
