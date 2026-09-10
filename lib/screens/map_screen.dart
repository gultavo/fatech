import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../models/domain.dart';
import '../services/app_services.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import 'occurrence_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.services, required this.visit});

  final AppServices services;
  final Visit visit;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Occurrence> _occurrences = [];
  MapExport? _export;
  List<LatLng> _hull = [];
  bool _loading = true;
  bool _generating = false;
  bool _exporting = false;
  bool _tilesFailed = false;
  String _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  String _tileAttribution = 'OpenStreetMap contributors';

  List<Occurrence> get _withLocation =>
      _occurrences.where((item) => item.hasLocation).toList();
  String get _currentHash => mapInputHash(buildMapPoints(_occurrences));
  bool get _exportIsCurrent =>
      _export != null && _export!.inputHash == _currentHash;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final occurrences = await widget.services.repository.listOccurrences(
      widget.visit.id,
    );
    final export = await widget.services.repository.latestMapExport(
      widget.visit.id,
    );
    final tileUrl =
        await widget.services.repository.getSetting('tile_url_template') ??
        _tileUrl;
    final tileAttribution =
        await widget.services.repository.getSetting('tile_attribution') ??
        _tileAttribution;
    if (!mounted) return;
    setState(() {
      _occurrences = occurrences;
      _export = export;
      _hull = export == null ? [] : _parseHull(export.geojsonJson);
      _tileUrl = tileUrl;
      _tileAttribution = tileAttribution;
      _loading = false;
    });
  }

  List<LatLng> _parseHull(String geojsonText) {
    try {
      final geojson = jsonDecode(geojsonText) as Map<String, dynamic>;
      final features = geojson['features'] as List;
      final hull = features.cast<Map>().where(
        (feature) => (feature['properties'] as Map?)?['kind'] == 'hull',
      );
      if (hull.isEmpty) return [];
      final rings = (hull.first['geometry'] as Map)['coordinates'] as List;
      final coordinates = rings.first as List;
      return coordinates.map((value) {
        final pair = value as List;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _generate() async {
    if (_withLocation.isEmpty || _generating) return false;
    setState(() => _generating = true);
    try {
      final baseUrl = resolveApiBaseUrl(
        await widget.services.repository.getSetting('api_base_url'),
      );
      final snapshotHash = _currentHash;
      final result = await widget.services.api.generateMap(
        baseUrl: baseUrl,
        visit: widget.visit,
        occurrences: _occurrences,
      );
      final fresh = await widget.services.repository.listOccurrences(
        widget.visit.id,
      );
      final freshHash = mapInputHash(buildMapPoints(fresh));
      if (freshHash != snapshotHash ||
          result.inputHash != snapshotHash ||
          result.visitId != widget.visit.id) {
        throw const ApiFailure(
          'STALE_RESPONSE',
          'Os dados mudaram durante a geração. O resultado não foi salvo; gere novamente.',
        );
      }
      final id = widget.services.repository.newId();
      final file = await widget.services.storage.writeKml(
        widget.visit.id,
        id,
        result.kml,
      );
      final export = MapExport(
        id: id,
        visitId: widget.visit.id,
        inputHash: result.inputHash,
        createdAt: widget.services.repository.now(),
        geojsonJson: jsonEncode(result.geojson),
        warningsJson: jsonEncode(result.warnings),
        relativeKmlPath: await widget.services.storage.relativePath(file),
        pointCount: result.pointCount,
        hasHull: result.hasHull,
      );
      await widget.services.repository.saveMapExport(export);
      if (!mounted) return false;
      setState(() {
        _occurrences = fresh;
        _export = export;
        _hull = _parseHull(export.geojsonJson);
      });
      final message = result.hasHull
          ? 'Contorno e KML gerados com ${result.pointCount} ponto(s).'
          : 'KML gerado sem contorno. ${result.warnings.join(' ')}';
      showMessage(context, message);
      return true;
    } on ApiFailure catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
      return false;
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _shareKml() async {
    if (_exporting || _generating) return;
    setState(() => _exporting = true);
    try {
      if (!_exportIsCurrent && !await _generate()) return;
      final export = _export;
      if (export == null) return;
      final path = await widget.services.storage.absolutePath(
        export.relativeKmlPath,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(path, mimeType: 'application/vnd.google-earth.kml+xml'),
          ],
          text:
              'KML da visita “${widget.visit.title}”. Fotos e áudios permanecem no aplicativo.',
        ),
      );
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Não foi possível abrir o compartilhamento do KML.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showOccurrence(Occurrence occurrence) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ocorrência ${shortId(occurrence.id)}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                occurrence.environmentalOccurrence.isEmpty
                    ? 'Descrição ainda não preenchida.'
                    : occurrence.environmentalOccurrence,
              ),
              const SizedBox(height: 8),
              Text(
                '${occurrence.latitude!.toStringAsFixed(7)}, ${occurrence.longitude!.toStringAsFixed(7)}'
                '${occurrence.locationSource == 'manual_demo' ? ' · DADO FICTÍCIO' : ''}',
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (_) => OccurrenceScreen(
                            services: widget.services,
                            visit: widget.visit,
                            occurrenceId: occurrence.id,
                          ),
                        ),
                      )
                      .then((_) => _load());
                },
                child: const Text('Abrir registro completo'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTileError(Object tile, Object error, StackTrace? stackTrace) {
    if (_tilesFailed || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tilesFailed) setState(() => _tilesFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _generating || _exporting;
    final points = _withLocation
        .map((item) => LatLng(item.latitude!, item.longitude!))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa da visita')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFFF3CD),
                    padding: const EdgeInsets.all(10),
                    child: const Text(
                      'Contorno dos pontos registrados. Não representa uma delimitação técnica da área afetada.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${points.length} ponto(s) · ${_occurrences.length - points.length} sem coordenada',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_export != null)
                          StatusPill(
                            label: _exportIsCurrent
                                ? 'Exportação atual'
                                : 'Exportação desatualizada',
                            complete: _exportIsCurrent,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: points.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text(
                                'Capture uma localização em ao menos uma ocorrência para visualizar e exportar pontos.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              FlutterMap(
                                options: MapOptions(
                                  initialCenter: points.first,
                                  initialZoom: points.length == 1 ? 17 : 14,
                                  initialCameraFit: points.length > 1
                                      ? CameraFit.bounds(
                                          bounds: LatLngBounds.fromPoints(
                                            points,
                                          ),
                                          padding: const EdgeInsets.all(48),
                                        )
                                      : null,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: _tileUrl,
                                    userAgentPackageName: 'com.example.fatech',
                                    errorTileCallback: _onTileError,
                                  ),
                                  if (_hull.length >= 4)
                                    PolygonLayer(
                                      polygons: [
                                        Polygon(
                                          points: _hull,
                                          color: const Color(
                                            0xFF1C70AD,
                                          ).withValues(alpha: 0.16),
                                          borderColor: const Color(0xFF1C70AD),
                                          borderStrokeWidth: 3,
                                          pattern: StrokePattern.dashed(
                                            segments: const [10, 8],
                                          ),
                                        ),
                                      ],
                                    ),
                                  MarkerLayer(
                                    markers: _withLocation.map((item) {
                                      final color =
                                          item.locationSource == 'manual_demo'
                                          ? Colors.deepOrange
                                          : item.isFinalized
                                          ? const Color(0xFF279271)
                                          : const Color(0xFF1C70AD);
                                      return Marker(
                                        point: LatLng(
                                          item.latitude!,
                                          item.longitude!,
                                        ),
                                        width: 48,
                                        height: 48,
                                        child: IconButton.filled(
                                          tooltip:
                                              'Abrir ocorrência ${shortId(item.id)}',
                                          style: IconButton.styleFrom(
                                            backgroundColor: color,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () =>
                                              _showOccurrence(item),
                                          icon: const Icon(Icons.location_on),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  RichAttributionWidget(
                                    attributions: [
                                      TextSourceAttribution(_tileAttribution),
                                    ],
                                  ),
                                ],
                              ),
                              if (_tilesFailed)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  top: 12,
                                  child: Material(
                                    color: Colors.blueGrey.shade800,
                                    borderRadius: BorderRadius.circular(10),
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Text(
                                        'Mapa-base indisponível. Marcadores e contorno locais continuam visíveis.',
                                        style: TextStyle(color: Colors.white),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: points.isEmpty || busy
                                ? null
                                : _generate,
                            icon: _generating && !_exporting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.gesture),
                            label: const Text('Gerar contorno'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: points.isEmpty || busy
                                ? null
                                : _shareKml,
                            icon: _exporting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.share_outlined),
                            label: const Text('Exportar KML'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
