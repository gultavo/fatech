import 'dart:convert';

bool _boolFromDb(Object? value) => value == 1 || value == true;
int _boolToDb(bool value) => value ? 1 : 0;

class Visit {
  const Visit({
    required this.id,
    required this.title,
    required this.visitDate,
    required this.visitType,
    required this.enterprise,
    required this.status,
    required this.isDemo,
    required this.createdAt,
    required this.updatedAt,
    this.occurrenceCount = 0,
  });

  final String id;
  final String title;
  final String visitDate;
  final String visitType;
  final String enterprise;
  final String status;
  final bool isDemo;
  final String createdAt;
  final String updatedAt;
  final int occurrenceCount;

  bool get isClosed => status == 'closed';

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'visit_date': visitDate,
    'visit_type': visitType,
    'enterprise': enterprise,
    'status': status,
    'is_demo': _boolToDb(isDemo),
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory Visit.fromMap(Map<String, Object?> map) => Visit(
    id: map['id']! as String,
    title: map['title']! as String,
    visitDate: map['visit_date']! as String,
    visitType: map['visit_type']! as String,
    enterprise: map['enterprise']! as String,
    status: map['status']! as String,
    isDemo: _boolFromDb(map['is_demo']),
    createdAt: map['created_at']! as String,
    updatedAt: map['updated_at']! as String,
    occurrenceCount: (map['occurrence_count'] as num?)?.toInt() ?? 0,
  );
}

class Occurrence {
  const Occurrence({
    required this.id,
    required this.visitId,
    required this.status,
    required this.visitDate,
    required this.visitType,
    required this.enterprise,
    required this.locationReference,
    required this.environmentalOccurrence,
    required this.technicalOpinion,
    required this.writtenReport,
    required this.postFieldNotes,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.locationCapturedAt,
    required this.locationSource,
    required this.lowAccuracyAcknowledged,
    required this.fieldMetadata,
    required this.extractionStatus,
    required this.extractionError,
    required this.extractionInputHash,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedAt,
    required this.finalizedAt,
  });

  final String id;
  final String visitId;
  final String status;
  final String visitDate;
  final String visitType;
  final String enterprise;
  final String locationReference;
  final String environmentalOccurrence;
  final String technicalOpinion;
  final String writtenReport;
  final String postFieldNotes;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final String? locationCapturedAt;
  final String? locationSource;
  final bool lowAccuracyAcknowledged;
  final Map<String, dynamic> fieldMetadata;
  final String extractionStatus;
  final String? extractionError;
  final String? extractionInputHash;
  final int revision;
  final String createdAt;
  final String updatedAt;
  final String? reviewedAt;
  final String? finalizedAt;

  bool get isFinalized => status == 'finalized';
  bool get hasLocation => latitude != null && longitude != null;

  Occurrence copyWith({
    String? status,
    String? visitDate,
    String? visitType,
    String? enterprise,
    String? locationReference,
    String? environmentalOccurrence,
    String? technicalOpinion,
    String? writtenReport,
    String? postFieldNotes,
    double? latitude,
    double? longitude,
    double? accuracyM,
    String? locationCapturedAt,
    String? locationSource,
    bool? lowAccuracyAcknowledged,
    Map<String, dynamic>? fieldMetadata,
    String? extractionStatus,
    String? extractionError,
    String? extractionInputHash,
    int? revision,
    String? updatedAt,
    String? reviewedAt,
    String? finalizedAt,
    bool clearLocation = false,
    bool clearExtractionError = false,
    bool clearReviewedAt = false,
    bool clearFinalizedAt = false,
  }) => Occurrence(
    id: id,
    visitId: visitId,
    status: status ?? this.status,
    visitDate: visitDate ?? this.visitDate,
    visitType: visitType ?? this.visitType,
    enterprise: enterprise ?? this.enterprise,
    locationReference: locationReference ?? this.locationReference,
    environmentalOccurrence:
        environmentalOccurrence ?? this.environmentalOccurrence,
    technicalOpinion: technicalOpinion ?? this.technicalOpinion,
    writtenReport: writtenReport ?? this.writtenReport,
    postFieldNotes: postFieldNotes ?? this.postFieldNotes,
    latitude: clearLocation ? null : latitude ?? this.latitude,
    longitude: clearLocation ? null : longitude ?? this.longitude,
    accuracyM: clearLocation ? null : accuracyM ?? this.accuracyM,
    locationCapturedAt: clearLocation
        ? null
        : locationCapturedAt ?? this.locationCapturedAt,
    locationSource: clearLocation
        ? null
        : locationSource ?? this.locationSource,
    lowAccuracyAcknowledged:
        lowAccuracyAcknowledged ?? this.lowAccuracyAcknowledged,
    fieldMetadata: fieldMetadata ?? this.fieldMetadata,
    extractionStatus: extractionStatus ?? this.extractionStatus,
    extractionError: clearExtractionError
        ? null
        : extractionError ?? this.extractionError,
    extractionInputHash: extractionInputHash ?? this.extractionInputHash,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reviewedAt: clearReviewedAt ? null : reviewedAt ?? this.reviewedAt,
    finalizedAt: clearFinalizedAt ? null : finalizedAt ?? this.finalizedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'visit_id': visitId,
    'status': status,
    'visit_date': visitDate,
    'visit_type': visitType,
    'enterprise': enterprise,
    'location_reference': locationReference,
    'environmental_occurrence': environmentalOccurrence,
    'technical_opinion': technicalOpinion,
    'written_report': writtenReport,
    'post_field_notes': postFieldNotes,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'location_captured_at': locationCapturedAt,
    'location_source': locationSource,
    'low_accuracy_acknowledged': _boolToDb(lowAccuracyAcknowledged),
    'field_metadata_json': jsonEncode(fieldMetadata),
    'extraction_status': extractionStatus,
    'extraction_error': extractionError,
    'extraction_input_hash': extractionInputHash,
    'revision': revision,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'reviewed_at': reviewedAt,
    'finalized_at': finalizedAt,
  };

  factory Occurrence.fromMap(Map<String, Object?> map) => Occurrence(
    id: map['id']! as String,
    visitId: map['visit_id']! as String,
    status: map['status']! as String,
    visitDate: map['visit_date']! as String,
    visitType: map['visit_type']! as String,
    enterprise: map['enterprise']! as String,
    locationReference: map['location_reference'] as String? ?? '',
    environmentalOccurrence: map['environmental_occurrence'] as String? ?? '',
    technicalOpinion: map['technical_opinion'] as String? ?? '',
    writtenReport: map['written_report'] as String? ?? '',
    postFieldNotes: map['post_field_notes'] as String? ?? '',
    latitude: (map['latitude'] as num?)?.toDouble(),
    longitude: (map['longitude'] as num?)?.toDouble(),
    accuracyM: (map['accuracy_m'] as num?)?.toDouble(),
    locationCapturedAt: map['location_captured_at'] as String?,
    locationSource: map['location_source'] as String?,
    lowAccuracyAcknowledged: _boolFromDb(map['low_accuracy_acknowledged']),
    fieldMetadata: _decodeMetadata(map['field_metadata_json'] as String?),
    extractionStatus: map['extraction_status'] as String? ?? 'not_requested',
    extractionError: map['extraction_error'] as String?,
    extractionInputHash: map['extraction_input_hash'] as String?,
    revision: (map['revision'] as num?)?.toInt() ?? 0,
    createdAt: map['created_at']! as String,
    updatedAt: map['updated_at']! as String,
    reviewedAt: map['reviewed_at'] as String?,
    finalizedAt: map['finalized_at'] as String?,
  );

  static Map<String, dynamic> _decodeMetadata(String? value) {
    if (value == null || value.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return {};
    }
  }
}

class Attachment {
  const Attachment({
    required this.id,
    required this.occurrenceId,
    required this.kind,
    required this.relativePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.durationMs,
    required this.capturedAt,
    required this.latitudeSnapshot,
    required this.longitudeSnapshot,
    required this.transcriptionOriginal,
    required this.transcriptionEdited,
    required this.transcriptionStatus,
    required this.transcriptionError,
    required this.createdAt,
  });

  final String id;
  final String occurrenceId;
  final String kind;
  final String relativePath;
  final String mimeType;
  final int sizeBytes;
  final int? durationMs;
  final String capturedAt;
  final double? latitudeSnapshot;
  final double? longitudeSnapshot;
  final String? transcriptionOriginal;
  final String? transcriptionEdited;
  final String transcriptionStatus;
  final String? transcriptionError;
  final String createdAt;

  bool get isPhoto => kind == 'photo';
  bool get isAudio => kind == 'audio';

  Attachment copyWith({
    String? transcriptionOriginal,
    String? transcriptionEdited,
    String? transcriptionStatus,
    String? transcriptionError,
    bool clearTranscriptionError = false,
  }) => Attachment(
    id: id,
    occurrenceId: occurrenceId,
    kind: kind,
    relativePath: relativePath,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    durationMs: durationMs,
    capturedAt: capturedAt,
    latitudeSnapshot: latitudeSnapshot,
    longitudeSnapshot: longitudeSnapshot,
    transcriptionOriginal: transcriptionOriginal ?? this.transcriptionOriginal,
    transcriptionEdited: transcriptionEdited ?? this.transcriptionEdited,
    transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
    transcriptionError: clearTranscriptionError
        ? null
        : transcriptionError ?? this.transcriptionError,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'occurrence_id': occurrenceId,
    'kind': kind,
    'relative_path': relativePath,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'duration_ms': durationMs,
    'captured_at': capturedAt,
    'latitude_snapshot': latitudeSnapshot,
    'longitude_snapshot': longitudeSnapshot,
    'transcription_original': transcriptionOriginal,
    'transcription_edited': transcriptionEdited,
    'transcription_status': transcriptionStatus,
    'transcription_error': transcriptionError,
    'created_at': createdAt,
  };

  factory Attachment.fromMap(Map<String, Object?> map) => Attachment(
    id: map['id']! as String,
    occurrenceId: map['occurrence_id']! as String,
    kind: map['kind']! as String,
    relativePath: map['relative_path']! as String,
    mimeType: map['mime_type']! as String,
    sizeBytes: (map['size_bytes'] as num).toInt(),
    durationMs: (map['duration_ms'] as num?)?.toInt(),
    capturedAt: map['captured_at']! as String,
    latitudeSnapshot: (map['latitude_snapshot'] as num?)?.toDouble(),
    longitudeSnapshot: (map['longitude_snapshot'] as num?)?.toDouble(),
    transcriptionOriginal: map['transcription_original'] as String?,
    transcriptionEdited: map['transcription_edited'] as String?,
    transcriptionStatus:
        map['transcription_status'] as String? ?? 'not_requested',
    transcriptionError: map['transcription_error'] as String?,
    createdAt: map['created_at']! as String,
  );
}

class MapExport {
  const MapExport({
    required this.id,
    required this.visitId,
    required this.inputHash,
    required this.createdAt,
    required this.geojsonJson,
    required this.warningsJson,
    required this.relativeKmlPath,
    required this.pointCount,
    required this.hasHull,
  });

  final String id;
  final String visitId;
  final String inputHash;
  final String createdAt;
  final String geojsonJson;
  final String warningsJson;
  final String relativeKmlPath;
  final int pointCount;
  final bool hasHull;

  Map<String, Object?> toMap() => {
    'id': id,
    'visit_id': visitId,
    'input_hash': inputHash,
    'created_at': createdAt,
    'geojson_json': geojsonJson,
    'warnings_json': warningsJson,
    'relative_kml_path': relativeKmlPath,
    'point_count': pointCount,
    'has_hull': _boolToDb(hasHull),
  };

  factory MapExport.fromMap(Map<String, Object?> map) => MapExport(
    id: map['id']! as String,
    visitId: map['visit_id']! as String,
    inputHash: map['input_hash']! as String,
    createdAt: map['created_at']! as String,
    geojsonJson: map['geojson_json']! as String,
    warningsJson: map['warnings_json']! as String,
    relativeKmlPath: map['relative_kml_path']! as String,
    pointCount: (map['point_count'] as num).toInt(),
    hasHull: _boolFromDb(map['has_hull']),
  );
}
