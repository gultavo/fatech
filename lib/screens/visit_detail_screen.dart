import 'package:flutter/material.dart';

import '../models/domain.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import 'map_screen.dart';
import 'occurrence_screen.dart';

class VisitDetailScreen extends StatefulWidget {
  const VisitDetailScreen({
    super.key,
    required this.services,
    required this.visitId,
  });

  final AppServices services;
  final String visitId;

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  Visit? _visit;
  List<Occurrence> _occurrences = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final visit = await widget.services.repository.getVisit(widget.visitId);
    final occurrences = await widget.services.repository.listOccurrences(
      widget.visitId,
    );
    if (mounted) {
      setState(() {
        _visit = visit;
        _occurrences = occurrences;
        _loading = false;
      });
    }
  }

  Future<void> _openOccurrence(Occurrence occurrence) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OccurrenceScreen(
          services: widget.services,
          visit: _visit!,
          occurrenceId: occurrence.id,
        ),
      ),
    );
    await _load();
  }

  Future<void> _newOccurrence() async {
    if (_visit!.isClosed) {
      showMessage(
        context,
        'Reabra a visita antes de adicionar uma ocorrência.',
      );
      return;
    }
    final occurrence = await widget.services.repository.createOccurrence(
      _visit!,
    );
    if (mounted) await _openOccurrence(occurrence);
  }

  Future<void> _toggleClosed() async {
    final visit = _visit!;
    if (visit.isClosed) {
      final confirmed = await _confirm(
        'Reabrir visita?',
        'Isso permitirá criar e editar ocorrências novamente.',
      );
      if (!confirmed) return;
      await widget.services.repository.setVisitStatus(visit.id, 'open');
      await _load();
      return;
    }
    if (_occurrences.isEmpty || _occurrences.any((item) => !item.isFinalized)) {
      if (mounted) {
        showMessage(
          context,
          'Para concluir, finalize todas as ocorrências da visita.',
          error: true,
        );
      }
      return;
    }
    await widget.services.repository.setVisitStatus(visit.id, 'closed');
    await _load();
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    return Scaffold(
      appBar: AppBar(title: Text(visit?.title ?? 'Visita')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : visit == null
            ? const Center(child: Text('Visita não encontrada.'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    visit.enterprise,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                StatusPill(
                                  label: visit.isClosed
                                      ? 'Concluída'
                                      : 'Em campo',
                                  complete: visit.isClosed,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${formatDate(visit.visitDate)} · ${visit.visitType} · ${_occurrences.length} ocorrência(s)',
                            ),
                            if (visit.isDemo) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'DADOS FICTÍCIOS PARA DEMONSTRAÇÃO',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _newOccurrence,
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('Nova ocorrência'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => MapScreen(
                                    services: widget.services,
                                    visit: visit,
                                  ),
                                ),
                              );
                              await _load();
                            },
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Mapa / KML'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Ocorrências',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_occurrences.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Registre cada local observado como uma ocorrência separada.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ..._occurrences.asMap().entries.map((entry) {
                        final item = entry.value;
                        final description = item.environmentalOccurrence.isEmpty
                            ? (item.writtenReport.isEmpty
                                  ? 'Descrição ainda não preenchida'
                                  : item.writtenReport)
                            : item.environmentalOccurrence;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(14),
                              leading: CircleAvatar(
                                child: Text('${entry.key + 1}'),
                              ),
                              title: Text(
                                'Ocorrência ${shortId(item.id)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '$description\n${item.hasLocation ? '${item.latitude!.toStringAsFixed(6)}, ${item.longitude!.toStringAsFixed(6)}' : 'Sem coordenada'}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: StatusPill(
                                label: item.isFinalized
                                    ? 'Finalizada'
                                    : 'Rascunho',
                                complete: item.isFinalized,
                              ),
                              onTap: () => _openOccurrence(item),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _toggleClosed,
                      icon: Icon(
                        visit.isClosed ? Icons.lock_open : Icons.task_alt,
                      ),
                      label: Text(
                        visit.isClosed ? 'Reabrir visita' : 'Concluir visita',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
