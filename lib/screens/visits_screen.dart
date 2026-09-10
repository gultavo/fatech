import 'package:flutter/material.dart';

import '../controllers/visits_controller.dart';
import '../models/domain.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import 'settings_screen.dart';
import 'visit_detail_screen.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  late final VisitsController controller = VisitsController(
    widget.services.repository,
  )..addListener(_changed);

  @override
  void initState() {
    super.initState();
    controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _openVisit(Visit visit) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VisitDetailScreen(services: widget.services, visitId: visit.id),
      ),
    );
    await controller.load();
  }

  Future<void> _newVisit() async {
    final visit = await showDialog<Visit>(
      context: context,
      builder: (_) => _NewVisitDialog(services: widget.services),
    );
    if (visit != null) {
      await controller.load();
      if (mounted) await _openVisit(visit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAtech · Visitas'),
        actions: [
          IconButton(
            tooltip: 'Configuração da API',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(services: widget.services),
                ),
              );
              await controller.load();
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.load,
          child: controller.loading && controller.visits.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : controller.error != null
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(controller.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: controller.load,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                )
              : controller.visits.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(32),
                  children: const [
                    SizedBox(height: 80),
                    Icon(Icons.hiking, size: 72, color: Color(0xFF1C70AD)),
                    SizedBox(height: 20),
                    Text(
                      'Nenhuma visita registrada',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Crie uma visita para reunir ocorrências, evidências e pontos do mapa no mesmo registro.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: controller.visits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final visit = controller.visits[index];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          visit.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${formatDate(visit.visitDate)} · ${visit.visitType}\n'
                            '${visit.occurrenceCount} ocorrência(s)${visit.isDemo ? ' · DADOS FICTÍCIOS' : ''}',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openVisit(visit),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newVisit,
        icon: const Icon(Icons.add),
        label: const Text('Nova visita'),
      ),
    );
  }
}

class _NewVisitDialog extends StatefulWidget {
  const _NewVisitDialog({required this.services});
  final AppServices services;

  @override
  State<_NewVisitDialog> createState() => _NewVisitDialogState();
}

class _NewVisitDialogState extends State<_NewVisitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _enterprise = TextEditingController();
  DateTime _date = DateTime.now();
  String _type = 'Rotina';
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _enterprise.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final visit = await widget.services.repository.createVisit(
      title: _title.text,
      visitDate:
          '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      visitType: _type,
      enterprise: _enterprise.text,
    );
    if (mounted) Navigator.of(context).pop(visit);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova visita'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o título.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _enterprise,
                  decoration: const InputDecoration(
                    labelText: 'Empreendimento',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o empreendimento.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const ['Rotina', 'Atendimento de chamado', 'Outro']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _type = value!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data da visita'),
                  subtitle: Text(
                    '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (selected != null) setState(() => _date = selected);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Criar'),
        ),
      ],
    );
  }
}
