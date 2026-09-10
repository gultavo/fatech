import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/domain.dart';

const _androidEmulatorApiBaseUrl = 'http://10.0.2.2:8000';
const _desktopApiBaseUrl = 'http://127.0.0.1:8000';

String get defaultApiBaseUrl =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? _androidEmulatorApiBaseUrl
    : _desktopApiBaseUrl;

String resolveApiBaseUrl(String? configured) {
  final value = configured?.trim();
  if (value == null || value.isEmpty) return defaultApiBaseUrl;
  if (!kIsWeb &&
      defaultTargetPlatform != TargetPlatform.android &&
      value == _androidEmulatorApiBaseUrl) {
    return _desktopApiBaseUrl;
  }
  return value;
}

class ApiFailure implements Exception {
  const ApiFailure(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class HealthResult {
  const HealthResult({required this.reachable, required this.aiConfigured});
  final bool reachable;
  final bool aiConfigured;
}

class ExtractionResult {
  const ExtractionResult({
    required this.occurrenceId,
    required this.revision,
    required this.inputHash,
    required this.fields,
    required this.warnings,
  });

  final String occurrenceId;
  final int revision;
  final String inputHash;
  final Map<String, dynamic> fields;
  final List<String> warnings;
}

class MapGenerationResult {
  const MapGenerationResult({
    required this.visitId,
    required this.inputHash,
    required this.pointCount,
    required this.uniquePointCount,
    required this.hasHull,
    required this.warnings,
    required this.geojson,
    required this.kml,
  });

  final String visitId;
  final String inputHash;
  final int pointCount;
  final int uniquePointCount;
  final bool hasHull;
  final List<String> warnings;
  final Map<String, dynamic> geojson;
  final String kml;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 45);

  Uri _uri(String baseUrl, String path) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized$path');
  }

  Future<HealthResult> health(String baseUrl) async {
    try {
      final response = await _client
          .get(_uri(baseUrl, '/health'))
          .timeout(const Duration(seconds: 8));
      final body = _decode(response);
      return HealthResult(
        reachable: response.statusCode == 200 && body['status'] == 'ok',
        aiConfigured: (body['capabilities'] as Map?)?['ai_configured'] == true,
      );
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'API_UNREACHABLE',
        'Não foi possível acessar a API nesse endereço.',
      );
    }
  }

  Future<String> transcribe({
    required String baseUrl,
    required Occurrence occurrence,
    required Attachment attachment,
    required File file,
  }) async {
    try {
      final request =
          http.MultipartRequest(
              'POST',
              _uri(baseUrl, '/api/v1/audio/transcribe'),
            )
            ..fields['occurrence_id'] = occurrence.id
            ..fields['attachment_id'] = attachment.id
            ..files.add(
              await http.MultipartFile.fromPath(
                'file',
                file.path,
                filename: file.uri.pathSegments.last,
                contentType: MediaType.parse(attachment.mimeType),
              ),
            );
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final body = _decode(response);
      if (body['occurrence_id'] != occurrence.id ||
          body['attachment_id'] != attachment.id) {
        throw const ApiFailure(
          'MISMATCHED_RESPONSE',
          'A API respondeu para outro registro. A transcrição não foi aplicada.',
        );
      }
      return body['transcript'] as String;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'API_UNREACHABLE',
        'A transcrição falhou. O áudio permanece salvo; tente novamente.',
      );
    }
  }

  Future<ExtractionResult> extract({
    required String baseUrl,
    required Occurrence occurrence,
    required List<Map<String, String>> sources,
    required String inputHash,
  }) async {
    try {
      final response = await _client
          .post(
            _uri(baseUrl, '/api/v1/forms/extract'),
            headers: {'content-type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'occurrence_id': occurrence.id,
              'revision': occurrence.revision,
              'input_hash': inputHash,
              'sources': sources,
            }),
          )
          .timeout(_timeout);
      final body = _decode(response);
      return ExtractionResult(
        occurrenceId: body['occurrence_id'] as String,
        revision: (body['revision'] as num).toInt(),
        inputHash: body['input_hash'] as String,
        fields: Map<String, dynamic>.from(body['fields'] as Map),
        warnings: (body['warnings'] as List).cast<String>(),
      );
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'API_UNREACHABLE',
        'Não foi possível obter sugestões agora. O preenchimento manual segue disponível.',
      );
    }
  }

  Future<MapGenerationResult> generateMap({
    required String baseUrl,
    required Visit visit,
    required List<Occurrence> occurrences,
  }) async {
    final points = buildMapPoints(occurrences);
    final inputHash = mapInputHash(points);
    try {
      final response = await _client
          .post(
            _uri(baseUrl, '/api/v1/maps/generate'),
            headers: {'content-type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'visit_id': visit.id,
              'input_hash': inputHash,
              'points': points,
            }),
          )
          .timeout(_timeout);
      final body = _decode(response);
      return MapGenerationResult(
        visitId: body['visit_id'] as String,
        inputHash: body['input_hash'] as String,
        pointCount: (body['point_count'] as num).toInt(),
        uniquePointCount: (body['unique_point_count'] as num).toInt(),
        hasHull: body['has_hull'] as bool,
        warnings: (body['warnings'] as List).cast<String>(),
        geojson: Map<String, dynamic>.from(body['geojson'] as Map),
        kml: body['kml'] as String,
      );
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure(
        'API_UNREACHABLE',
        'Não foi possível acessar a API em ${baseUrl.trim()}. '
            'Inicie o backend e confira o endereço nas configurações.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw ApiFailure(
        'INVALID_RESPONSE',
        'A API devolveu uma resposta inválida.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'] as Map?;
      throw ApiFailure(
        error?['code'] as String? ?? 'HTTP_${response.statusCode}',
        error?['message'] as String? ?? 'Falha na API.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  void close() => _client.close();
}

List<Map<String, dynamic>> buildMapPoints(List<Occurrence> occurrences) {
  final valid = occurrences.where((item) => item.hasLocation).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return valid
      .map(
        (item) => <String, dynamic>{
          'occurrence_id': item.id,
          'latitude': item.latitude,
          'longitude': item.longitude,
          'properties': <String, dynamic>{
            'status': item.status,
            'visit_date': item.visitDate,
            'enterprise': item.enterprise,
            'environmental_occurrence': item.environmentalOccurrence,
            'technical_opinion': item.technicalOpinion.isEmpty
                ? null
                : item.technicalOpinion,
            'location_reference': item.locationReference,
            'accuracy_m': item.accuracyM,
            'location_source': item.locationSource,
            'is_demo': item.locationSource == 'manual_demo',
          },
        },
      )
      .toList();
}

String mapInputHash(List<Map<String, dynamic>> points) =>
    sha256.convert(utf8.encode(jsonEncode(points))).toString();

String sourcesHash(List<Map<String, String>> sources) =>
    sha256.convert(utf8.encode(jsonEncode(sources))).toString();
