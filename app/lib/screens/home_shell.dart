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

/// Estrutura principal: barra de navegação com as 5 áreas do app.
/// Os avisos ficam no sino, no topo da tela; sair da conta fica na aba Conta.
class HomeShell extends StatefulWidget {
  final Future<void> Function() aoSair;
  const HomeShell({super.key, required this.aoSair});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _aba = 0;
  int _naoLidas = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _atualizarBadge();
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

  @override
  Widget build(BuildContext context) {
    const titulos = ['Dilu', 'Clima', 'Abrigos e dicas', 'Emergência', 'Minha conta'];
    final telas = <Widget>[
      const EnchentesScreen(),
      const ClimaScreen(),
      const SheltersScreen(),
      const SosScreen(),
      ContaScreen(aoSair: widget.aoSair),
    ];
    return Scaffold(
      appBar: AppBar(
        title: _aba == 0 ? const DiluLogo(tamanho: 32) : Text(titulos[_aba]),
        actions: [
          const BotaoTextoGrande(),
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
      body: telas[_aba],
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
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Conta'),
          ],
        ),
      ),
    );
  }
}
