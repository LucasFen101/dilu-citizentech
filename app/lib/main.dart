import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Preferencias.carregar();
  runApp(const AlertaEnchenteApp());
}

class AlertaEnchenteApp extends StatelessWidget {
  const AlertaEnchenteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dilu',
      debugShowCheckedModeBanner: false,
      theme: construirTema(),
      // modo texto grande: aumenta as letras do app inteiro
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: Preferencias.textoGrande,
        builder: (_, grande, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(grande ? 1.3 : 1.0)),
          child: child!,
        ),
      ),
      home: const _Porteiro(),
    );
  }
}

/// Decide entre tela de login e app, conforme a sessão salva.
class _Porteiro extends StatefulWidget {
  const _Porteiro();

  @override
  State<_Porteiro> createState() => _PorteiroState();
}

enum _Estado { carregando, deslogado, logado }

class _PorteiroState extends State<_Porteiro> {
  _Estado _estado = _Estado.carregando;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  /// Restaura o token salvo e confere se ainda vale.
  Future<void> _iniciar() async {
    final temToken = await Sessao.restaurar();
    if (!temToken) return _mudar(_Estado.deslogado);
    try {
      await Api.eu();
      _mudar(_Estado.logado);
    } on ApiException catch (e) {
      if (e.status == 401) await Sessao.sair();
      // sem rede: mantém logado só se o token existir e o erro não for 401
      _mudar(e.status == 401 ? _Estado.deslogado : _Estado.logado);
    }
  }

  void _mudar(_Estado e) {
    if (mounted) setState(() => _estado = e);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_estado) {
      _Estado.carregando => const Scaffold(body: Center(child: CircularProgressIndicator())),
      _Estado.deslogado => LoginScreen(aoEntrar: () => _mudar(_Estado.logado)),
      _Estado.logado => HomeShell(aoSair: () async {
          await Sessao.sair();
          _mudar(_Estado.deslogado);
        }),
    };
  }
}
