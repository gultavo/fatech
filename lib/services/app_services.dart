import '../data/app_database.dart';
import '../data/app_repository.dart';
import '../data/file_storage.dart';
import 'api_service.dart';
import 'location_service.dart';
import 'media_service.dart';

class AppServices {
  AppServices._({
    required this.database,
    required this.repository,
    required this.storage,
    required this.api,
    required this.location,
    required this.media,
  });

  final AppDatabase database;
  final AppRepository repository;
  final FileStorage storage;
  final ApiService api;
  final LocationService location;
  final MediaService media;

  static Future<AppServices> create() async {
    final database = AppDatabase();
    await database.database;
    final storage = FileStorage();
    await storage.root;
    return AppServices._(
      database: database,
      repository: AppRepository(database),
      storage: storage,
      api: ApiService(),
      location: LocationService(),
      media: MediaService(storage),
    );
  }

  Future<void> dispose() async {
    api.close();
    await media.dispose();
    await database.close();
  }
}
