import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'lugares_screen.dart';

/// Avisos: alertas do clima agora + avisos gerados pelo banco
/// (risco do bairro subiu, vizinho pediu ajuda...).
class NotificationsScreen extends StatefulWidget {
  final Future<void> Function() aoLer;
  const NotificationsScreen({super.key, required this.aoLer});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Notificacao> _lista = [];
  Clima? _clima;
  bool _carregando = true;
  List<(Lugar, List<AlertaClima>)>? _lugares; // alertas de cada lugar salvo

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarClima();
    _carregarLugares();
  }

  /// Alertas de clima e de chuva acumulada para cada lugar que o morador acompanha.
  Future<void> _carregarLugares() async {
    try {
      final lugares = await Api.lugares();
      final res = await Future.wait(lugares.map((l) async {
        final r = await Future.wait([buscarClima(l.latitude, l.longitude), buscarChuvaAcumulada(l.latitude, l.longitude)]);
        final clima = r[0] as Clima?;
        final acumulada = r[1] as ChuvaAcumulada?;
        final alertas = <AlertaClima>[
          if (acumulada != null && alertaChuvaAcumulada(acumulada) != null) alertaChuvaAcumulada(acumulada)!,
          if (clima != null) ...alertasDoClima(clima),
        ];
        return (l, alertas);
      }));
      if (mounted) setState(() => _lugares = res);
    } on ApiException catch (_) {
      // sem lugares: a seção não aparece
    }
  }

  /// Busca a previsão do local do usuário (sem travar a lista de avisos).
  Future<void> _carregarClima() async {
    final pos = await posicaoAtual() ?? kLocalPadrao;
    final c = await buscarClima(pos.latitude, pos.longitude);
    if (mounted) setState(() => _clima = c);
  }

  Future<void> _carregar() async {
    try {
      final l = await Api.notificacoes();
      if (!mounted) return;
      setState(() => _lista = l);
      // ao abrir a tela, os avisos novos passam a contar como lidos (mostrados em destaque nesta visita)
      if (l.any((n) => !n.lida)) {
        await Api.marcarLidas();
        await widget.aoLer();
      }
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  static const _ordemNivel = ['BAIXO', 'MODERADO', 'ALTO', 'CRITICO'];

  String _maiorNivel(List<AlertaClima> alertas) =>
      alertas.map((a) => a.nivel).reduce((a, b) => _ordemNivel.indexOf(a) >= _ordemNivel.indexOf(b) ? a : b);

  IconData _icone(String tipo) => switch (tipo) {
        'RISCO' => Icons.warning_amber,
        'AJUDA' => Icons.crisis_alert,
        'LOCAL' => Icons.shield,
        _ => Icons.info,
      };

  Color _cor(String tipo) => switch (tipo) {
        'RISCO' => corNivel('ALTO'),
        'AJUDA' => kBrasa,
        'LOCAL' => kMusgo,
        _ => kAgua,
      };

  /// Bloco no topo: alertas do clima (chuva, calor, UV e ar) ou "tudo tranquilo".
  Widget _blocoClima() {
    if (_clima == null) return const SizedBox.shrink();
    final alertas = alertasDoClima(_clima!);
    if (alertas.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle_outline, color: kMusgo),
          title: Text('Clima sem alertas nas próximas 12h'),
          subtitle: Text('Sem chuva forte, calor extremo, UV muito alto ou ar ruim previstos para a sua região.'),
        ),
      );
    }
    return Column(children: [
      for (final a in alertas)
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: corNivel(a.nivel), width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(a.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                Etiqueta(rotuloNivel(a.nivel), cor: corNivel(a.nivel)),
              ]),
              const SizedBox(height: 6),
              Text(a.mensagem),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Esqueleto();
    final fmt = DateFormat('dd/MM HH:mm');
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_carregar(), _carregarClima(), _carregarLugares()]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Rotulo('Clima onde você está'),
          _blocoClima(),
          if (_lugares != null && _lugares!.isNotEmpty) ...[
            const Rotulo('Seus lugares'),
            for (final (l, alertas) in _lugares!)
              Card(
                shape: alertas.isEmpty
                    ? null
                    : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: corNivel(_maiorNivel(alertas)), width: 2),
                      ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(iconeLugar(l.tipo), color: kTinta),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l.apelido, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                      if (alertas.isEmpty)
                        const Etiqueta('Sem alertas', cor: kMusgo, icone: Icons.check)
                      else
                        Etiqueta(rotuloNivel(_maiorNivel(alertas)), cor: corNivel(_maiorNivel(alertas))),
                    ]),
                    for (final a in alertas) ...[
                      const SizedBox(height: 8),
                      Text(a.titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(a.mensagem, style: const TextStyle(color: kTintaSuave)),
                    ],
                  ]),
                ),
              ),
          ],
          const Rotulo('Avisos da comunidade'),
          if (_lista.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhum aviso por enquanto. Quando o risco subir no seu bairro ou um vizinho pedir ajuda, você será avisado aqui.'),
              ),
            ),
          for (final n in _lista)
            Card(
              color: n.lida ? null : kAreia,
              child: ListTile(
                leading: CircleAvatar(backgroundColor: _cor(n.tipo), child: Icon(_icone(n.tipo), color: Colors.white)),
                title: Text(n.titulo, style: TextStyle(fontWeight: n.lida ? FontWeight.normal : FontWeight.bold)),
                subtitle: Text('${n.mensagem ?? ''}${n.criadoEm != null ? '\n${fmt.format(n.criadoEm!)}' : ''}'),
                isThreeLine: true,
              ),
            ),
        ],
      ),
    );
  }
}
