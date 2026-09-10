import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../models/domain.dart';
import '../services/app_services.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/common.dart';
import 'form_review_screen.dart';

class OccurrenceScreen extends StatefulWidget {
  const OccurrenceScreen({
    super.key,
    required this.services,
    required this.visit,
    required this.occurrenceId,
  });

  final AppServices services;
  final Visit visit;
  final String occurrenceId;

  @override
  State<OccurrenceScreen> createState() => _OccurrenceScreenState();
}

class _OccurrenceScreenState extends State<OccurrenceScreen>
    with WidgetsBindingObserver {
  final _written = TextEditingController();
  final _postField = TextEditingController();
  final Map<String, Timer> _transcriptTimers = {};
  Occurrence? _occurrence;
  List<Attachment> _attachments = [];
  bool _loading = true;
  bool _saving = false;
  bool _capturingLocation = false;
  bool _recording = false;
  bool _stoppingRecording = false;
  bool _allowPop = false;
  bool _backInProgress = false;
  String? _recordingId;
  DateTime? _recordingStartedAt;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  Timer? _saveTimer;
  bool _initializingControllers = false;

  bool get _editable => _occurrence != null && !_occurrence!.isFinalized;
  List<Attachment> get _photos =>
      _attachments.where((item) => item.isPhoto).toList();
  List<Attachment> get _audios =>
      _attachments.where((item) => item.isAudio).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _written.addListener(_textChanged);
    _postField.addListener(_textChanged);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_recording && state != AppLifecycleState.resumed) {
      unawaited(_stopRecording(interrupted: true));
    } else if (state != AppLifecycleState.resumed) {
      unawaited(_saveText());
    }
  }

  Future<void> _load() async {
    final occurrence = await widget.services.repository.getOccurrence(
      widget.occurrenceId,
    );
    final attachments = await widget.services.repository.listAttachments(
      widget.occurrenceId,
    );
    if (!mounted) return;
    setState(() {
      _occurrence = occurrence;
      _attachments = attachments;
      _loading = false;
      if (occurrence != null) {
        _initializingControllers = true;
        _written.text = occurrence.writtenReport;
        _postField.text = occurrence.postFieldNotes;
        _initializingControllers = false;
      }
    });
    await _recoverLostPhoto();
  }

  void _textChanged() {
    if (_initializingControllers || !_editable) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), _saveText);
  }

  Future<void> _saveText({bool notify = false}) async {
    final occurrence = _occurrence;
    if (occurrence == null || occurrence.isFinalized || _saving) return;
    _saveTimer?.cancel();
    final written = _written.text;
    final postField = _postField.text;
    if (written == occurrence.writtenReport &&
        postField == occurrence.postFieldNotes) {
      if (notify && mounted) showMessage(context, 'Rascunho já está salvo.');
      return;
    }
    setState(() => _saving = true);
    final updated = occurrence.copyWith(
      writtenReport: written,
      postFieldNotes: postField,
      status: 'draft',
      extractionStatus: 'not_requested',
      revision: occurrence.revision + 1,
      updatedAt: widget.services.repository.now(),
      clearReviewedAt: true,
      clearFinalizedAt: true,
    );
    await widget.services.repository.saveOccurrence(updated);
    if (!mounted) return;
    setState(() {
      _occurrence = updated;
      _saving = false;
    });
    if (notify) showMessage(context, 'Rascunho salvo no aparelho.');
  }

  Future<void> _recoverLostPhoto() async {
    final repository = widget.services.repository;
    final pending = await repository.getSetting('pending_photo_occurrence_id');
    if (pending != widget.occurrenceId) return;
    final lost = await widget.services.media.retrieveLostPhotos();
    for (final item in lost) {
      await _persistPickedPhoto(item.path);
    }
    await repository.setSetting('pending_photo_occurrence_id', '');
    if (lost.isNotEmpty && mounted) {
      showMessage(context, 'Foto recuperada e vinculada à ocorrência.');
    }
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Usar câmera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final id = widget.services.repository.newId();
    await widget.services.repository.setSetting(
      'pending_photo_occurrence_id',
      widget.occurrenceId,
    );
    try {
      final file = await widget.services.media.pickPhoto(
        source: source,
        id: id,
      );
      if (file != null) await _persistPhotoFile(file, id);
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          'Não foi possível adicionar a foto: $error',
          error: true,
        );
      }
    } finally {
      await widget.services.repository.setSetting(
        'pending_photo_occurrence_id',
        '',
      );
    }
  }

  Future<void> _persistPickedPhoto(String sourcePath) async {
    final id = widget.services.repository.newId();
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath).toLowerCase();
    final file = await widget.services.storage.copyAttachment(
      sourcePath: sourcePath,
      id: id,
      kind: 'photo',
      extension: extension,
    );
    await _persistPhotoFile(file, id);
  }

  Future<void> _persistPhotoFile(File file, String id) async {
    final occurrence = _occurrence!;
    final stat = await file.stat();
    final relative = await widget.services.storage.relativePath(file);
    final extension = p.extension(file.path).toLowerCase();
    final mime = switch (extension) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' || '.heif' => 'image/heic',
      '.gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    final attachment = Attachment(
      id: id,
      occurrenceId: occurrence.id,
      kind: 'photo',
      relativePath: relative,
      mimeType: mime,
      sizeBytes: stat.size,
      durationMs: null,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      latitudeSnapshot: occurrence.latitude,
      longitudeSnapshot: occurrence.longitude,
      transcriptionOriginal: null,
      transcriptionEdited: null,
      transcriptionStatus: 'not_requested',
      transcriptionError: null,
      createdAt: widget.services.repository.now(),
    );
    await widget.services.repository.addAttachment(attachment);
    await _reloadAfterAttachment();
  }

  Future<void> _removeAttachment(Attachment attachment) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              attachment.isPhoto ? 'Remover foto?' : 'Remover áudio?',
            ),
            content: const Text('Somente este anexo será apagado do aparelho.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remover'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.services.repository.deleteAttachment(
      attachment.id,
      attachment.occurrenceId,
    );
    await widget.services.storage.deleteRelative(attachment.relativePath);
    await _reloadAfterAttachment();
  }

  Future<void> _reloadAfterAttachment() async {
    final occurrence = await widget.services.repository.getOccurrence(
      widget.occurrenceId,
    );
    final attachments = await widget.services.repository.listAttachments(
      widget.occurrenceId,
    );
    if (mounted) {
      setState(() {
        _occurrence = occurrence;
        _attachments = attachments;
      });
    }
  }

  Future<void> _captureLocation() async {
    if (_occurrence!.hasLocation) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Recapturar este ponto?'),
              content: const Text(
                'Isso corrige a coordenada desta ocorrência. Para outro local, crie uma nova ocorrência.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Recapturar'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    setState(() => _capturingLocation = true);
    try {
      final position = await widget.services.location.capture();
      var acknowledged = false;
      if (position.accuracy > 30 && mounted) {
        acknowledged =
            await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Precisão baixa'),
                content: Text(
                  'A precisão retornada foi ${position.accuracy.toStringAsFixed(1)} m. Esse limite de 30 m é apenas uma guarda do protótipo. Deseja usar o ponto?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Não usar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirmar uso'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (position.accuracy > 30 && !acknowledged) return;
      final current = _occurrence!;
      final updated = current.copyWith(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        locationCapturedAt: position.timestamp.toUtc().toIso8601String(),
        locationSource: 'gps',
        lowAccuracyAcknowledged: acknowledged,
        revision: current.revision + 1,
        updatedAt: widget.services.repository.now(),
        status: 'draft',
        clearReviewedAt: true,
        clearFinalizedAt: true,
      );
      await widget.services.repository.saveOccurrence(updated);
      if (mounted) {
        setState(() => _occurrence = updated);
        showMessage(context, 'GPS atual salvo no aparelho.');
      }
    } on LocationFailure catch (error) {
      if (!mounted) return;
      showMessage(context, error.message, error: true);
      if (error.permanentlyDenied) {
        await widget.services.location.openAppSettings();
      }
    } catch (error) {
      if (mounted) {
        showMessage(
          context,
          'Falha ao capturar localização: $error',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  Future<void> _manualDemoLocation() async {
    final enabled =
        await widget.services.repository.getSetting('demo_mode_enabled') ==
        'true';
    if (!enabled || !mounted) {
      if (mounted) {
        showMessage(context, 'Ative o modo de demonstração nas configurações.');
      }
      return;
    }
    final latitude = TextEditingController(
      text: _occurrence!.latitude?.toString() ?? '-27.5954',
    );
    final longitude = TextEditingController(
      text: _occurrence!.longitude?.toString() ?? '-48.5480',
    );
    final values = await showDialog<(double, double)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coordenada fictícia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Uso exclusivo para demonstração; não é uma medição GPS.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: latitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: longitude,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final lat = double.tryParse(latitude.text.replaceAll(',', '.'));
              final lon = double.tryParse(longitude.text.replaceAll(',', '.'));
              if (lat == null ||
                  lon == null ||
                  lat < -90 ||
                  lat > 90 ||
                  lon < -180 ||
                  lon > 180) {
                return;
              }
              Navigator.pop(context, (lat, lon));
            },
            child: const Text('Usar dado fictício'),
          ),
        ],
      ),
    );
    latitude.dispose();
    longitude.dispose();
    if (values == null) return;
    final current = _occurrence!;
    final updated = current.copyWith(
      latitude: values.$1,
      longitude: values.$2,
      locationSource: 'manual_demo',
      locationCapturedAt: widget.services.repository.now(),
      lowAccuracyAcknowledged: false,
      revision: current.revision + 1,
      updatedAt: widget.services.repository.now(),
      status: 'draft',
      clearReviewedAt: true,
      clearFinalizedAt: true,
    );
    await widget.services.repository.saveOccurrence(updated);
    if (mounted) setState(() => _occurrence = updated);
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    final id = widget.services.repository.newId();
    try {
      await widget.services.media.startRecording(id);
      _recordingId = id;
      _recordingStartedAt = DateTime.now();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _recordingStartedAt == null) return;
        final elapsed = DateTime.now().difference(_recordingStartedAt!);
        setState(() => _recordingDuration = elapsed);
        if (elapsed.inSeconds >= 120) unawaited(_stopRecording());
      });
      setState(() {
        _recording = true;
        _recordingDuration = Duration.zero;
      });
    } catch (error) {
      if (mounted) showMessage(context, '$error', error: true);
    }
  }

  Future<void> _stopRecording({bool interrupted = false}) async {
    if (!_recording || _stoppingRecording) return;
    _stoppingRecording = true;
    _recordingTimer?.cancel();
    final duration = DateTime.now().difference(_recordingStartedAt!);
    try {
      final path = await widget.services.media.stopRecording();
      if (path != null && await File(path).exists()) {
        final file = File(path);
        final stat = await file.stat();
        final occurrence = _occurrence!;
        final attachment = Attachment(
          id: _recordingId!,
          occurrenceId: occurrence.id,
          kind: 'audio',
          relativePath: await widget.services.storage.relativePath(file),
          mimeType: 'audio/mp4',
          sizeBytes: stat.size,
          durationMs: duration.inMilliseconds,
          capturedAt: widget.services.repository.now(),
          latitudeSnapshot: occurrence.latitude,
          longitudeSnapshot: occurrence.longitude,
          transcriptionOriginal: null,
          transcriptionEdited: null,
          transcriptionStatus: 'not_requested',
          transcriptionError: null,
          createdAt: widget.services.repository.now(),
        );
        await widget.services.repository.addAttachment(attachment);
      }
      await _reloadAfterAttachment();
      if (interrupted && mounted) {
        showMessage(
          context,
          'A gravação foi encerrada quando o app saiu de foco. Confira o clipe salvo.',
        );
      }
    } catch (error) {
      if (mounted) {
        showMessage(context, 'Falha ao encerrar o áudio: $error', error: true);
      }
    } finally {
      _stoppingRecording = false;
      _recordingId = null;
      _recordingStartedAt = null;
      if (mounted) {
        setState(() {
          _recording = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<bool> _confirmExternalProcessing() async {
    if (await widget.services.repository.getSetting('ai_disclosure_accepted') ==
        'true') {
      return true;
    }
    if (!mounted) return false;
    final accepted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Processamento externo'),
            content: const Text(
              'O áudio ou texto desta ocorrência será enviado ao provedor de IA configurado no backend. Não envie dados sensíveis sem autorização.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Entendi e continuar'),
              ),
            ],
          ),
        ) ??
        false;
    if (accepted) {
      await widget.services.repository.setSetting(
        'ai_disclosure_accepted',
        'true',
      );
    }
    return accepted;
  }

  Future<void> _transcribe(Attachment attachment) async {
    if (attachment.transcriptionStatus == 'processing') return;
    if (attachment.sizeBytes > 10 * 1024 * 1024) {
      showMessage(
        context,
        'Este clipe excede o limite de 10 MiB e não será enviado.',
        error: true,
      );
      return;
    }
    if (!await _confirmExternalProcessing()) return;
    final baseUrl = resolveApiBaseUrl(
      await widget.services.repository.getSetting('api_base_url'),
    );
    var current = attachment.copyWith(
      transcriptionStatus: 'processing',
      clearTranscriptionError: true,
    );
    await widget.services.repository.saveAttachment(current);
    await _reloadAfterAttachment();
    try {
      final file = File(
        await widget.services.storage.absolutePath(attachment.relativePath),
      );
      final transcript = await widget.services.api.transcribe(
        baseUrl: baseUrl,
        occurrence: _occurrence!,
        attachment: attachment,
        file: file,
      );
      current = current.copyWith(
        transcriptionOriginal: transcript,
        transcriptionEdited: transcript,
        transcriptionStatus: 'done',
        clearTranscriptionError: true,
      );
      await widget.services.repository.saveAttachment(
        current,
        touchOccurrence: true,
      );
      if (mounted) {
        showMessage(
          context,
          'Transcrição salva. Revise o texto antes de usar.',
        );
      }
    } on ApiFailure catch (error) {
      current = current.copyWith(
        transcriptionStatus: 'error',
        transcriptionError: error.message,
      );
      await widget.services.repository.saveAttachment(current);
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      await _reloadAfterAttachment();
    }
  }

  void _scheduleTranscriptSave(Attachment attachment, String value) {
    _transcriptTimers[attachment.id]?.cancel();
    _transcriptTimers[attachment.id] = Timer(
      const Duration(milliseconds: 600),
      () async {
        await widget.services.repository.saveAttachment(
          attachment.copyWith(transcriptionEdited: value),
          touchOccurrence: true,
        );
        await _reloadAfterAttachment();
      },
    );
  }

  Future<void> _openReview() async {
    await _saveText();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FormReviewScreen(
          services: widget.services,
          occurrenceId: widget.occurrenceId,
        ),
      ),
    );
    await _load();
  }

  Future<void> _reopenOccurrence() async {
    if (widget.visit.isClosed) {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Reabrir visita e ocorrência?'),
              content: const Text(
                'A edição exige nova revisão antes de finalizar novamente.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Reabrir'),
                ),
              ],
            ),
          ) ??
          false;
      if (!accepted) return;
      await widget.services.repository.setVisitStatus(widget.visit.id, 'open');
    }
    final current = _occurrence!;
    await widget.services.repository.saveOccurrence(
      current.copyWith(
        status: 'draft',
        revision: current.revision + 1,
        updatedAt: widget.services.repository.now(),
        clearReviewedAt: true,
        clearFinalizedAt: true,
      ),
    );
    await _load();
  }

  Future<void> _handleBack() async {
    if (_backInProgress) return;
    if (_recording) {
      showMessage(context, 'Encerre a gravação antes de sair.', error: true);
      return;
    }
    _backInProgress = true;
    await _saveText();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String _durationLabel(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _recordingTimer?.cancel();
    for (final timer in _transcriptTimers.values) {
      timer.cancel();
    }
    if (_recording) unawaited(widget.services.media.stopRecording());
    _written
      ..removeListener(_textChanged)
      ..dispose();
    _postField
      ..removeListener(_textChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = _occurrence;
    return PopScope(
      canPop: _allowPop && !_recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Relatório'),
          actions: [
            if (occurrence != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: StatusPill(
                    label: occurrence.isFinalized ? 'Finalizado' : 'Rascunho',
                    complete: occurrence.isFinalized,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : occurrence == null
              ? const Center(child: Text('Ocorrência não encontrada.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    SectionCard(
                      title: widget.visit.title,
                      subtitle: 'Ocorrência ${shortId(occurrence.id)}',
                      child: Text(
                        '${occurrence.enterprise}\n${occurrence.locationReference.isEmpty ? 'Referência local ainda não preenchida' : occurrence.locationReference}',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: 'Evidência fotográfica',
                      subtitle: 'Obrigatória para finalizar',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_photos.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text('Nenhuma foto adicionada.'),
                            )
                          else
                            SizedBox(
                              height: 106,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _photos.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) => _PhotoTile(
                                  attachment: _photos[index],
                                  services: widget.services,
                                  editable: _editable,
                                  onRemove: () =>
                                      _removeAttachment(_photos[index]),
                                ),
                              ),
                            ),
                          if (_editable) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _choosePhoto,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: const Text('Adicionar foto'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: 'Relato de campo',
                      subtitle:
                          'Texto e áudios coexistem e ficam salvos no aparelho.',
                      trailing: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.save_outlined,
                              color: Color(0xFF279271),
                            ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _written,
                            enabled: _editable,
                            minLines: 4,
                            maxLines: 8,
                            maxLength: 8000,
                            decoration: const InputDecoration(
                              labelText: 'Relato escrito',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_editable)
                            FilledButton.icon(
                              onPressed: _recording
                                  ? () => _stopRecording()
                                  : _startRecording,
                              style: _recording
                                  ? FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade700,
                                    )
                                  : null,
                              icon: Icon(
                                _recording ? Icons.stop : Icons.mic_none,
                              ),
                              label: Text(
                                _recording
                                    ? 'Parar · ${_durationLabel(_recordingDuration.inMilliseconds)} / 02:00'
                                    : 'Gravar áudio',
                              ),
                            ),
                          if (_audios.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ..._audios.map(
                              (audio) => _AudioCard(
                                key: ValueKey(
                                  '${audio.id}-${audio.transcriptionEdited}',
                                ),
                                attachment: audio,
                                editable: _editable,
                                services: widget.services,
                                onRemove: () => _removeAttachment(audio),
                                onTranscribe: () => _transcribe(audio),
                                onTranscriptChanged: (value) =>
                                    _scheduleTranscriptSave(audio, value),
                                durationLabel: _durationLabel,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: 'Localização',
                      subtitle: occurrence.locationSource == 'manual_demo'
                          ? 'DADO FICTÍCIO · não capturado por GPS'
                          : 'Posição atual do aparelho, capturada sob ação explícita.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (occurrence.hasLocation)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Latitude: ${occurrence.latitude!.toStringAsFixed(7)}\n'
                                'Longitude: ${occurrence.longitude!.toStringAsFixed(7)}\n'
                                'Precisão: ${occurrence.accuracyM == null ? 'não informada' : '${occurrence.accuracyM!.toStringAsFixed(1)} m'}\n'
                                'Captura: ${occurrence.locationCapturedAt ?? 'não informada'}',
                              ),
                            )
                          else
                            const Text('Nenhuma coordenada capturada.'),
                          if (_editable) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _capturingLocation
                                  ? null
                                  : _captureLocation,
                              icon: _capturingLocation
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.my_location),
                              label: Text(
                                _capturingLocation
                                    ? 'Obtendo posição atual…'
                                    : 'Capturar localização',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _manualDemoLocation,
                              icon: const Icon(Icons.science_outlined),
                              label: const Text(
                                'Inserir coordenada fictícia (modo demo)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: ExpansionTile(
                        title: const Text('Complemento pós-campo'),
                        subtitle: const Text(
                          'Contexto adicional separado do relato original',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          TextField(
                            controller: _postField,
                            enabled: _editable,
                            minLines: 3,
                            maxLines: 6,
                            maxLength: 4000,
                            decoration: const InputDecoration(
                              labelText: 'Complemento',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_editable) ...[
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _saveText(notify: true),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Salvar rascunho'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _recording ? null : _openReview,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Revisar formulário'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: _reopenOccurrence,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar / complementar'),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.attachment,
    required this.services,
    required this.editable,
    required this.onRemove,
  });

  final Attachment attachment;
  final AppServices services;
  final bool editable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: services.storage.absolutePath(attachment.relativePath),
      builder: (context, snapshot) {
        final file = snapshot.hasData ? File(snapshot.data!) : null;
        return Stack(
          children: [
            InkWell(
              onTap: file == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.file(file, fit: BoxFit.contain),
                        ),
                      ),
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 106,
                  height: 106,
                  color: Colors.blueGrey.shade100,
                  child: file == null
                      ? const Center(child: CircularProgressIndicator())
                      : Image.file(
                          file,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
            ),
            if (editable)
              Positioned(
                right: 2,
                top: 2,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remover foto',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AudioCard extends StatelessWidget {
  const _AudioCard({
    super.key,
    required this.attachment,
    required this.editable,
    required this.services,
    required this.onRemove,
    required this.onTranscribe,
    required this.onTranscriptChanged,
    required this.durationLabel,
  });

  final Attachment attachment;
  final bool editable;
  final AppServices services;
  final VoidCallback onRemove;
  final VoidCallback onTranscribe;
  final ValueChanged<String> onTranscriptChanged;
  final String Function(int) durationLabel;

  @override
  Widget build(BuildContext context) {
    final processing = attachment.transcriptionStatus == 'processing';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Reproduzir áudio',
                onPressed: () => services.media.play(attachment.relativePath),
                icon: const Icon(Icons.play_circle_outline),
              ),
              Expanded(
                child: Text(
                  'Áudio · ${durationLabel(attachment.durationMs ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (editable)
                IconButton(
                  tooltip: 'Remover áudio',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: processing ? null : onTranscribe,
            icon: processing
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.transcribe_outlined),
            label: Text(
              attachment.transcriptionOriginal == null
                  ? 'Transcrever'
                  : 'Transcrever novamente',
            ),
          ),
          if (attachment.transcriptionError != null) ...[
            const SizedBox(height: 8),
            Text(
              attachment.transcriptionError!,
              style: TextStyle(color: Colors.red.shade800),
            ),
          ],
          if (attachment.transcriptionOriginal != null) ...[
            const SizedBox(height: 10),
            TextFormField(
              initialValue:
                  attachment.transcriptionEdited ??
                  attachment.transcriptionOriginal,
              enabled: editable,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Transcrição revisável',
                helperText: 'O texto original também permanece preservado.',
              ),
              onChanged: onTranscriptChanged,
            ),
          ],
        ],
      ),
    );
  }
}
