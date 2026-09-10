import 'dart:io';

import 'package:flutter/material.dart';

import '../models/domain.dart';
import '../services/app_services.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

class FormReviewScreen extends StatefulWidget {
  const FormReviewScreen({
    super.key,
    required this.services,
    required this.occurrenceId,
  });

  final AppServices services;
  final String occurrenceId;

  @override
  State<FormReviewScreen> createState() => _FormReviewScreenState();
}

class _FormReviewScreenState extends State<FormReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _enterprise = TextEditingController();
  final _locationReference = TextEditingController();
  final _environmentalOccurrence = TextEditingController();
  final _technicalOpinion = TextEditingController();
  Occurrence? _occurrence;
  List<Attachment> _attachments = [];
  String _visitDate = '';
  String _visitType = 'Rotina';
  bool _reviewed = false;
  bool _loading = true;
  bool _busy = false;
  bool _initializing = false;
  bool _allowPop = false;
  bool _leaving = false;
  final Map<String, Map<String, dynamic>> _activeSuggestions = {};

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _enterprise,
      _locationReference,
      _environmentalOccurrence,
      _technicalOpinion,
    ]) {
      controller.addListener(_manualEdit);
    }
    _load();
  }

  Future<void> _load() async {
    final occurrence = await widget.services.repository.getOccurrence(
      widget.occurrenceId,
    );
    final attachments = await widget.services.repository.listAttachments(
      widget.occurrenceId,
    );
    if (!mounted || occurrence == null) return;
    setState(() {
      _occurrence = occurrence;
      _attachments = attachments;
      _visitDate = occurrence.visitDate;
      _visitType = occurrence.visitType;
      _reviewed = occurrence.reviewedAt != null;
      _initializing = true;
      _enterprise.text = occurrence.enterprise;
      _locationReference.text = occurrence.locationReference;
      _environmentalOccurrence.text = occurrence.environmentalOccurrence;
      _technicalOpinion.text = occurrence.technicalOpinion;
      _initializing = false;
      _loading = false;
    });
  }

  void _manualEdit() {
    if (_initializing || !mounted) return;
    setState(() => _reviewed = false);
  }

  String _valueFor(String key) => switch (key) {
    'visit_date' => _visitDate,
    'visit_type' => _visitType,
    'enterprise' => _enterprise.text,
    'location_reference' => _locationReference.text,
    'environmental_occurrence' => _environmentalOccurrence.text,
    'technical_opinion' => _technicalOpinion.text,
    _ => '',
  };

  void _applyValue(String key, String value) {
    _initializing = true;
    switch (key) {
      case 'visit_date':
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
          _visitDate = value;
        }
      case 'visit_type':
        if (const [
          'Rotina',
          'Atendimento de chamado',
          'Outro',
        ].contains(value)) {
          _visitType = value;
        }
      case 'enterprise':
        _enterprise.text = value;
      case 'location_reference':
        _locationReference.text = value;
      case 'environmental_occurrence':
        _environmentalOccurrence.text = value;
      case 'technical_opinion':
        _technicalOpinion.text = value;
    }
    _initializing = false;
    _reviewed = false;
  }

  List<Map<String, String>> _sources() {
    final result = <Map<String, String>>[];
    final occurrence = _occurrence!;
    if (occurrence.writtenReport.trim().isNotEmpty) {
      result.add({'id': 'written_report', 'text': occurrence.writtenReport});
    }
    for (final audio in _attachments.where((item) => item.isAudio)) {
      final text = audio.transcriptionEdited?.trim().isNotEmpty == true
          ? audio.transcriptionEdited!
          : audio.transcriptionOriginal;
      if (text != null && text.trim().isNotEmpty) {
        result.add({'id': 'audio:${audio.id}', 'text': text});
      }
    }
    if (occurrence.postFieldNotes.trim().isNotEmpty) {
      result.add({'id': 'post_field_notes', 'text': occurrence.postFieldNotes});
    }
    return result;
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
              'Os textos desta ocorrência serão enviados ao provedor de IA configurado no backend. Não envie dados sensíveis sem autorização.',
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

  Future<void> _suggest() async {
    final sources = _sources();
    if (sources.isEmpty) {
      showMessage(
        context,
        'Escreva um relato ou transcreva ao menos um áudio antes de solicitar sugestões.',
        error: true,
      );
      return;
    }
    if (!await _confirmExternalProcessing()) return;
    final occurrence = _occurrence!;
    final inputHash = sourcesHash(sources);
    final processing = occurrence.copyWith(
      extractionStatus: 'processing',
      extractionInputHash: inputHash,
      updatedAt: widget.services.repository.now(),
      clearExtractionError: true,
    );
    await widget.services.repository.saveOccurrence(processing);
    setState(() {
      _occurrence = processing;
      _busy = true;
    });
    try {
      final baseUrl = resolveApiBaseUrl(
        await widget.services.repository.getSetting('api_base_url'),
      );
      final response = await widget.services.api.extract(
        baseUrl: baseUrl,
        occurrence: occurrence,
        sources: sources,
        inputHash: inputHash,
      );
      final fresh = await widget.services.repository.getOccurrence(
        occurrence.id,
      );
      if (fresh == null ||
          response.occurrenceId != fresh.id ||
          response.revision != fresh.revision ||
          response.inputHash != inputHash ||
          fresh.extractionInputHash != inputHash) {
        throw const ApiFailure(
          'STALE_RESPONSE',
          'O relato mudou durante o processamento. A resposta não foi aplicada; solicite novamente.',
        );
      }
      final suggested = fresh.copyWith(
        extractionStatus: 'suggested',
        clearExtractionError: true,
        updatedAt: widget.services.repository.now(),
      );
      await widget.services.repository.saveOccurrence(suggested);
      if (!mounted) return;
      final selected = await showDialog<Set<String>>(
        context: context,
        builder: (_) =>
            _SuggestionDialog(fields: response.fields, currentValue: _valueFor),
      );
      if (selected != null) {
        setState(() {
          _occurrence = suggested;
          for (final key in selected) {
            final suggestion = Map<String, dynamic>.from(
              response.fields[key] as Map,
            );
            final value = suggestion['value'] as String?;
            if (value != null) {
              _applyValue(key, value);
              _activeSuggestions[key] = suggestion;
            }
          }
        });
      }
      if (response.warnings.isNotEmpty && mounted) {
        showMessage(context, response.warnings.join(' · '));
      }
    } on ApiFailure catch (error) {
      final fresh = await widget.services.repository.getOccurrence(
        occurrence.id,
      );
      if (fresh != null) {
        final failed = fresh.copyWith(
          extractionStatus: 'error',
          extractionError: error.message,
          updatedAt: widget.services.repository.now(),
        );
        await widget.services.repository.saveOccurrence(failed);
        if (mounted) setState(() => _occurrence = failed);
      }
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Occurrence _buildUpdated({required bool finalize}) {
    final current = _occurrence!;
    final changed =
        _visitDate != current.visitDate ||
        _visitType != current.visitType ||
        _enterprise.text.trim() != current.enterprise ||
        _locationReference.text.trim() != current.locationReference ||
        _environmentalOccurrence.text.trim() !=
            current.environmentalOccurrence ||
        _technicalOpinion.text.trim() != current.technicalOpinion;
    final metadata = Map<String, dynamic>.from(current.fieldMetadata);
    final changedFields = <String, bool>{
      'visit_date': _visitDate != current.visitDate,
      'visit_type': _visitType != current.visitType,
      'enterprise': _enterprise.text.trim() != current.enterprise,
      'location_reference':
          _locationReference.text.trim() != current.locationReference,
      'environmental_occurrence':
          _environmentalOccurrence.text.trim() !=
          current.environmentalOccurrence,
      'technical_opinion':
          _technicalOpinion.text.trim() != current.technicalOpinion,
    };
    for (final entry in changedFields.entries) {
      if (entry.value && !_activeSuggestions.containsKey(entry.key)) {
        metadata[entry.key] = {
          'origin': 'manual',
          'source_id': null,
          'evidence': null,
          'reviewed': finalize,
        };
      }
    }
    for (final entry in _activeSuggestions.entries) {
      metadata[entry.key] = {
        'origin': 'ai_suggestion',
        'source_id': entry.value['source_id'],
        'evidence': entry.value['evidence'],
        'reviewed': finalize,
      };
    }
    if (finalize) {
      for (final entry in metadata.entries.toList()) {
        final value = Map<String, dynamic>.from(entry.value as Map);
        value['reviewed'] = true;
        metadata[entry.key] = value;
      }
    }
    final timestamp = widget.services.repository.now();
    return current.copyWith(
      status: finalize ? 'finalized' : 'draft',
      visitDate: _visitDate,
      visitType: _visitType,
      enterprise: _enterprise.text.trim(),
      locationReference: _locationReference.text.trim(),
      environmentalOccurrence: _environmentalOccurrence.text.trim(),
      technicalOpinion: _technicalOpinion.text.trim(),
      fieldMetadata: metadata,
      extractionStatus: finalize && current.extractionStatus == 'suggested'
          ? 'reviewed'
          : current.extractionStatus,
      revision: current.revision + (changed ? 1 : 0),
      updatedAt: timestamp,
      reviewedAt: finalize ? timestamp : null,
      finalizedAt: finalize ? timestamp : null,
      clearReviewedAt: !finalize,
      clearFinalizedAt: !finalize,
    );
  }

  Future<void> _saveDraft() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.services.repository.saveOccurrence(
      _buildUpdated(finalize: false),
    );
    if (mounted) {
      setState(() => _busy = false);
      showMessage(context, 'Rascunho salvo no aparelho.');
    }
    await _load();
  }

  Future<void> _finalize() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    final missing = <String>[];
    final occurrence = _occurrence!;
    if (!occurrence.hasLocation) missing.add('localização');
    if ((occurrence.accuracyM ?? 0) > 30 &&
        !occurrence.lowAccuracyAcknowledged) {
      missing.add('confirmação da baixa precisão');
    }
    var validPhotoCount = 0;
    for (final photo in _attachments.where((item) => item.isPhoto)) {
      final path = await widget.services.storage.absolutePath(
        photo.relativePath,
      );
      if (await File(path).exists()) validPhotoCount++;
    }
    if (validPhotoCount == 0) missing.add('ao menos uma foto salva');
    if (!_reviewed) missing.add('confirmação da revisão humana');
    if (missing.isNotEmpty) {
      if (mounted) {
        showMessage(
          context,
          'Para finalizar, falta: ${missing.join(', ')}.',
          error: true,
        );
      }
      return;
    }
    setState(() => _busy = true);
    await widget.services.repository.saveOccurrence(
      _buildUpdated(finalize: true),
    );
    if (mounted) {
      showMessage(context, 'Ocorrência finalizada e salva no aparelho.');
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _leave() async {
    if (_busy) {
      showMessage(context, 'Aguarde o processamento atual terminar.');
      return;
    }
    if (_leaving) return;
    _leaving = true;
    try {
      if (_occurrence != null) {
        await widget.services.repository.saveOccurrence(
          _buildUpdated(finalize: false),
        );
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (error) {
      _leaving = false;
      if (mounted) {
        showMessage(
          context,
          'Não foi possível salvar o rascunho: $error',
          error: true,
        );
      }
    }
  }

  Widget _fieldWithSuggestion({
    required String keyName,
    required TextEditingController controller,
    required String label,
    int minLines = 1,
    int maxLines = 1,
    bool required = false,
  }) {
    final suggestion = _activeSuggestions[keyName];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLines > 1 ? 8000 : 500,
          decoration: InputDecoration(
            labelText: '$label${required ? ' *' : ''}',
            helperText: suggestion == null ? null : 'Sugestão da IA — revisar',
            helperStyle: const TextStyle(
              color: Color(0xFF279271),
              fontWeight: FontWeight.w700,
            ),
          ),
          validator: required
              ? (value) => value == null || value.trim().isEmpty
                    ? 'Campo obrigatório.'
                    : null
              : null,
          onChanged: (_) {
            if (_activeSuggestions.remove(keyName) != null) setState(() {});
          },
        ),
        if (suggestion?['evidence'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Trecho de apoio: “${suggestion!['evidence']}”',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _enterprise,
      _locationReference,
      _environmentalOccurrence,
      _technicalOpinion,
    ]) {
      controller
        ..removeListener(_manualEdit)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = _occurrence;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Revisar ocorrência')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : occurrence == null
              ? const Center(child: Text('Ocorrência não encontrada.'))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      const Text(
                        'Etapa 2 de 2',
                        style: TextStyle(
                          color: Color(0xFF1C70AD),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Confira antes de finalizar',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      SectionCard(
                        title: 'Preenchimento assistido',
                        subtitle:
                            'A IA apenas sugere com base nos textos desta ocorrência.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _suggest,
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Sugerir preenchimento'),
                            ),
                            if (occurrence.extractionError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                occurrence.extractionError!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SectionCard(
                        title: 'Formulário reduzido',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Data da vistoria *'),
                              subtitle: Text(formatDate(_visitDate)),
                              trailing: const Icon(
                                Icons.calendar_month_outlined,
                              ),
                              onTap: () async {
                                final parsed = DateTime.tryParse(_visitDate);
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: parsed ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (selected != null) {
                                  setState(() {
                                    _visitDate =
                                        '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
                                    _activeSuggestions.remove('visit_date');
                                    _reviewed = false;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _visitType,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de vistoria *',
                              ),
                              items:
                                  const [
                                        'Rotina',
                                        'Atendimento de chamado',
                                        'Outro',
                                      ]
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) => setState(() {
                                _visitType = value!;
                                _activeSuggestions.remove('visit_type');
                                _reviewed = false;
                              }),
                            ),
                            const SizedBox(height: 12),
                            _fieldWithSuggestion(
                              keyName: 'enterprise',
                              controller: _enterprise,
                              label: 'Empreendimento',
                              required: true,
                            ),
                            const SizedBox(height: 12),
                            _fieldWithSuggestion(
                              keyName: 'location_reference',
                              controller: _locationReference,
                              label: 'Localização (referência textual)',
                            ),
                            const SizedBox(height: 12),
                            _fieldWithSuggestion(
                              keyName: 'environmental_occurrence',
                              controller: _environmentalOccurrence,
                              label: 'Ocorrência ambiental',
                              minLines: 3,
                              maxLines: 7,
                              required: true,
                            ),
                            const SizedBox(height: 12),
                            _fieldWithSuggestion(
                              keyName: 'technical_opinion',
                              controller: _technicalOpinion,
                              label: 'Parecer técnico (opcional)',
                              minLines: 3,
                              maxLines: 7,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SectionCard(
                        title: 'Evidências e coordenada',
                        child: Text(
                          '${_attachments.where((item) => item.isPhoto).length} foto(s) · '
                          '${_attachments.where((item) => item.isAudio).length} áudio(s)\n'
                          '${occurrence.hasLocation ? '${occurrence.latitude!.toStringAsFixed(6)}, ${occurrence.longitude!.toStringAsFixed(6)}${occurrence.locationSource == 'manual_demo' ? ' · DADO FICTÍCIO' : ''}' : 'Sem coordenada'}',
                        ),
                      ),
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        value: _reviewed,
                        onChanged: (value) =>
                            setState(() => _reviewed = value!),
                        title: const Text(
                          'Revisei as informações deste registro',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'A confirmação humana é obrigatória; a IA não finaliza a ocorrência.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _saveDraft,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Salvar rascunho'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _busy ? null : _finalize,
                        icon: const Icon(Icons.task_alt),
                        label: const Text('Finalizar ocorrência'),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SuggestionDialog extends StatefulWidget {
  const _SuggestionDialog({required this.fields, required this.currentValue});

  final Map<String, dynamic> fields;
  final String Function(String) currentValue;

  @override
  State<_SuggestionDialog> createState() => _SuggestionDialogState();
}

class _SuggestionDialogState extends State<_SuggestionDialog> {
  late final Map<String, bool> selected = {
    for (final entry in widget.fields.entries)
      if ((entry.value as Map)['value'] != null)
        entry.key: widget.currentValue(entry.key).trim().isEmpty,
  };

  static const labels = {
    'visit_date': 'Data da vistoria',
    'visit_type': 'Tipo de vistoria',
    'enterprise': 'Empreendimento',
    'location_reference': 'Referência local',
    'environmental_occurrence': 'Ocorrência ambiental',
    'technical_opinion': 'Parecer técnico',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Revisar sugestões'),
      content: SizedBox(
        width: 480,
        child: selected.isEmpty
            ? const Text(
                'A IA não encontrou campos apoiados pelos relatos enviados.',
              )
            : ListView(
                shrinkWrap: true,
                children: selected.keys.map((key) {
                  final value = Map<String, dynamic>.from(
                    widget.fields[key] as Map,
                  );
                  final hasExisting = widget
                      .currentValue(key)
                      .trim()
                      .isNotEmpty;
                  return CheckboxListTile(
                    value: selected[key],
                    onChanged: (checked) =>
                        setState(() => selected[key] = checked!),
                    title: Text(labels[key] ?? key),
                    subtitle: Text(
                      '${value['value']}\nTrecho: “${value['evidence']}”${hasExisting ? '\nHá um valor atual; marque apenas se quiser substituí-lo.' : ''}',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            selected.entries
                .where((entry) => entry.value)
                .map((entry) => entry.key)
                .toSet(),
          ),
          child: const Text('Aplicar selecionadas'),
        ),
      ],
    );
  }
}
