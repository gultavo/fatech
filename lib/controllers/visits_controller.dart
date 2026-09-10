import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../models/domain.dart';

class VisitsController extends ChangeNotifier {
  VisitsController(this.repository);

  final AppRepository repository;
  List<Visit> visits = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      visits = await repository.listVisits();
    } catch (exception) {
      error = 'Não foi possível carregar as visitas: $exception';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
