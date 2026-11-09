import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Abrigos próximos e checklist de segurança em enchentes.
class SheltersScreen extends StatelessWidget {
  const SheltersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: kPapelClaro,
            child: TabBar(tabs: [Tab(icon: Icon(Icons.home_work), text: 'Abrigos'), Tab(icon: Icon(Icons.checklist), text: 'O que fazer')]),
          ),
          Expanded(child: TabBarView(children: [_ListaAbrigos(), _Dicas()])),
        ],
      ),
    );
  }
}

class _ListaAbrigos extends StatefulWidget {
  const _ListaAbrigos();

  @override
  State<_ListaAbrigos> createState() => _ListaAbrigosState();
}

class _ListaAbrigosState extends State<_ListaAbrigos> with AutomaticKeepAliveClientMixin {
  List<Abrigo> _abrigos = [];
  bool _carregando = true;
  bool _semGps = false;
  bool _semConexao = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final pos = await posicaoAtual();
    try {
      final a = await Api.abrigos(pos?.latitude, pos?.longitude);
      if (mounted) {
        setState(() {
          _abrigos = a;
          _semGps = pos == null;
          _semConexao = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == null) {
        setState(() => _semConexao = true);
      } else {
        aviso(context, e.message, erro: true);
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_carregando) return const Esqueleto();
    if (_semConexao && _abrigos.isEmpty) return EstadoTela.semConexao(aoTentar: _carregar);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_semGps)
            const Card(
              color: kAreia,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Sem localização: os abrigos aparecem sem ordem de distância.'),
              ),
            ),
          if (_abrigos.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Nenhum abrigo cadastrado.'))),
          for (final a in _abrigos)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.home_work, color: kAgua),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.nome, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                      if (a.distanciaKm != null)
                        Etiqueta('${a.distanciaKm!.toStringAsFixed(1)} km', cor: kAreia),
                    ]),
                    Text('${a.bairro}${a.endereco != null ? ' · ${a.endereco}' : ''}'),
                    if (a.capacidade != null) Text('Capacidade: ${a.capacidade} pessoas'),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          onPressed: () => abrirRota(a.latitude, a.longitude),
                          icon: const Icon(Icons.directions),
                          label: const Text('Como chegar'),
                        ),
                      ),
                      if (a.telefone != null) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                            tooltip: 'Ligar para ${a.nome}', onPressed: () => ligar(a.telefone!), icon: const Icon(Icons.call)),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text('Os abrigos mostrados são exemplos de demonstração. Confirme os locais oficiais com a Defesa Civil (199).',
              style: TextStyle(fontSize: 12, color: kTintaSuave)),
        ],
      ),
    );
  }
}

class _Dicas extends StatelessWidget {
  const _Dicas();

  static const _grupos = <(String, IconData, List<String>)>[
    (
      'Antes da enchente',
      Icons.watch_later,
      [
        'Separe documentos, remédios, carregador e lanterna em uma bolsa.',
        'Combine com a família um ponto de encontro e um contato de referência.',
        'Guarde os telefones: Defesa Civil 199 e Bombeiros 193.',
        'Acompanhe a previsão de chuva e os avisos do app.',
      ]
    ),
    (
      'Durante a enchente',
      Icons.warning_amber,
      [
        'Vá para um local alto e não tente atravessar ruas alagadas a pé ou de carro.',
        'Desligue a energia elétrica e o gás se a água entrar em casa.',
        'Evite contato com a água: ela pode estar contaminada e conter fios energizados.',
        'Use o botão SOS para avisar seus contatos e a vizinhança.',
      ]
    ),
    (
      'Calor extremo',
      Icons.thermostat,
      [
        'Beba água o dia todo, mesmo sem sede. Evite álcool e bebidas muito doces.',
        'Evite o sol entre 10h e 16h e use roupas leves, chapéu e protetor solar.',
        'Nunca deixe crianças, idosos ou animais dentro de carros fechados.',
        'Procure locais frescos e ventilados. Sinais de alerta: tontura, náusea, pele quente e seca: busque atendimento.',
      ]
    ),
    (
      'Depois da enchente',
      Icons.cleaning_services,
      [
        'Só volte para casa quando as autoridades liberarem.',
        'Descarte alimentos que tiveram contato com a água.',
        'Limpe e desinfete o ambiente com água sanitária; use luvas e botas.',
        'Marque o relato como resolvido no mapa para atualizar a comunidade.',
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final g in _grupos)
          Card(
            child: ExpansionTile(
              initiallyExpanded: g.$1 == 'Durante a enchente',
              leading: Icon(g.$2, color: kAgua),
              title: Text(g.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final item in g.$3)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.check_circle_outline, size: 20, color: kMusgo),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item, style: const TextStyle(fontSize: 15))),
                    ]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
