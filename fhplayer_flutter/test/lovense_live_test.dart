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
  });
}
