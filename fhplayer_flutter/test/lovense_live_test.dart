import 'package:fhplayer_flutter/lovense_live.dart';
import 'package:fhplayer_flutter/lovense_mock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LovenseLiveRuleEngine', () {
    const LovenseLiveRuleEngine engine = LovenseLiveRuleEngine();

    test('infers capabilities from short names and type hints', () {
      const LovenseLiveDevice nora = LovenseLiveDevice(
        id: 'nora-1',
        name: 'Nora',
        nickName: '',
        type: 'Nora',
        fullFunctionNames: <String>['Vibrate'],
        shortFunctionNames: <String>['r'],
      );

      final Set<String> capabilities = inferLovenseRuleCapabilities(nora);
      expect(capabilities.contains('vibrate'), isTrue);
      expect(capabilities.contains('rotate'), isTrue);
    });

    test('evaluates delays and durations into dispatch commands', () {
      const LovenseLiveDevice nora = LovenseLiveDevice(
        id: 'nora-1',
        name: 'Nora',
        nickName: '',
        type: 'Nora',
        fullFunctionNames: <String>['Vibrate', 'Rotate'],
        shortFunctionNames: <String>['v', 'r'],
      );

      final LovenseLiveRuleEvaluation evaluation = engine.evaluate(
        rulesText:
            'if pos >= 10 then delay(250) + vibrate(12, 800) + rotate(5, 1200)\n'
            'else stop()',
        context: const LovenseActionContext(
          index: 1,
          atMs: 750,
          pos: 80,
          currentMs: 760,
          deltaMs: 10,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );

      expect(evaluation.issues, isEmpty);
      expect(evaluation.commands, hasLength(2));
      expect(evaluation.commands[0].delayMs, 250);
      expect(evaluation.commands[0].durationMs, 800);
      expect(evaluation.commands[0].command.action, 'Vibrate:12');
      expect(evaluation.commands[1].delayMs, 250);
      expect(evaluation.commands[1].durationMs, 1200);
      expect(evaluation.commands[1].command.action, 'Rotate:5');
    });

    test('reports unsupported command capabilities for selected devices', () {
      const LovenseLiveDevice hush = LovenseLiveDevice(
        id: 'hush-1',
        name: 'Hush',
        nickName: '',
        type: 'Hush',
        fullFunctionNames: <String>['Vibrate'],
        shortFunctionNames: <String>['v'],
      );

      final LovenseLiveRuleEvaluation evaluation = engine.evaluate(
        rulesText: 'if pos >= 10 then rotate(6)\nelse stop()',
        context: const LovenseActionContext(
          index: 1,
          atMs: 750,
          pos: 80,
          currentMs: 760,
          deltaMs: 10,
        ),
        selectedDevices: const <LovenseLiveDevice>[hush],
      );

      expect(evaluation.commands, isEmpty);
      expect(evaluation.issues, isNotEmpty);
      expect(
        evaluation.issues.first.toString().toLowerCase(),
        contains('supports "rotate"'),
      );
    });

    test('supports trigger gap variables in conditions', () {
      const LovenseLiveDevice nora = LovenseLiveDevice(
        id: 'nora-1',
        name: 'Nora',
        nickName: '',
        type: 'Nora',
        fullFunctionNames: <String>['Vibrate'],
        shortFunctionNames: <String>['v'],
      );

      final LovenseLiveRuleEvaluation rapidEvaluation = engine.evaluate(
        rulesText:
            'if gapms < 90 then stop()\n'
            'else if triggergapms < 140 then vibrate(6, 800)\n'
            'else vibrate(12, 800)',
        context: const LovenseActionContext(
          index: 2,
          atMs: 1200,
          pos: 70,
          currentMs: 1204,
          deltaMs: 4,
          triggerGapMs: 80,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(rapidEvaluation.issues, isEmpty);
      expect(rapidEvaluation.commands, hasLength(1));
      expect(rapidEvaluation.commands.first.command.action, 'Stop');

      final LovenseLiveRuleEvaluation mediumEvaluation = engine.evaluate(
        rulesText:
            'if gapms < 90 then stop()\n'
            'else if triggergapms < 140 then vibrate(6, 800)\n'
            'else vibrate(12, 800)',
        context: const LovenseActionContext(
          index: 3,
          atMs: 1320,
          pos: 70,
          currentMs: 1325,
          deltaMs: 5,
          triggerGapMs: 120,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(mediumEvaluation.issues, isEmpty);
      expect(mediumEvaluation.commands, hasLength(1));
      expect(mediumEvaluation.commands.first.command.action, 'Vibrate:6');
    });

    test('supports burststart and burstduration functions', () {
      const LovenseLiveDevice nora = LovenseLiveDevice(
        id: 'nora-1',
        name: 'Nora',
        nickName: '',
        type: 'Nora',
        fullFunctionNames: <String>['Vibrate'],
        shortFunctionNames: <String>['v'],
      );

      final LovenseLiveRuleEvaluation burstEvaluation = engine.evaluate(
        rulesText:
            'if burststart(90, 3) >= 1 then vibrate(10, burstduration(90, 3))\n'
            'else stop()',
        context: LovenseActionContext(
          index: 4,
          atMs: 1800,
          pos: 75,
          currentMs: 1803,
          deltaMs: 3,
          triggerGapMs: 45,
          burstStartResolver: (int maxGapMs, int minTriggers) => 1,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 420,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(burstEvaluation.issues, isEmpty);
      expect(burstEvaluation.commands, hasLength(1));
      expect(burstEvaluation.commands.first.command.action, 'Vibrate:10');
      expect(burstEvaluation.commands.first.durationMs, 420);

      final LovenseLiveRuleEvaluation noBurstEvaluation = engine.evaluate(
        rulesText:
            'if burststart(90, 3) >= 1 then vibrate(10, burstduration(90, 3))\n'
            'else stop()',
        context: LovenseActionContext(
          index: 5,
          atMs: 1900,
          pos: 75,
          currentMs: 1906,
          deltaMs: 6,
          triggerGapMs: 100,
          burstStartResolver: (int maxGapMs, int minTriggers) => 0,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 0,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(noBurstEvaluation.issues, isEmpty);
      expect(noBurstEvaluation.commands, hasLength(1));
      expect(noBurstEvaluation.commands.first.command.action, 'Stop');
    });

    test('supports burstmember and burstindex functions', () {
      const LovenseLiveDevice nora = LovenseLiveDevice(
        id: 'nora-1',
        name: 'Nora',
        nickName: '',
        type: 'Nora',
        fullFunctionNames: <String>['Vibrate'],
        shortFunctionNames: <String>['v'],
      );

      final LovenseLiveRuleEvaluation memberEvaluation = engine.evaluate(
        rulesText:
            'if burstmember(90, 3) >= 1 then stop()\n'
            'else if burstindex(90, 3) >= 2 then vibrate(8, 600)\n'
            'else vibrate(5, 600)',
        context: LovenseActionContext(
          index: 6,
          atMs: 2100,
          pos: 75,
          currentMs: 2103,
          deltaMs: 3,
          triggerGapMs: 45,
          burstStartResolver: (int maxGapMs, int minTriggers) => 0,
          burstDurationMsResolver: (int maxGapMs, int minTriggers) => 0,
          burstMemberResolver: (int maxGapMs, int minTriggers) => 1,
          burstIndexResolver: (int maxGapMs, int minTriggers) => 2,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(memberEvaluation.issues, isEmpty);
      expect(memberEvaluation.commands, hasLength(1));
      expect(memberEvaluation.commands.first.command.action, 'Stop');
    });

    test('supports burstcount function for exact burst length checks', () {
      const LovenseLiveDevice nora = LovenseLiveDevice(
        id: 'nora-1',
        name: 'Nora',
        nickName: '',
        type: 'Nora',
        fullFunctionNames: <String>['Vibrate'],
        shortFunctionNames: <String>['v'],
      );

      final LovenseLiveRuleEvaluation exactEvaluation = engine.evaluate(
        rulesText:
            'if burstcount(90) == 5 then vibrate(11, 650)\n'
            'else stop()',
        context: LovenseActionContext(
          index: 7,
          atMs: 2400,
          pos: 76,
          currentMs: 2404,
          deltaMs: 4,
          triggerGapMs: 42,
          burstCountResolver: (int maxGapMs) => 5,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(exactEvaluation.issues, isEmpty);
      expect(exactEvaluation.commands, hasLength(1));
      expect(exactEvaluation.commands.first.command.action, 'Vibrate:11');

      final LovenseLiveRuleEvaluation nonExactEvaluation = engine.evaluate(
        rulesText:
            'if burstcount(90) == 5 then vibrate(11, 650)\n'
            'else stop()',
        context: LovenseActionContext(
          index: 8,
          atMs: 2450,
          pos: 76,
          currentMs: 2456,
          deltaMs: 6,
          triggerGapMs: 48,
          burstCountResolver: (int maxGapMs) => 4,
        ),
        selectedDevices: const <LovenseLiveDevice>[nora],
      );
      expect(nonExactEvaluation.issues, isEmpty);
      expect(nonExactEvaluation.commands, hasLength(1));
      expect(nonExactEvaluation.commands.first.command.action, 'Stop');
    });
  });
}
