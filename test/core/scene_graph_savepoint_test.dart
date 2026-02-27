import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/scene_graph/scene_graph_savepoint.dart';

void main() {
  group('SceneGraphSavepoint', () {
    test('stores name, offset, and version', () {
      const sp = SceneGraphSavepoint(
        name: 'before-constraint',
        inverseOpsOffset: 3,
        versionAtSavepoint: 7,
      );

      expect(sp.name, 'before-constraint');
      expect(sp.inverseOpsOffset, 3);
      expect(sp.versionAtSavepoint, 7);
    });

    test('toString includes name and offset', () {
      const sp = SceneGraphSavepoint(
        name: 'test',
        inverseOpsOffset: 5,
        versionAtSavepoint: 10,
      );

      expect(sp.toString(), contains('test'));
      expect(sp.toString(), contains('5'));
    });

    test('can be const-constructed', () {
      // Multiple const instances with same args should be identical.
      const sp1 = SceneGraphSavepoint(
        name: 'x',
        inverseOpsOffset: 0,
        versionAtSavepoint: 0,
      );
      const sp2 = SceneGraphSavepoint(
        name: 'x',
        inverseOpsOffset: 0,
        versionAtSavepoint: 0,
      );

      expect(identical(sp1, sp2), isTrue);
    });
  });
}
