import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/cycling_activity.dart';

class CyclingActivityRepository {
  CyclingActivityRepository({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<Directory> _routesDirectory() async {
    final parent = _directory ?? await getApplicationDocumentsDirectory();
    final routes = Directory('${parent.path}${Platform.pathSeparator}routes');
    await routes.create(recursive: true);
    return routes;
  }

  Future<List<CyclingActivity>> loadAll() async {
    final routes = await _routesDirectory();
    final activities = <CyclingActivity>[];
    await for (final entity in routes.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw FormatException(
            'El archivo de recorrido ${entity.uri} no es válido.');
      }
      activities.add(CyclingActivity.fromJson(decoded));
    }
    activities.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(activities);
  }

  Future<void> save(CyclingActivity activity) async {
    final routes = await _routesDirectory();
    final file = File(
      '${routes.path}${Platform.pathSeparator}${activity.id}.json',
    );
    await file.writeAsString(jsonEncode(activity.toJson()), flush: true);
  }
}
