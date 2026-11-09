import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'clima_screen.dart';
import 'conta_screen.dart';
import 'enchentes_screen.dart';
import 'notifications_screen.dart';
import 'shelters_screen.dart';
import 'sos_screen.dart';

/// Estrutura principal: barra de navegação com as 4 áreas do app.
/// No topo ficam o texto grande, a conta do morador e o sino de avisos.
class HomeShell extends StatefulWidget {
  final Future<void> Function() aoSair;
  const HomeShell({super.key, required this.aoSair});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _aba = 0;
  int _naoLidas = 0;
  String? _inicial; // primeira letra do nome, para o botão da conta
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _atualizarBadge();
    _carregarNome();
    // confere novos avisos a cada minuto
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _atualizarBadge());
  }

  @override
  void dispose() {
    _timer?.cancel(); // evita timer vivo depois de sair da tela
    super.dispose();
  }

  Future<void> _atualizarBadge() async {
    try {
      final lista = await Api.notificacoes();
      if (mounted) setState(() => _naoLidas = lista.where((n) => !n.lida).length);
    } on ApiException catch (e) {
      if (e.status == 401) await widget.aoSair();
    }
  }

  Future<void> _carregarNome() async {
    try {
      final nome = ((await Api.eu())['nome'] as String?)?.trim() ?? '';
      if (mounted && nome.isNotEmpty) setState(() => _inicial = nome.characters.first.toUpperCase());
    } on ApiException catch (_) {
      // sem nome: o botão mostra o ícone genérico
    }
  }

  Future<void> _abrirAvisos() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Avisos')),
          body: NotificationsScreen(aoLer: _atualizarBadge),
        ),
      ),
    );
    _atualizarBadge();
  }

  Future<void> _abrirConta() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Minha conta')),
          body: ContaScreen(aoSair: () async {
            // fecha a tela da conta antes de voltar para o login
            Navigator.of(ctx).popUntil((r) => r.isFirst);
            await widget.aoSair();
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titulos = ['Dilu', 'Clima', 'Abrigos e dicas', 'Emergência'];
    const telas = <Widget>[
      EnchentesScreen(),
      ClimaScreen(),
      SheltersScreen(),
      SosScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: _aba == 0 ? const DiluLogo(tamanho: 32) : Text(titulos[_aba]),
        actions: [
          const BotaoTextoGrande(),
          IconButton(
            tooltip: 'Minha conta',
            icon: _inicial == null
                ? const Icon(Icons.account_circle_outlined)
                : CircleAvatar(
                    radius: 14,
                    backgroundColor: kTinta,
                    child: Text(_inicial!, style: const TextStyle(color: kPapel, fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
            onPressed: _abrirConta,
          ),
          IconButton(
            tooltip: _naoLidas > 0 ? 'Avisos ($_naoLidas novos)' : 'Avisos',
            icon: Badge(
              isLabelVisible: _naoLidas > 0,
              label: Text('$_naoLidas'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: _abrirAvisos,
          ),
        ],
      ),
      // sem IndexedStack: cada aba recarrega os dados ao ser aberta e libera memória ao sair
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        // só a aba nova é desenhada no fim da troca; a antiga sai da memória
        layoutBuilder: (atual, _) => atual ?? const SizedBox.shrink(),
        transitionBuilder: (filho, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(anim), child: filho),
        ),
        child: KeyedSubtree(key: ValueKey(_aba), child: telas[_aba]),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLinha))),
        child: NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: (i) => setState(() => _aba = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.flood_outlined), selectedIcon: Icon(Icons.flood), label: 'Enchentes'),
            NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud), label: 'Clima'),
            NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work), label: 'Abrigos'),
            NavigationDestination(
              icon: Icon(Icons.crisis_alert_outlined, color: kBrasa),
              selectedIcon: Icon(Icons.crisis_alert, color: kBrasa),
              label: 'SOS',
            ),
          ],
        ),
      ),
    );
  }
}
