import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'report_screen.dart';

/// Mapa com os alagamentos da comunidade, sua posição e a previsão de chuva.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapa = MapController();
  LatLng _centro = kLocalPadrao;
  LatLng? _minhaPosicao;
  List<Alagamento> _alagamentos = [];
  Clima? _clima;
  bool _carregando = true;

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

  Future<void> _carregar({bool primeira = true}) async {
    setState(() => _carregando = true);
    final pos = await posicaoAtual();
    if (!mounted) return;
    if (pos == null && primeira) {
      aviso(context, 'Sem localização: usando São Paulo como ponto inicial.');
    }
    final ref = pos ?? _centro;
    try {
      // busca alagamentos e chuva ao mesmo tempo
      final res = await Future.wait([Api.alagamentos(ref.latitude, ref.longitude), buscarClima(ref.latitude, ref.longitude)]);
      if (!mounted) return;
      setState(() {
        _minhaPosicao = pos;
        _centro = ref;
        _alagamentos = res[0] as List<Alagamento>;
        _clima = res[1] as Clima?;
      });
      if (primeira) _mapa.move(ref, 14);
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _relatar() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(inicial: _minhaPosicao ?? _centro)),
    );
    if (ok == true) _carregar(primeira: false);
  }

  void _detalhes(Alagamento a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetalheAlagamento(
        alagamento: a,
        aoMudar: () => _carregar(primeira: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapa,
          options: MapOptions(initialCenter: _centro, initialZoom: 13, minZoom: 4, maxZoom: 18),
          children: [
            camadaBase(context),
            MarkerLayer(markers: [
              if (_minhaPosicao != null)
                Marker(
                  point: _minhaPosicao!,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: kAgua.withValues(alpha: 0.18)),
                    alignment: Alignment.center,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: kAgua,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ),
              for (final a in _alagamentos)
                Marker(
                  point: LatLng(a.latitude, a.longitude),
                  width: 38,
                  height: 54,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => _detalhes(a),
                    child: Semantics(
                      label: 'Alagamento ${rotuloGravidade(a.gravidade)}',
                      button: true,
                      child: MarcadorGota(cor: corGravidade(a.gravidade), largura: 38),
                    ),
                  ),
                ),
            ]),
            atribuicaoMapa(),
          ],
        ),        // previsão de chuva
        Positioned(top: 10, left: 10, right: 10, child: _CartaoClima(clima: _clima, carregando: _carregando)),
        // legenda
        Positioned(
          left: 10,
          bottom: 34,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final g in [4, 3, 2, 1])
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Gota(largura: 8, cor: corGravidade(g)),
                      const SizedBox(width: 6),
                      Text(rotuloGravidade(g), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 34,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'gps',
                backgroundColor: kPapelClaro,
                foregroundColor: kTinta,
                elevation: 0,
                tooltip: 'Minha localização',
                onPressed: () async {
                  await _carregar();
                },
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'relatar',
                elevation: 0,
                onPressed: _relatar,
                backgroundColor: kSinal,
                foregroundColor: kTinta,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Relatar alagamento'),
              ),
            ],
          ),
        ),
        if (_carregando) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
      ],
    );
  }
}

/// Cartão com a previsão de chuva, calor, UV e qualidade do ar das próximas 12 horas.
class _CartaoClima extends StatelessWidget {
  final Clima? clima;
  final bool carregando;
  const _CartaoClima({required this.clima, required this.carregando});

  @override
  Widget build(BuildContext context) {
    if (clima == null) {
      return carregando
          ? const SizedBox.shrink()
          : const Card(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text('Previsão do clima indisponível no momento.'),
              ),
            );
    }
    final c = clima!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LinhaClima(
              icone: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Gota(largura: 16, cor: corNivel(c.chuva.nivel))),
              titulo: 'Chuva em 12h: ${c.chuva.mmProximas12h.toStringAsFixed(1)} mm',
              detalhe: 'Chance máxima ${c.chuva.probabilidadeMax}% · pico ${c.chuva.maxMmPorHora.toStringAsFixed(1)} mm/h',
              nivel: c.chuva.nivel,
            ),
            const Divider(height: 14, color: kLinha),
            _LinhaClima(
              icone: Icon(Icons.thermostat, color: corNivel(c.calor.nivel), size: 28),
              titulo: 'Sensação de até ${c.calor.sensacaoMax.toStringAsFixed(0)} °C',
              detalhe: 'Máxima ${c.calor.temperaturaMax.toStringAsFixed(0)} °C · UV ${c.calor.uvMax.toStringAsFixed(0)}'
                  '${c.ar != null ? ' · ${rotuloAr(c.ar!.aqi)} (${c.ar!.aqi})' : ''}',
              nivel: c.calor.nivel,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaClima extends StatelessWidget {
  final Widget icone;
  final String titulo;
  final String detalhe;
  final String nivel;
  const _LinhaClima({required this.icone, required this.titulo, required this.detalhe, required this.nivel});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 30, child: Center(child: icone)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text(detalhe, style: const TextStyle(fontSize: 12, color: kTintaSuave)),
        ]),
      ),
      Etiqueta(rotuloNivel(nivel), cor: corNivel(nivel)),
    ]);
  }
}
/// Detalhes de um alagamento, com ações de confirmar / resolver.
class _DetalheAlagamento extends StatefulWidget {
  final Alagamento alagamento;
  final VoidCallback aoMudar;
  const _DetalheAlagamento({required this.alagamento, required this.aoMudar});

  @override
  State<_DetalheAlagamento> createState() => _DetalheAlagamentoState();
}

class _DetalheAlagamentoState extends State<_DetalheAlagamento> {
  bool _ocupado = false;

  Future<void> _acao(Future<void> Function() f, String sucesso) async {
    setState(() => _ocupado = true);
    try {
      await f();
      if (!mounted) return;
      Navigator.pop(context);
      aviso(context, sucesso);
      widget.aoMudar();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _ocupado = false);
        aviso(context, e.message, erro: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alagamento;
    final fmt = DateFormat('dd/MM HH:mm');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Etiqueta(rotuloGravidade(a.gravidade), cor: corGravidade(a.gravidade)),
              const SizedBox(width: 12),
              if (a.bairro != null) Expanded(child: Text(a.bairro!, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 8),
            Text(a.descricao?.isNotEmpty == true ? a.descricao! : descricaoGravidade(a.gravidade),
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            if (a.fotoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  Api.arquivo(a.fotoUrl!),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: 800, // reduz a imagem na memória
                  errorBuilder: (_, _, _) => const SizedBox(height: 60, child: Center(child: Text('Foto indisponível'))),
                ),
              ),
            const SizedBox(height: 8),
            Text('Relatado por ${a.autor}${a.criadoEm != null ? ' em ${fmt.format(a.criadoEm!)}' : ''}',
                style: const TextStyle(color: kTintaSuave)),
            Text('${a.confirmacoes} confirmação(ões) da comunidade'
                '${a.distanciaKm != null ? ' · a ${a.distanciaKm!.toStringAsFixed(1)} km de você' : ''}',
                style: const TextStyle(color: kTintaSuave)),
            if (a.expiraEm != null)
              Text('Relato válido até ${fmt.format(a.expiraEm!)}', style: const TextStyle(color: kTintaSuave)),
            const SizedBox(height: 16),
            if (!a.meu && !a.confirmadoPorMim)
              FilledButton.icon(
                onPressed: _ocupado ? null : () => _acao(() => Api.confirmar(a.id), 'Obrigado! Você confirmou este alagamento.'),
                icon: const Icon(Icons.check_circle),
                label: const Text('Também vi: confirmar'),
              ),
            if (a.confirmadoPorMim)
              const ListTile(leading: Icon(Icons.check_circle, color: kMusgo), title: Text('Você já confirmou este alagamento')),
            if (a.meu)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kMusgo),
                onPressed: _ocupado ? null : () => _acao(() => Api.resolver(a.id), 'Relato marcado como resolvido.'),
                icon: const Icon(Icons.done_all),
                label: const Text('A água baixou: encerrar relato'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => abrirRota(a.latitude, a.longitude),
              icon: const Icon(Icons.directions),
              label: const Text('Ver no mapa do celular'),
            ),
          ],
        ),
      ),
    );
  }
}
