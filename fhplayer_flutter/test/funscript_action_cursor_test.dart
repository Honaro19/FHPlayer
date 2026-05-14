import 'package:flutter_test/flutter_test.dart';

import 'package:fhplayer_flutter/main.dart';

void main() {
  group('FunscriptActionCursor', () {
    test('triggers due actions once as playback advances', () {
      final FunscriptActionCursor cursor = FunscriptActionCursor(
        _probeScript(),
      );

      expect(_indexes(cursor.triggerDue(0)), <int>[0]);
      expect(cursor.nextActionIndex, 1);
      expect(cursor.currentActionIndex, 0);
      expect(cursor.lastTriggeredActionIndex, 0);

      expect(cursor.triggerDue(749), isEmpty);
      expect(cursor.nextActionIndex, 1);
      expect(cursor.currentActionIndex, 0);

      expect(_indexes(cursor.triggerDue(2500)), <int>[1, 2, 3]);
      expect(cursor.nextActionIndex, 4);
      expect(cursor.currentActionIndex, 3);
      expect(cursor.lastTriggeredActionIndex, 3);

      expect(cursor.triggerDue(2500), isEmpty);
      expect(cursor.nextActionIndex, 4);
    });

    test('sync after seeking skips elapsed actions', () {
      final FunscriptActionCursor cursor = FunscriptActionCursor(
        _probeScript(),
      );

      cursor.sync(1600, includeCurrentAction: true);

      expect(cursor.currentActionIndex, 2);
      expect(cursor.nextActionIndex, 3);
      expect(_indexes(cursor.triggerDue(2500)), <int>[3]);
    });

    test('sync exactly on an action can keep that action due', () {
      final FunscriptActionCursor cursor = FunscriptActionCursor(
        _probeScript(),
      );

      cursor.sync(1500, includeCurrentAction: true);

      expect(cursor.currentActionIndex, 2);
      expect(cursor.nextActionIndex, 2);
      expect(_indexes(cursor.triggerDue(1500)), <int>[2]);
    });

    test('replay from the beginning resets due actions', () {
      final FunscriptActionCursor cursor = FunscriptActionCursor(
        _probeScript(),
      );

      expect(_indexes(cursor.triggerDue(7000)), <int>[0, 1, 2, 3, 4, 5, 6]);
      expect(cursor.nextActionIndex, 7);

      cursor.sync(0, includeCurrentAction: true);

      expect(cursor.nextActionIndex, 0);
      expect(cursor.currentActionIndex, 0);
      expect(_indexes(cursor.triggerDue(0)), <int>[0]);
    });
  });
}

Funscript _probeScript() {
  return Funscript.fromJson(<String, Object>{
    'actions': <Map<String, Object>>[
      <String, Object>{'at': 0, 'pos': 10},
      <String, Object>{'at': 750, 'pos': 90},
      <String, Object>{'at': 1500, 'pos': 20},
      <String, Object>{'at': 2500, 'pos': 80},
      <String, Object>{'at': 3750, 'pos': 35},
      <String, Object>{'at': 5200, 'pos': 95},
      <String, Object>{'at': 7000, 'pos': 15},
    ],
  }, sourceName: 'timing_probe.funscript');
}

List<int> _indexes(Iterable<FunscriptAction> actions) {
  return <int>[for (final FunscriptAction action in actions) action.index];
}
