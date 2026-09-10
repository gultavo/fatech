import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fatech/models/domain.dart';
import 'package:fatech/services/api_service.dart';
import 'package:fatech/widgets/common.dart';

void main() {
  test('URL da API usa loopback no Windows', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(defaultApiBaseUrl, 'http://127.0.0.1:8000');
    expect(resolveApiBaseUrl('http://10.0.2.2:8000'), 'http://127.0.0.1:8000');
  });

  test('hash do mapa é estável para a mesma ordem canônica', () {
    final points = [
      {
        'occurrence_id': 'b',
        'latitude': -27.0,
        'longitude': -48.0,
        'properties': {'status': 'draft'},
      },
    ];
    expect(mapInputHash(points), mapInputHash(points));
    final changed = [
      {
        ...points.first,
        'properties': {'status': 'finalized'},
      },
    ];
    expect(mapInputHash(changed), isNot(mapInputHash(points)));
  });

  test('Occurrence preserva null para coordenada ausente', () {
    final occurrence = Occurrence.fromMap({
      'id': 'occ-1',
      'visit_id': 'visit-1',
      'status': 'draft',
      'visit_date': '2026-09-09',
      'visit_type': 'Rotina',
      'enterprise': 'Teste',
      'location_reference': '',
      'environmental_occurrence': '',
      'technical_opinion': '',
      'written_report': '',
      'post_field_notes': '',
      'latitude': null,
      'longitude': null,
      'accuracy_m': null,
      'location_captured_at': null,
      'location_source': null,
      'low_accuracy_acknowledged': 0,
      'field_metadata_json': '{}',
      'extraction_status': 'not_requested',
      'extraction_error': null,
      'extraction_input_hash': null,
      'revision': 0,
      'created_at': '2026-09-09T00:00:00Z',
      'updated_at': '2026-09-09T00:00:00Z',
      'reviewed_at': null,
      'finalized_at': null,
    });
    expect(occurrence.hasLocation, isFalse);
    expect(occurrence.toMap()['latitude'], isNull);
  });

  testWidgets('status tem texto além da cor', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusPill(label: 'Rascunho', complete: false)),
      ),
    );
    expect(find.text('Rascunho'), findsOneWidget);
  });
}
