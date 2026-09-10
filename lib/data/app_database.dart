import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final database = await openDatabase(
      p.join(root, 'fatech.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onOpen: (db) async {
        await db.update(
          'attachments',
          {
            'transcription_status': 'error',
            'transcription_error':
                'Processamento interrompido. Tente novamente.',
          },
          where: 'transcription_status = ?',
          whereArgs: ['processing'],
        );
        await db.update(
          'occurrences',
          {
            'extraction_status': 'error',
            'extraction_error': 'Processamento interrompido. Tente novamente.',
          },
          where: 'extraction_status = ?',
          whereArgs: ['processing'],
        );
      },
    );
    _database = database;
    return database;
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE visits (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        visit_date TEXT NOT NULL,
        visit_type TEXT NOT NULL,
        enterprise TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('open','closed')),
        is_demo INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE occurrences (
        id TEXT PRIMARY KEY,
        visit_id TEXT NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
        status TEXT NOT NULL CHECK(status IN ('draft','finalized')),
        visit_date TEXT NOT NULL,
        visit_type TEXT NOT NULL,
        enterprise TEXT NOT NULL,
        location_reference TEXT NOT NULL DEFAULT '',
        environmental_occurrence TEXT NOT NULL DEFAULT '',
        technical_opinion TEXT NOT NULL DEFAULT '',
        written_report TEXT NOT NULL DEFAULT '',
        post_field_notes TEXT NOT NULL DEFAULT '',
        latitude REAL,
        longitude REAL,
        accuracy_m REAL,
        location_captured_at TEXT,
        location_source TEXT CHECK(location_source IN ('gps','manual_demo') OR location_source IS NULL),
        low_accuracy_acknowledged INTEGER NOT NULL DEFAULT 0,
        field_metadata_json TEXT NOT NULL DEFAULT '{}',
        extraction_status TEXT NOT NULL DEFAULT 'not_requested',
        extraction_error TEXT,
        extraction_input_hash TEXT,
        revision INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        reviewed_at TEXT,
        finalized_at TEXT,
        CHECK((latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL))
      )
    ''');
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        occurrence_id TEXT NOT NULL REFERENCES occurrences(id) ON DELETE CASCADE,
        kind TEXT NOT NULL CHECK(kind IN ('photo','audio')),
        relative_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        duration_ms INTEGER,
        captured_at TEXT NOT NULL,
        latitude_snapshot REAL,
        longitude_snapshot REAL,
        transcription_original TEXT,
        transcription_edited TEXT,
        transcription_status TEXT NOT NULL DEFAULT 'not_requested',
        transcription_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE map_exports (
        id TEXT PRIMARY KEY,
        visit_id TEXT NOT NULL REFERENCES visits(id) ON DELETE CASCADE,
        input_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        geojson_json TEXT NOT NULL,
        warnings_json TEXT NOT NULL,
        relative_kml_path TEXT NOT NULL,
        point_count INTEGER NOT NULL,
        has_hull INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_occurrences_visit ON occurrences(visit_id)',
    );
    await db.execute(
      'CREATE INDEX idx_attachments_occurrence ON attachments(occurrence_id)',
    );
    await db.execute(
      'CREATE INDEX idx_map_exports_visit ON map_exports(visit_id, created_at)',
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
