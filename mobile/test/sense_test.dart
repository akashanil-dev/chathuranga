import 'package:flutter_test/flutter_test.dart';
import 'package:sense_mobile/core/constants.dart';

void main() {
  group('SENSE Core Constants and Protocol Tests', () {
    test('Protocol enum byte index integrity', () {
      expect(Dir.none.index, 0);
      expect(Dir.left.index, 1);
      expect(Dir.right.index, 2);
      expect(Dir.up.index, 3);
      expect(Dir.down.index, 4);
      expect(Dir.centered.index, 5);

      expect(Closeness.far.index, 0);
      expect(Closeness.mid.index, 1);
      expect(Closeness.near.index, 2);
      expect(Closeness.veryNear.index, 3);

      expect(GState.searching.index, 0);
      expect(GState.approaching.index, 1);
      expect(GState.reached.index, 2);
    });

    test('closenessFor correctly classifies distances', () {
      expect(closenessFor(0), Closeness.far); // No echo / invalid
      expect(closenessFor(20), Closeness.veryNear); // < 30 cm
      expect(closenessFor(45), Closeness.near); // < 60 cm
      expect(closenessFor(80), Closeness.mid); // < 100 cm
      expect(closenessFor(150), Closeness.far); // >= 100 cm
      expect(closenessFor(500), Closeness.far); // Out of range
    });

    test('dirFromX maps normalized horizontal position', () {
      expect(dirFromX(0.1), Dir.left);
      expect(dirFromX(0.34), Dir.left);
      expect(dirFromX(0.5), Dir.centered);
      expect(dirFromX(0.66), Dir.right);
      expect(dirFromX(0.9), Dir.right);
    });

    test('Target mappings are configured for offline COCO model', () {
      expect(kTargets, contains('PHONE'));
      expect(kTargets, contains('BOTTLE'));
      expect(kTargets, contains('CUP'));
      expect(kTargetLabels['PHONE'], 'cell phone');
      expect(kTargetLabels['BOTTLE'], 'bottle');
      expect(kTargetLabels['CUP'], 'cup');
      expect(kDetectorReady, isTrue);
    });
  });
}
