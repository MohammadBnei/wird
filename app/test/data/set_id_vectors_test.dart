import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/sets.dart';

/// The one file both halves answer to. The server suite reads the same rows
/// from server/internal/store/set_id_vectors_test.go; neither suite computes
/// what it asserts, so the two cannot agree with themselves while disagreeing
/// with each other.
const _vectorsPath = '../docs/adr/0002-set-identity-vectors.json';

void main() {
  // The failure: the device names a set by an id the server does not derive,
  // so the server refuses the prayer op — and a refusal is permanent, so the
  // prayer is dead-lettered and the reader loses it for good. The
  // expectations here are checked in, not computed, so this test reddens the
  // moment the device's derivation drifts from the server's.
  test('the device derives the set id the server derives for the same range,'
      ' so the prayer is not refused and lost', () {
    final file = File(_vectorsPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'without the shared vectors nothing checks the device against '
          'the server',
    );
    final vectors =
        (jsonDecode(file.readAsStringSync())['vectors'] as List).cast<Map<String, dynamic>>();
    expect(
      vectors,
      isNotEmpty,
      reason: 'empty vectors would pass without checking anything',
    );

    for (final v in vectors) {
      final order = ReadingOrder.values.byName(v['reading_order'] as String);
      expect(
        setIdFor(order, v['start_ayah_id'] as int, v['end_ayah_id'] as int),
        v['expected_set_id'],
        reason: '${v['label']}: the device names this set something the '
            'server will refuse',
      );
    }
  });
}
