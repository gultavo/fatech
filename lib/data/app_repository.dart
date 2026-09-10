import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/domain.dart';
import 'app_database.dart';

class AppRepository {
  AppRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  final Uuid _uuid = const Uuid();

  String newId() => _uuid.v4();
  String now() => DateTime.now().toUtc().toIso8601String();

  Future<List<Visit>> listVisits() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery('''
      SELECT v.*, COUNT(o.id) AS occurrence_count
      FROM visits v
      LEFT JOIN occurrences o ON o.visit_id = v.id
      GROUP BY v.id
      ORDER BY v.visit_date DESC, v.created_at DESC
    ''');
    return rows.map(Visit.fromMap).toList();
  }

  Future<Visit?> getVisit(String id) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''SELECT v.*, COUNT(o.id) AS occurrence_count
         FROM visits v LEFT JOIN occurrences o ON o.visit_id = v.id
         WHERE v.id = ? GROUP BY v.id''',
      [id],
    );
    return rows.isEmpty ? null : Visit.fromMap(rows.first);
  }

  Future<Visit> createVisit({
    required String title,
    required String visitDate,
    required String visitType,
    required String enterprise,
    bool isDemo = false,
  }) async {
    final timestamp = now();
    final visit = Visit(
      id: newId(),
      title: title.trim(),
      visitDate: visitDate,
      visitType: visitType,
      enterprise: enterprise.trim(),
      status: 'open',
      isDemo: isDemo,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final db = await _appDatabase.database;
    await db.insert('visits', visit.toMap());
    return visit;
  }

  Future<Visit> createDemoVisit() async {
    final date = DateTime.now();
    final dateText =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final visit = await createVisit(
      title: 'Visita demonstrativa · margem do reservatório',
      visitDate: dateText,
      visitType: 'Rotina',
      enterprise: 'Empreendimento fictício',
      isDemo: true,
    );
    const samples = [
      (-27.595400, -48.548000, 'Possível acúmulo de sedimentos'),
      (-27.596050, -48.546850, 'Vegetação limita a visibilidade'),
      (-27.597000, -48.548400, 'Ponto de observação da margem'),
      (-27.596250, -48.549100, 'Registro visual para conferência'),
    ];
    for (final sample in samples) {
      final occurrence = await createOccurrence(visit);
      await saveOccurrence(
        occurrence.copyWith(
          latitude: sample.$1,
          longitude: sample.$2,
          locationSource: 'manual_demo',
          locationCapturedAt: now(),
          environmentalOccurrence: sample.$3,
          writtenReport:
              '${sample.$3}. Registro fictício criado apenas para demonstrar mapa e KML.',
          revision: occurrence.revision + 1,
          updatedAt: now(),
        ),
      );
    }
    return visit;
  }

  Future<void> setVisitStatus(String id, String status) async {
    final db = await _appDatabase.database;
    await db.update(
      'visits',
      {'status': status, 'updated_at': now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Occurrence>> listOccurrences(String visitId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'occurrences',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Occurrence.fromMap).toList();
  }

  Future<Occurrence?> getOccurrence(String id) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'occurrences',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Occurrence.fromMap(rows.first);
  }

  Future<Occurrence> createOccurrence(Visit visit) async {
    final timestamp = now();
    final occurrence = Occurrence(
      id: newId(),
      visitId: visit.id,
      status: 'draft',
      visitDate: visit.visitDate,
      visitType: visit.visitType,
      enterprise: visit.enterprise,
      locationReference: '',
      environmentalOccurrence: '',
      technicalOpinion: '',
      writtenReport: '',
      postFieldNotes: '',
      latitude: null,
      longitude: null,
      accuracyM: null,
      locationCapturedAt: null,
      locationSource: null,
      lowAccuracyAcknowledged: false,
      fieldMetadata: const {
        'visit_date': {
          'origin': 'inherited_visit',
          'source_id': null,
          'evidence': null,
          'reviewed': false,
        },
        'visit_type': {
          'origin': 'inherited_visit',
          'source_id': null,
          'evidence': null,
          'reviewed': false,
        },
        'enterprise': {
          'origin': 'inherited_visit',
          'source_id': null,
          'evidence': null,
          'reviewed': false,
        },
      },
      extractionStatus: 'not_requested',
      extractionError: null,
      extractionInputHash: null,
      revision: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
      reviewedAt: null,
      finalizedAt: null,
    );
    final db = await _appDatabase.database;
    await db.insert('occurrences', occurrence.toMap());
    return occurrence;
  }

  Future<void> saveOccurrence(Occurrence occurrence) async {
    final db = await _appDatabase.database;
    await db.update(
      'occurrences',
      occurrence.toMap(),
      where: 'id = ?',
      whereArgs: [occurrence.id],
    );
  }

  Future<List<Attachment>> listAttachments(String occurrenceId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'attachments',
      where: 'occurrence_id = ?',
      whereArgs: [occurrenceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Attachment.fromMap).toList();
  }

  Future<void> addAttachment(Attachment attachment) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert('attachments', attachment.toMap());
      await _touchOccurrence(txn, attachment.occurrenceId);
    });
  }

  Future<void> saveAttachment(
    Attachment attachment, {
    bool touchOccurrence = false,
  }) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.update(
        'attachments',
        attachment.toMap(),
        where: 'id = ?',
        whereArgs: [attachment.id],
      );
      if (touchOccurrence) {
        await _touchOccurrence(txn, attachment.occurrenceId);
      }
    });
  }

  Future<void> deleteAttachment(String id, String occurrenceId) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.delete('attachments', where: 'id = ?', whereArgs: [id]);
      await _touchOccurrence(txn, occurrenceId);
    });
  }

  Future<void> _touchOccurrence(DatabaseExecutor db, String id) async {
    await db.rawUpdate(
      '''UPDATE occurrences
         SET revision = revision + 1, updated_at = ?, reviewed_at = NULL,
             status = 'draft', finalized_at = NULL,
             extraction_status = 'not_requested', extraction_input_hash = NULL
         WHERE id = ?''',
      [now(), id],
    );
  }

  Future<void> saveMapExport(MapExport export) async {
    final db = await _appDatabase.database;
    await db.insert('map_exports', export.toMap());
  }

  Future<MapExport?> latestMapExport(String visitId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'map_exports',
      where: 'visit_id = ?',
      whereArgs: [visitId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : MapExport.fromMap(rows.first);
  }

  Future<String?> getSetting(String key) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _appDatabase.database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
