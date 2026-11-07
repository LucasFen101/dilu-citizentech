import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Painel de risco por bairro, calculado pelo Oracle (PL/SQL + view).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Bairro> _bairros = [];
  NumerosDilu? _numeros;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final res = await Future.wait([Api.indicadores(), Api.numeros()]);
      if (mounted) {
        setState(() {
          _bairros = res[0] as List<Bairro>;
          _numeros = res[1] as NumerosDilu;
        });
      }
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _historico(Bairro b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _HistoricoBairro(bairro: b),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    final contagem = <String, int>{};
    for (final b in _bairros) {
      contagem[b.nivel] = (contagem[b.nivel] ?? 0) + 1;
    }
    final maior = _bairros.fold<double>(1, (m, b) => b.score > m ? b.score : m);
    final ativos = _bairros.fold<int>(0, (s, b) => s + b.alagamentosAtivos);
    final pedidos = _bairros.fold<int>(0, (s, b) => s + b.pedidosAbertos);

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            _Resumo(valor: '$ativos', rotulo: 'alagamentos\nativos', icone: Icons.water_drop, cor: kAgua),
            const SizedBox(width: 8),
            _Resumo(valor: '$pedidos', rotulo: 'pedidos de\najuda abertos', icone: Icons.crisis_alert, cor: kBrasa),
            const SizedBox(width: 8),
            _Resumo(
                valor: '${(contagem['ALTO'] ?? 0) + (contagem['CRITICO'] ?? 0)}',
                rotulo: 'bairros em\nrisco alto', icone: Icons.warning_amber, cor: corNivel('ALTO')),
          ]),
          if (_numeros != null) _NumerosDilu(n: _numeros!),
          const SizedBox(height: 12),
          Text('Bairros por nível de risco', style: Theme.of(context).textTheme.titleMedium),
          const Text('Toque em um bairro para ver o histórico.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          for (final b in _bairros)
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _historico(b),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(b.nome, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                        Etiqueta(rotuloNivel(b.nivel), cor: corNivel(b.nivel)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (b.score / maior).clamp(0.0, 1.0),
                          minHeight: 10,
                          color: corNivel(b.nivel),
                          backgroundColor: kAreia,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 14, runSpacing: 4, children: [
                        Text('${b.alagamentosAtivos} ativo(s)'),
                        Text('${b.relatos24h} relato(s) em 24h'),
                        Text('${b.pedidosAbertos} pedido(s) de ajuda'),
                        Text('${b.abrigos} abrigo(s)'),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Dilu em números": resultados gerais, calculados pela view do Oracle.
class _NumerosDilu extends StatelessWidget {
  final NumerosDilu n;
  const _NumerosDilu({required this.n});

  @override
  Widget build(BuildContext context) {
    final itens = <(String, String)>[
      ('${n.relatosTotal}', 'relatos de alagamento'),
      ('${n.confirmacoes}', 'confirmações da comunidade'),
      ('${n.relatosResolvidos}', 'relatos resolvidos'),
      ('${n.pedidosAtendidos} de ${n.pedidosAjuda}', 'pedidos de ajuda atendidos'),
      ('${n.avisosRisco}', 'avisos de risco enviados'),
      ('${n.moradores}', 'moradores no Dilu'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Rotulo('Dilu em números'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            runSpacing: 14,
            children: [
              for (final i in itens)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SizedBox(
                    width: 140,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.$1, style: Theme.of(context).textTheme.headlineSmall),
                      Text(i.$2, style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _Resumo extends StatelessWidget {
  final String valor;
  final String rotulo;
  final IconData icone;
  final Color cor;
  const _Resumo({required this.valor, required this.rotulo, required this.icone, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(children: [
            Icon(icone, color: cor),
            Text(valor, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cor)),
            Text(rotulo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// Últimas mudanças de nível de risco de um bairro.
class _HistoricoBairro extends StatelessWidget {
  final Bairro bairro;
  const _HistoricoBairro({required this.bairro});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Histórico: ${bairro.nome}', style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: FutureBuilder<List<RegistroRisco>>(
                future: Api.historico(bairro.id),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  final lista = snap.data ?? [];
                  if (lista.isEmpty) {
                    return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma mudança de risco registrada ainda.')));
                  }
                  return ListView(
                    children: [
                      for (final r in lista)
                        ListTile(
                          leading: SizedBox(width: 24, child: Center(child: Gota(largura: 14, cor: corNivel(r.nivel)))),
                          title: Text('Risco ${rotuloNivel(r.nivel).toLowerCase()} (pontuação ${r.score.toStringAsFixed(1)})'),
                          subtitle: Text(r.quando != null ? fmt.format(r.quando!) : ''),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
