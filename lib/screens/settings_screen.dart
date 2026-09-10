import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _tileUrl = TextEditingController();
  final _tileAttribution = TextEditingController();
  bool _demoEnabled = false;
  bool _loading = true;
  bool _testing = false;
  bool _creatingDemo = false;
  HealthResult? _health;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = widget.services.repository;
    _url.text = resolveApiBaseUrl(await repository.getSetting('api_base_url'));
    _tileUrl.text =
        await repository.getSetting('tile_url_template') ??
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    _tileAttribution.text =
        await repository.getSetting('tile_attribution') ??
        'OpenStreetMap contributors';
    _demoEnabled = await repository.getSetting('demo_mode_enabled') == 'true';
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _save() async {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      showMessage(
        context,
        'Informe uma URL completa, como $defaultApiBaseUrl.',
        error: true,
      );
      return false;
    }
    final tileValue = _tileUrl.text.trim();
    if (!tileValue.startsWith('http') ||
        !tileValue.contains('{z}') ||
        !tileValue.contains('{x}') ||
        !tileValue.contains('{y}')) {
      showMessage(
        context,
        'A fonte de tiles deve ser uma URL contendo {z}, {x} e {y}.',
        error: true,
      );
      return false;
    }
    if (_tileAttribution.text.trim().isEmpty) {
      showMessage(
        context,
        'Informe a atribuição da fonte do mapa.',
        error: true,
      );
      return false;
    }
    await widget.services.repository.setSetting('api_base_url', value);
    await widget.services.repository.setSetting('tile_url_template', tileValue);
    await widget.services.repository.setSetting(
      'tile_attribution',
      _tileAttribution.text.trim(),
    );
    await widget.services.repository.setSetting(
      'demo_mode_enabled',
      _demoEnabled.toString(),
    );
    if (mounted) showMessage(context, 'Configuração salva no aparelho.');
    return true;
  }

  Future<void> _test() async {
    if (!await _save()) return;
    setState(() {
      _testing = true;
      _health = null;
      _error = null;
    });
    try {
      final health = await widget.services.api.health(_url.text);
      if (mounted) setState(() => _health = health);
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _createDemo() async {
    if (!_demoEnabled || _creatingDemo) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Criar conjunto fictício?'),
            content: const Text(
              'Será criada uma visita com quatro ocorrências e coordenadas manuais, todas identificadas como demonstração.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Criar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _creatingDemo = true);
    await widget.services.repository.createDemoVisit();
    if (mounted) {
      setState(() => _creatingDemo = false);
      showMessage(context, 'Visita fictícia criada e identificada na lista.');
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _tileUrl.dispose();
    _tileAttribution.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuração técnica')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'API de processamento',
                    subtitle: 'A chave de IA fica somente no backend.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'Endereço da API',
                            hintText: defaultApiBaseUrl,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_find),
                          label: const Text('Salvar e testar conexão'),
                        ),
                        if (_health != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'API acessível: ${_health!.reachable ? 'sim' : 'não'}\n'
                            'IA configurada: ${_health!.aiConfigured ? 'sim' : 'não'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'Windows: use 127.0.0.1. Emulador Android: 10.0.2.2 aponta para o notebook. Em celular físico, use o IP do notebook na mesma rede.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Mapa-base',
                    subtitle:
                        'Os pontos locais continuam disponíveis se os tiles falharem.',
                    child: Column(
                      children: [
                        TextField(
                          controller: _tileUrl,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Modelo de URL dos tiles',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _tileAttribution,
                          decoration: const InputDecoration(
                            labelText: 'Atribuição visível',
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _testing ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Salvar configuração do mapa'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Modo de demonstração',
                    subtitle:
                        'Desativado por padrão. Nunca representa coleta real.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Permitir dados fictícios'),
                          subtitle: const Text(
                            'Habilita coordenadas manuais e o conjunto de exemplo.',
                          ),
                          value: _demoEnabled,
                          onChanged: (value) async {
                            setState(() => _demoEnabled = value);
                            await widget.services.repository.setSetting(
                              'demo_mode_enabled',
                              value.toString(),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          onPressed: _demoEnabled && !_creatingDemo
                              ? _createDemo
                              : null,
                          icon: const Icon(Icons.science_outlined),
                          label: Text(
                            _creatingDemo
                                ? 'Criando…'
                                : 'Criar visita fictícia com 4 pontos',
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
