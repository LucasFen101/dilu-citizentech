import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../cidades_br.dart';
import '../clima_grade.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

enum CamadaClima { chuva, temperatura, umidade }

/// Mapa de clima do Brasil: manchas de cor suaves sobre as principais cidades de
/// cada região. Os números aparecem ao tocar; as faixas de região filtram o mapa.
class ClimaScreen extends StatefulWidget {
  const ClimaScreen({super.key});

  @override
  State<ClimaScreen> createState() => _ClimaScreenState();
}

class _ClimaScreenState extends State<ClimaScreen> with SingleTickerProviderStateMixin {
  static const _centroBrasil = LatLng(-14.2, -51.9);
  static const _zoomBrasil = 3.8;

  final _mapa = MapController();
  final List<CelulaClima> _cidades = gerarCidadesBrasil();
  CamadaClima _camada = CamadaClima.chuva;
  CelulaClima? _selecionada;
  String? _regiao; // filtro: região em destaque (null = Brasil todo)
  LatLng? _minha; // posição do usuário (opcional)
  bool _carregando = true;
  bool _falhou = false;
  DateTime? _atualizadoEm;

  // animação de "voar" até um ponto
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  late final CurvedAnimation _curva = CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);
  LatLng _de = _centroBrasil;
  LatLng _para = _centroBrasil;
  double _z0 = _zoomBrasil;
  double _z1 = _zoomBrasil;

  @override
  void initState() {
    super.initState();
    _anim.addListener(_passoAnimacao);
    _carregar();
    _localizar();
  }

  @override
  void dispose() {
    _anim.dispose();
    _mapa.dispose();
    super.dispose();
  }

  void _passoAnimacao() {
    final t = _curva.value;
    _mapa.move(
      LatLng(_de.latitude + (_para.latitude - _de.latitude) * t, _de.longitude + (_para.longitude - _de.longitude) * t),
      _z0 + (_z1 - _z0) * t,
    );
  }

  /// Leva o mapa suavemente até um ponto e zoom.
  void _voarPara(LatLng alvo, double zoom) {
    final cam = _mapa.camera;
    _de = cam.center;
    _z0 = cam.zoom;
    _para = alvo;
    _z1 = zoom;
    _anim.forward(from: 0);
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    final ok = await buscarGrade(_cidades);
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _falhou = !ok;
      if (ok) _atualizadoEm = DateTime.now();
    });
  }

  /// Pede a localização (opcional): mostra a bolinha do usuário.
  Future<void> _localizar({bool avisar = false}) async {
    final pos = await posicaoAtual();
    if (!mounted) return;
    if (pos == null) {
      if (avisar) aviso(context, 'Não foi possível obter sua localização.', erro: true);
      return;
    }
    setState(() => _minha = pos);
    if (avisar) _voarPara(pos, 7.5);
  }

  /// Valor numérico da cidade na camada atual.
  double? _valor(CelulaClima c) {
    if (!c.temDados) return null;
    return switch (_camada) {
      CamadaClima.chuva => c.chuvaMm ?? 0,
      CamadaClima.temperatura => c.temperatura,
      CamadaClima.umidade => c.umidade,
    };
  }

  /// Cor da cidade na camada atual; null quando não deve ser pintada (sem chuva).
  /// Cidades fora da região em destaque ficam esmaecidas.
  Color? _cor(CelulaClima c, {double alpha = 0.7}) {
    final v = _valor(c);
    if (v == null) return null;
    final fator = (_regiao != null && c.regiao != _regiao) ? 0.25 : 1.0;
    final a = alpha * fator;
    return switch (_camada) {
      CamadaClima.chuva => c.chovendo ? corChuva(v < 0.3 ? 0.3 : v).withValues(alpha: a) : null,
      CamadaClima.temperatura => corTemperatura(v).withValues(alpha: a),
      CamadaClima.umidade => corUmidade(v).withValues(alpha: a),
    };
  }

  String _textoValor(CelulaClima c) => switch (_camada) {
        CamadaClima.chuva => c.chovendo ? '${(c.chuvaMm ?? 0).toStringAsFixed(1)} mm' : 'sem chuva',
        CamadaClima.temperatura => '${(c.temperatura ?? 0).round()}°',
        CamadaClima.umidade => '${(c.umidade ?? 0).round()}%',
      };

  void _tocar(LatLng p) {
    final c = cidadeMaisProxima(_cidades, p);
    if (c != null) _abrirDetalhe(c);
  }

  void _abrirDetalhe(CelulaClima c) {
    setState(() => _selecionada = c);
    if (!c.temDados) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Detalhe(celula: c, atualizadoEm: _atualizadoEm),
    ).whenComplete(() {
      if (mounted) setState(() => _selecionada = null);
    });
  }

  /// Texto curto de cada região para a camada atual (cidades com chuva, ou média).
  String _resumoRegiao(String regiao) {
    final cs = _cidades.where((c) => c.regiao == regiao && c.temDados).toList();
    if (cs.isEmpty) return '…';
    switch (_camada) {
      case CamadaClima.chuva:
        return '${cs.where((c) => c.chovendo).length}/${cs.length}';
      case CamadaClima.temperatura:
        return '${(cs.map((c) => c.temperatura!).reduce((a, b) => a + b) / cs.length).round()}°';
      case CamadaClima.umidade:
        return '${(cs.map((c) => c.umidade ?? 0).reduce((a, b) => a + b) / cs.length).round()}%';
    }
  }

  void _escolherRegiao((String, LatLng, double) r) {
    if (_regiao == r.$1) {
      setState(() => _regiao = null);
      _voarPara(_centroBrasil, _zoomBrasil);
      return;
    }
    setState(() => _regiao = r.$1);
    _voarPara(r.$2, r.$3);
    _abrirRanking(r.$1);
  }

  /// Lista as cidades da região ordenadas pela camada atual; tocar numa cidade voa até ela.
  void _abrirRanking(String regiao) {
    final cs = _cidades.where((c) => c.regiao == regiao && c.temDados).toList()
      ..sort((a, b) => (_valor(b) ?? 0).compareTo(_valor(a) ?? 0));
    final titulo = switch (_camada) {
      CamadaClima.chuva => 'Chuva agora',
      CamadaClima.temperatura => 'Das mais quentes às mais frias',
      CamadaClima.umidade => 'Das mais úmidas às mais secas',
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.62,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(children: [
              Expanded(child: Text(regiao, style: Theme.of(ctx).textTheme.titleLarge)),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _regiao = null);
                  _voarPara(_centroBrasil, _zoomBrasil);
                },
                child: const Text('Ver Brasil todo'),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(titulo, style: const TextStyle(color: kTintaSuave))),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
              for (final c in cs)
                ListTile(
                  dense: true,
                  leading: c.chovendo ? const Icon(Icons.cloud, color: kChuva) : const Icon(Icons.location_on_outlined, color: kTintaSuave),
                  title: Text('${c.nome} · ${c.uf}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Etiqueta(_textoValor(c), cor: _cor(c, alpha: 1) ?? kAreia),
                  onTap: () {
                    Navigator.pop(ctx);
                    _voarPara(c.centro, 7.5);
                    _abrirDetalhe(c);
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
    final paradas = switch (_camada) {
      CamadaClima.chuva => paradasChuva,
      CamadaClima.temperatura => paradasTemperatura,
      CamadaClima.umidade => paradasUmidade,
    };
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapa,
          options: MapOptions(
            initialCenter: _centroBrasil,
            initialZoom: _zoomBrasil,
            minZoom: 3,
            maxZoom: 13,
            onTap: (_, p) => _tocar(p),
          ),
          children: [
            camadaBase(context),
            ManchasMapa(pontos: [for (final c in _cidades) (c.centro, _cor(c))]),
            // pontinhos das cidades (onde tocar)
            MarkerLayer(markers: [
              for (final c in _cidades)
                Marker(
                  point: c.centro,
                  width: 14,
                  height: 14,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (_regiao != null && c.regiao != _regiao) ? 0.35 : 1,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _cor(c, alpha: 1) ?? Colors.white,
                          border: Border.all(
                              color: identical(c, _selecionada) ? kTinta : Colors.white, width: identical(c, _selecionada) ? 3 : 2),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
            if (_minha != null)
              MarkerLayer(markers: [
                Marker(
                  point: _minha!,
                  width: 40,
                  height: 40,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: kAgua.withValues(alpha: 0.2)),
                      alignment: Alignment.center,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(color: kAgua, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      ),
                    ),
                  ),
                ),
              ]),
            // nuvem azul onde está chovendo (os números só aparecem ao tocar)
            MarkerLayer(markers: [
              for (final c in _cidades)
                if (c.temDados && c.chovendo)
                  Marker(
                    point: c.centro,
                    width: 34,
                    height: 34,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (_regiao != null && c.regiao != _regiao) ? 0.3 : 1,
                        child: const Icon(Icons.cloud, color: kChuva, size: 28, shadows: [Shadow(blurRadius: 4, color: Colors.white)]),
                      ),
                    ),
                  ),
            ]),
            atribuicaoMapa(),
          ],
        ),
        // painel superior: camada e regiões
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<CamadaClima>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: CamadaClima.chuva, label: Text('Chuva'), icon: Icon(Icons.cloud_outlined, size: 18)),
                    ButtonSegment(value: CamadaClima.temperatura, label: Text('Temp.'), icon: Icon(Icons.thermostat, size: 18)),
                    ButtonSegment(value: CamadaClima.umidade, label: Text('Umidade'), icon: Icon(Icons.water_drop_outlined, size: 18)),
                  ],
                  selected: {_camada},
                  onSelectionChanged: (s) => setState(() => _camada = s.first),
                ),
                const SizedBox(height: 8),
                if (_falhou)
                  InkWell(
                    onTap: _carregar,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Não foi possível carregar o clima. Toque para tentar de novo.',
                          style: TextStyle(color: kBrasa, fontWeight: FontWeight.w700)),
                    ),
                  )
                else
                  // faixas das cinco regiões: tocar filtra o mapa, voa até lá e lista as cidades
                  Row(children: [
                    for (final r in regioesBrasil)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.5),
                          child: Semantics(
                            label: 'Região ${r.$1}',
                            button: true,
                            selected: _regiao == r.$1,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _escolherRegiao(r),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _regiao == r.$1 ? kTinta : kPapel,
                                  border: Border.all(color: _regiao == r.$1 ? kTinta : kLinha),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Text(r.$1 == 'Centro-Oeste' ? 'C. Oeste' : r.$1,
                                        style: GoogleFonts.manrope(
                                            fontSize: 11.5, fontWeight: FontWeight.w800, color: _regiao == r.$1 ? kPapel : kTinta)),
                                    Text(_carregando && _atualizadoEm == null ? '…' : _resumoRegiao(r.$1),
                                        style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w700, color: _regiao == r.$1 ? kPapel : kTintaSuave)),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
              ]),
            ),
          ),
        ),
        // legenda em degradê
        Positioned(
          left: 10,
          bottom: 34,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: SizedBox(
                width: 170,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    switch (_camada) {
                      CamadaClima.chuva => 'Chuva (mm/h)',
                      CamadaClima.temperatura => 'Temperatura (°C)',
                      CamadaClima.umidade => 'Umidade (%)',
                    },
                    style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(colors: [for (final p in paradas) p.$2]),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(paradas.first.$1.round().toString(), style: const TextStyle(fontSize: 11)),
                    Text('${paradas.last.$1.round()}+', style: const TextStyle(fontSize: 11)),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.cloud, color: kChuva, size: 16),
                      SizedBox(width: 4),
                      Text('chovendo agora', style: TextStyle(fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 34,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(
              heroTag: 'minha-regiao',
              tooltip: 'Minha localização',
              backgroundColor: kPapelClaro,
              foregroundColor: kTinta,
              elevation: 0,
              onPressed: () => _minha == null ? _localizar(avisar: true) : _voarPara(_minha!, 7.5),
              child: const Icon(Icons.my_location),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'atualizar-clima',
              tooltip: 'Atualizar previsão',
              backgroundColor: kPapelClaro,
              foregroundColor: kTinta,
              elevation: 0,
              onPressed: _carregando ? null : _carregar,
              child: const Icon(Icons.refresh),
            ),
          ]),
        ),
        if (_carregando) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
      ],
    );
  }
}

/// Detalhes de uma cidade, mostrados ao tocar.
class _Detalhe extends StatelessWidget {
  final CelulaClima celula;
  final DateTime? atualizadoEm;
  const _Detalhe({required this.celula, required this.atualizadoEm});

  @override
  Widget build(BuildContext context) {
    final c = celula;
    final chuva = c.chuvaMm ?? 0;
    final fmt = DateFormat('HH:mm');
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
            Expanded(child: Text('${c.nome} · ${c.uf}', style: Theme.of(context).textTheme.titleLarge)),
            if (c.regiao != null) Etiqueta(c.regiao!, cor: kAreia),
          ]),
          Text(
            '${c.codigo != null ? descricaoTempo(c.codigo!) : 'Tempo atual'}'
            '${atualizadoEm != null ? ' · atualizado às ${fmt.format(atualizadoEm!)}' : ''}',
            style: const TextStyle(color: kTintaSuave),
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${c.temperatura!.round()}°', style: GoogleFonts.fraunces(fontSize: 56, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('sensação de ${(c.sensacao ?? c.temperatura!).round()}°', style: const TextStyle(fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Etiqueta(rotuloTemperatura(c.temperatura!), cor: corTemperatura(c.temperatura!)),
            Etiqueta(c.chovendo && chuva < 0.1 ? 'Chovendo' : rotuloChuva(chuva), cor: c.chovendo ? kChuva : kAreia, icone: c.chovendo ? Icons.cloud : null),
            if (c.umidade != null) Etiqueta(rotuloUmidade(c.umidade!), cor: corUmidade(c.umidade!)),
          ]),
          const SizedBox(height: 18),
          Wrap(runSpacing: 14, children: [
            dado('${chuva.toStringAsFixed(1)} mm', 'chuva na última hora'),
            dado('${(c.chuva6hMm ?? 0).toStringAsFixed(1)} mm', 'previstos nas próximas 6h'),
            dado('${(c.umidade ?? 0).round()}%', 'umidade do ar'),
            dado('${(c.ventoKmh ?? 0).round()} km/h', 'vento'),
          ]),
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text('Dados do centro da cidade, por previsão do Open-Meteo.', style: TextStyle(fontSize: 12, color: kTintaSuave)),
          ),
        ]),
      ),
    );
  }
}
