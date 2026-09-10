import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fatech/data/app_database.dart';
import 'package:fatech/data/app_repository.dart';

void main() {
  late Directory testDirectory;
  late AppDatabase appDatabase;
  late AppRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'fatech_sqlite_test_',
    );
    await databaseFactory.setDatabasesPath(testDirectory.path);
    appDatabase = AppDatabase();
    repository = AppRepository(appDatabase);
    await appDatabase.database;
  });

  tearDown(() async {
    await appDatabase.close();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('visita e ocorrências persistem com vínculos e IDs distintos', () async {
    final visit = await repository.createVisit(
      title: 'Teste de campo',
      visitDate: '2026-09-09',
      visitType: 'Rotina',
      enterprise: 'Empreendimento de teste',
    );
    final first = await repository.createOccurrence(visit);
    final second = await repository.createOccurrence(visit);

    expect(first.id, isNot(second.id));
    expect(first.visitId, visit.id);
    expect(second.visitId, visit.id);

    await repository.saveOccurrence(
      first.copyWith(
        writtenReport: 'Relato alterado apenas no primeiro ponto.',
        revision: 1,
        updatedAt: repository.now(),
      ),
    );
    expect((await repository.getOccurrence(second.id))!.writtenReport, isEmpty);

    await appDatabase.close();
    appDatabase = AppDatabase();
    repository = AppRepository(appDatabase);
    final reopened = await repository.listOccurrences(visit.id);

    expect(reopened, hasLength(2));
    expect(
      reopened.singleWhere((item) => item.id == first.id).writtenReport,
      contains('primeiro ponto'),
    );
  });

  test('rascunho aceita campos, anexos e coordenada ausentes', () async {
    final visit = await repository.createVisit(
      title: 'Rascunho',
      visitDate: '2026-09-09',
      visitType: 'Outro',
      enterprise: 'Teste',
    );
    final occurrence = await repository.createOccurrence(visit);
    final saved = await repository.getOccurrence(occurrence.id);

    expect(saved!.status, 'draft');
    expect(saved.latitude, isNull);
    expect(await repository.listAttachments(saved.id), isEmpty);
  });
}
