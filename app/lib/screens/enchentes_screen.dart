import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../cidades_br.dart';
import '../risco_enchente.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'map_screen.dart';

/// Aba principal de enchentes: risco estimado automaticamente (não depende de
/// ninguém usar o app) e, ao lado, os relatos feitos pela comunidade.
class EnchentesScreen extends StatefulWidget {
  const EnchentesScreen({super.key});

  @override
  State<EnchentesScreen> createState() => _EnchentesScreenState();
}

class _EnchentesScreenState extends State<EnchentesScreen> {
  int _aba = 0; // 0 = risco estimado, 1 = relatos da comunidade

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: kPapel,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Risco estimado'), icon: Icon(Icons.flood_outlined, size: 18)),
              ButtonSegment(value: 1, label: Text('Relatos'), icon: Icon(Icons.people_outline, size: 18)),
            ],
            selected: {_aba},
            onSelectionChanged: (s) => setState(() => _aba = s.first),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(child: _aba == 0 ? const _RiscoView() : const MapScreen()),
    ]);
  }
}

class _RiscoView extends StatefulWidget {
  const _RiscoView();

  @override
  State<_RiscoView> createState() => _RiscoViewState();
}

class _RiscoViewState extends State<_RiscoView> {
  final _mapa = MapController();
  final List<RiscoCidade> _lista = [for (final c in gerarCidadesBrasil()) RiscoCidade(c)];
  RiscoCidade? _selecionada;
  bool _carregando = true;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _mapa.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    final ok = await buscarRisco(_lista);
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _falhou = !ok;
    });
  }

  int _contagem(String nivel) => _lista.where((r) => r.temDados && r.nivel == nivel).length;

  RiscoCidade? _maisProxima(LatLng p) {
    const dist = Distance();
    RiscoCidade? melhor;
    var menor = double.infinity;
    for (final r in _lista) {
      final km = dist.as(LengthUnit.Kilometer, p, r.cidade.centro).toDouble();
      if (km < menor) {
        menor = km;
        melhor = r;
      }
    }
    return menor <= 350 ? melhor : null;
  }

  void _abrirDetalhe(RiscoCidade r) {
    setState(() => _selecionada = r);
    if (!r.temDados) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetalheRisco(r: r),
    ).whenComplete(() {
      if (mounted) setState(() => _selecionada = null);
    });
  }

  /// Cidades em maior risco primeiro (ou as 10 com mais chuva, se tudo estiver tranquilo).
  void _abrirRanking() {
    final todas = _lista.where((r) => r.temDados).toList()
      ..sort((a, b) {
        final c = b.indice.compareTo(a.indice);
        return c != 0 ? c : b.pontos.compareTo(a.pontos);
      });
    final emRisco = todas.where((r) => r.indice > 0).toList();
    final mostrar = emRisco.isNotEmpty ? emRisco : todas.take(10).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.62,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(emRisco.isNotEmpty ? 'Cidades em risco agora' : 'Nenhuma cidade em risco', style: Theme.of(ctx).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Text(
              emRisco.isNotEmpty ? 'Das mais para as menos preocupantes.' : 'Estas são as 10 com mais chuva somada (recente + prevista).',
              style: const TextStyle(color: kTintaSuave),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
              for (final r in mostrar)
                ListTile(
                  dense: true,
                  title: Text('${r.cidade.nome} · ${r.cidade.uf}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${r.chuvaRecente3d!.round()} mm nos últimos 3 dias · ${r.chuvaPrevista3d!.round()} mm previstos'),
                  trailing: Etiqueta(rotuloNivel(r.nivel), cor: corNivel(r.nivel)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _mapa.move(r.cidade.centro, 6.5);
                    _abrirDetalhe(r);
                  },
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      FlutterMap(
        mapController: _mapa,
        options: MapOptions(
          initialCenter: const LatLng(-14.2, -51.9),
          initialZoom: 3.8,
          minZoom: 3,
          maxZoom: 12,
          onTap: (_, p) {
            final r = _maisProxima(p);
            if (r != null) _abrirDetalhe(r);
          },
        ),
        children: [
          camadaBase(context),
          ManchasMapa(pontos: [
            for (final r in _lista) (r.cidade.centro, (r.temDados && r.indice > 0) ? corNivel(r.nivel).withValues(alpha: 0.72) : null),
          ]),
          MarkerLayer(markers: [
            for (final r in _lista)
              Marker(
                point: r.cidade.centro,
                width: 14,
                height: 14,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: r.temDados ? corNivel(r.nivel) : Colors.white,
                      border: Border.all(color: identical(r, _selecionada) ? kTinta : Colors.white, width: identical(r, _selecionada) ? 3 : 2),
                    ),
                  ),
                ),
              ),
          ]),
          atribuicaoMapa(),
        ],
      ),
      // painel superior: contagem por nível + ranking
      Positioned(
        top: 10,
        left: 10,
        right: 10,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Risco de enchente agora', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              const Text('Estimado pela chuva dos últimos 3 dias, pela previsão e pela vazão dos rios.',
                  style: TextStyle(fontSize: 12.5, color: kTintaSuave)),
              const SizedBox(height: 10),
              if (_falhou)
                InkWell(
                  onTap: _carregar,
                  child: const Text('Não foi possível carregar. Toque para tentar de novo.',
                      style: TextStyle(color: kBrasa, fontWeight: FontWeight.w700)),
                )
              else
                Row(children: [
                  for (final n in ['CRITICO', 'ALTO', 'MODERADO', 'BAIXO'])
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(color: corNivel(n), borderRadius: BorderRadius.circular(8)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_carregando ? '…' : '${_contagem(n)}',
                                style: GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w700, color: textoSobre(corNivel(n)))),
                            Text(rotuloNivel(n).toUpperCase(),
                                style: GoogleFonts.manrope(
                                    fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: textoSobre(corNivel(n)))),
                          ]),
                        ),
                      ),
                    ),
                ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                  onPressed: _carregando || _falhou ? null : _abrirRanking,
                  icon: const Icon(Icons.format_list_numbered, size: 18),
                  label: const Text('Ver cidades em maior risco'),
                ),
              ),
            ]),
          ),
        ),
      ),
      Positioned(
        left: 10,
        right: 70,
        bottom: 34,
        child: Card(
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Text('Estimativa por modelo, não é alerta oficial. Em emergência, ligue 199 (Defesa Civil).',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 34,
        child: FloatingActionButton.small(
          heroTag: 'atualizar-risco',
          tooltip: 'Atualizar',
          backgroundColor: kPapelClaro,
          foregroundColor: kTinta,
          elevation: 0,
          onPressed: _carregando ? null : _carregar,
          child: const Icon(Icons.refresh),
        ),
      ),
      if (_carregando) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
    ]);
  }
}

/// Detalhes e explicação do risco de uma cidade.
class _DetalheRisco extends StatelessWidget {
  final RiscoCidade r;
  const _DetalheRisco({required this.r});

  String get _mensagem => switch (r.nivel) {
        'CRITICO' => 'Risco muito alto de enchente. Evite áreas de baixada e acompanhe a Defesa Civil.',
        'ALTO' => 'Risco elevado de alagamentos. Evite áreas de baixada e margens de rios.',
        'MODERADO' => 'Atenção: a chuva acumulada pode causar alagamentos pontuais.',
        _ => 'Sem sinais de enchente pela previsão de chuva.',
      };

  @override
  Widget build(BuildContext context) {
    Widget dado(String valor, String rotulo) => SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(valor, style: Theme.of(context).textTheme.titleLarge),
            Text(rotulo, style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
          ]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text('${r.cidade.nome} · ${r.cidade.uf}', style: Theme.of(context).textTheme.titleLarge)),
            Etiqueta(rotuloNivel(r.nivel), cor: corNivel(r.nivel)),
          ]),
          const SizedBox(height: 6),
          Text(_mensagem, style: const TextStyle(fontSize: 15.5)),
          const SizedBox(height: 16),
          Wrap(runSpacing: 14, children: [
            dado('${r.chuvaRecente3d!.round()} mm', 'chuva nos últimos 3 dias'),
            dado('${r.chuvaPrevista3d!.round()} mm', 'prevista (hoje + 2 dias)'),
            dado(r.pontos.toStringAsFixed(0), 'pontuação de chuva'),
            dado(r.razaoVazao != null ? '${r.razaoVazao!.toStringAsFixed(1)}x' : '—', 'vazão do rio vs. média'),
          ]),
          if (r.reforcoRio)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('A vazão do rio está bem acima da média e subiu o nível em um degrau.', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 14),
          const Text(
            'Como calculamos: pontuação = 40% da chuva dos últimos 3 dias + 60% da chuva prevista. '
            'Abaixo de 25 é baixo; 25 a 50, moderado; 50 a 90, alto; acima de 90, crítico. '
            'A vazão vem de um modelo global de rios e pode não representar o rio desta cidade. '
            'É uma estimativa, não substitui os alertas oficiais.',
            style: TextStyle(fontSize: 12.5, color: kTintaSuave),
          ),
          if (r.indice >= 2) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: () => ligar('199'), icon: const Icon(Icons.call), label: const Text('Ligar para a Defesa Civil (199)')),
          ],
        ]),
      ),
    );
  }
}
