import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../cidades_br.dart';
import '../clima_grade.dart';
import '../models.dart';
import '../radar.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

enum CamadaClima { chuva, temperatura, umidade, ar }

/// Mapa de clima do Brasil: manchas de cor suaves sobre as principais cidades de
/// cada região. Os números aparecem ao tocar; as faixas de região filtram o mapa.
/// O botão de radar mostra a chuva real das últimas horas, animada.
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
  static const _zoomEtiquetas = 6.5;
  bool _perto = false; // mapa aproximado: mostra etiqueta com nome e valor de cada cidade
  DateTime? _atualizadoEm;

  // radar de chuva
  bool _radar = false;
  bool _carregandoRadar = false;
  List<QuadroRadar> _quadros = [];
  int _quadro = 0;
  bool _tocando = true;
  Timer? _timerRadar;

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
    _timerRadar?.cancel(); // para a animação do radar ao sair da aba
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
    // previsão e qualidade do ar em paralelo; o ar é opcional
    final res = await Future.wait([buscarGrade(_cidades), buscarArGrade(_cidades)]);
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _falhou = !res[0];
      if (res[0]) _atualizadoEm = DateTime.now();
    });
  }

  // ---- radar ----------------------------------------------------------------
  Future<void> _alternarRadar() async {
    if (_radar) {
      _timerRadar?.cancel();
      setState(() => _radar = false);
      return;
    }
    setState(() => _carregandoRadar = true);
    final quadros = await buscarRadar();
    if (!mounted) return;
    setState(() => _carregandoRadar = false);
    if (quadros.isEmpty) {
      aviso(context, 'Radar indisponível agora. Tente de novo em instantes.', erro: true);
      return;
    }
    setState(() {
      _quadros = quadros;
      _quadro = quadros.length - 1;
      _radar = true;
      _tocando = true;
    });
    _iniciarAnimacaoRadar();
  }

  void _iniciarAnimacaoRadar() {
    _timerRadar?.cancel();
    var pausa = 0;
    _timerRadar = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted || !_tocando) return;
      // segura um pouco no quadro mais recente antes de recomeçar
      if (_quadro == _quadros.length - 1 && pausa < 2) {
        pausa++;
        return;
      }
      pausa = 0;
      setState(() => _quadro = (_quadro + 1) % _quadros.length);
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
      CamadaClima.ar => c.aqi?.toDouble(),
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
      CamadaClima.ar => corAr(v).withValues(alpha: a),
    };
  }

  String _textoValor(CelulaClima c) => switch (_camada) {
    CamadaClima.chuva => c.chovendo ? '${(c.chuvaMm ?? 0).toStringAsFixed(1)} mm' : 'sem chuva',
    CamadaClima.temperatura => '${(c.temperatura ?? 0).round()}°',
    CamadaClima.umidade => '${(c.umidade ?? 0).round()}%',
    CamadaClima.ar => c.aqi == null ? '—' : 'índice ${c.aqi}',
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
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: _Detalhe(celula: c, atualizadoEm: _atualizadoEm),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selecionada = null);
    });
  }

  double _media(Iterable<double> l) => l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;

  /// Texto curto de cada região para a camada atual (cidades com chuva, ou média).
  String _resumoRegiao(String regiao) {
    final cs = _cidades.where((c) => c.regiao == regiao && c.temDados).toList();
    if (cs.isEmpty) return '…';
    return switch (_camada) {
      CamadaClima.chuva => '${cs.where((c) => c.chovendo).length}/${cs.length}',
      CamadaClima.temperatura => '${_media(cs.map((c) => c.temperatura!)).round()}°',
      CamadaClima.umidade => '${_media(cs.map((c) => c.umidade ?? 0)).round()}%',
      CamadaClima.ar =>
        cs.any((c) => c.aqi != null) ? '${_media(cs.where((c) => c.aqi != null).map((c) => c.aqi!.toDouble())).round()}' : '—',
    };
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
    final cs = _cidades.where((c) => c.regiao == regiao && c.temDados).toList()..sort((a, b) => (_valor(b) ?? 0).compareTo(_valor(a) ?? 0));
    final titulo = switch (_camada) {
      CamadaClima.chuva => 'Chuva agora',
      CamadaClima.temperatura => 'Das mais quentes às mais frias',
      CamadaClima.umidade => 'Das mais úmidas às mais secas',
      CamadaClima.ar => 'Do ar mais poluído ao mais limpo',
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(child: Text(regiao, style: Theme.of(ctx).textTheme.titleLarge)),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _regiao = null);
                      _voarPara(_centroBrasil, _zoomBrasil);
                    },
                    child: const Text('Ver Brasil todo'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(titulo, style: const TextStyle(color: kTintaSuave)),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final c in cs)
                    ListTile(
                      dense: true,
                      leading: c.chovendo
                          ? const Icon(Icons.cloud, color: kChuva)
                          : const Icon(Icons.location_on_outlined, color: kTintaSuave),
                      title: Text('${c.nome} · ${c.uf}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Etiqueta(_textoValor(c), cor: _cor(c, alpha: 1) ?? kAreia),
                      onTap: () {
                        Navigator.pop(ctx);
                        _voarPara(c.centro, 7.5);
                        _abrirDetalhe(c);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paradas = switch (_camada) {
      CamadaClima.chuva => paradasChuva,
      CamadaClima.temperatura => paradasTemperatura,
      CamadaClima.umidade => paradasUmidade,
      CamadaClima.ar => paradasAr,
    };
    // com o radar ligado na camada de chuva, o radar substitui as manchas estimadas
    final esconderManchas = _radar && _camada == CamadaClima.chuva;
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
            // só redesenha quando cruza o zoom em que as etiquetas aparecem/somem
            onPositionChanged: (cam, _) {
              final perto = cam.zoom >= _zoomEtiquetas;
              if (perto != _perto) setState(() => _perto = perto);
            },
          ),
          children: [
            camadaBase(context),
            if (!esconderManchas) ManchasMapa(pontos: [for (final c in _cidades) (c.centro, _cor(c))]),
            // todos os quadros do radar ficam carregados; só o atual aparece (troca sem piscar)
            if (_radar)
              for (var i = 0; i < _quadros.length; i++)
                Opacity(
                  key: ValueKey(_quadros[i].urlTiles),
                  opacity: i == _quadro ? 0.8 : 0,
                  child: TileLayer(
                    urlTemplate: _quadros[i].urlTiles,
                    userAgentPackageName: 'br.alertaenchente.alerta_enchente',
                    maxNativeZoom: 7, // o radar gratuito vai até o zoom 7; acima disso a imagem é ampliada
                    tileDisplay: const TileDisplay.instantaneous(),
                  ),
                ),
            // pontinhos das cidades (onde tocar)
            MarkerLayer(
              markers: [
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
                            color: esconderManchas ? Colors.white : (_cor(c, alpha: 1) ?? Colors.white),
                            border: Border.all(
                              color: identical(c, _selecionada) ? kTinta : (esconderManchas ? kTintaSuave : Colors.white),
                              width: identical(c, _selecionada) ? 3 : 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_minha != null)
              MarkerLayer(
                markers: [
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
                          decoration: BoxDecoration(
                            color: kAgua,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            // nuvem azul onde está chovendo (os números só aparecem ao tocar)
            if (!esconderManchas)
              MarkerLayer(
                markers: [
                  for (final c in _cidades)
                    if (c.temDados && c.chovendo)
                      Marker(
                        point: c.centro,
                        width: 34,
                        height: 34,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: (_regiao != null && c.regiao != _regiao) ? 0.3 : 1,
                            child: const Icon(
                              Icons.cloud,
                              color: kChuva,
                              size: 28,
                              shadows: [Shadow(blurRadius: 4, color: Colors.white)],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            // de perto: etiqueta com o nome e o valor da camada; tocar abre a ficha da cidade
            if (_perto)
              MarkerLayer(markers: [
                for (final c in _cidades)
                  if (c.temDados)
                    Marker(
                      point: c.centro,
                      width: 300, // folga para nomes longos (ex.: Presidente Prudente)
                      height: 76,
                      child: Align(alignment: Alignment.topCenter, child: _etiquetaCidade(c)),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<CamadaClima>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 2))),
                      // só texto (sem ícone) para caber em 4 partes, inclusive com texto grande
                      segments: const [
                        ButtonSegment(
                          value: CamadaClima.chuva,
                          label: FittedBox(child: Text('Chuva')),
                        ),
                        ButtonSegment(
                          value: CamadaClima.temperatura,
                          label: FittedBox(child: Text('Temp.')),
                        ),
                        ButtonSegment(
                          value: CamadaClima.umidade,
                          label: FittedBox(child: Text('Umidade')),
                        ),
                        ButtonSegment(
                          value: CamadaClima.ar,
                          label: FittedBox(child: Text('Ar')),
                        ),
                      ],
                      selected: {_camada},
                      onSelectionChanged: (s) => setState(() => _camada = s.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_falhou)
                    InkWell(
                      onTap: _carregar,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'Não foi possível carregar o clima. Toque para tentar de novo.',
                          style: TextStyle(color: kBrasa, fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  else
                    // faixas das cinco regiões: tocar filtra o mapa, voa até lá e lista as cidades
                    Row(
                      children: [
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
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _regiao == r.$1 ? kTinta : kPapel,
                                      border: Border.all(color: _regiao == r.$1 ? kTinta : kLinha),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            r.$1 == 'Centro-Oeste' ? 'C. Oeste' : r.$1,
                                            style: GoogleFonts.manrope(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: _regiao == r.$1 ? kPapel : kTinta,
                                            ),
                                          ),
                                          Text(
                                            _carregando && _atualizadoEm == null ? '…' : _resumoRegiao(r.$1),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _regiao == r.$1 ? kPapel : kTintaSuave,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        // legenda em degradê, ou o controle do radar quando ele está ligado
        Positioned(
          left: 10,
          bottom: 34,
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _radar ? _controleRadar() : _legenda(paradas)),
        ),
        Positioned(
          right: 12,
          bottom: 34,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'radar-chuva',
                tooltip: _radar ? 'Desligar radar' : 'Radar de chuva ao vivo',
                backgroundColor: _radar ? kTinta : kPapelClaro,
                foregroundColor: _radar ? kPapel : kTinta,
                elevation: 0,
                onPressed: _carregandoRadar ? null : _alternarRadar,
                child: _carregandoRadar
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.radar),
              ),
              const SizedBox(height: 10),
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
            ],
          ),
        ),
        if (_carregando) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
      ],
    );
  }

  Widget _legenda(List<(double, Color)> paradas) => Card(
    key: const ValueKey('legenda'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: SizedBox(
        width: 170,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (_camada) {
              CamadaClima.chuva => 'Chuva (mm/h)',
              CamadaClima.temperatura => 'Temperatura (°C)',
              CamadaClima.umidade => 'Umidade (%)',
              CamadaClima.ar => 'Qualidade do ar (índice)',
            }, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(colors: [for (final p in paradas) p.$2]),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_camada == CamadaClima.ar ? 'bom' : paradas.first.$1.round().toString(), style: const TextStyle(fontSize: 11)),
                Text(_camada == CamadaClima.ar ? 'perigoso' : '${paradas.last.$1.round()}+', style: const TextStyle(fontSize: 11)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.cloud, color: kChuva, size: 16),
                  SizedBox(width: 4),
                  Text('chovendo agora', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Valor curto para a plaquinha do mapa.
  String _textoCurto(CelulaClima c) => switch (_camada) {
        CamadaClima.chuva => c.chovendo ? '${(c.chuvaMm ?? 0).toStringAsFixed(1)} mm' : '0 mm',
        CamadaClima.temperatura => '${(c.temperatura ?? 0).round()}°',
        CamadaClima.umidade => '${(c.umidade ?? 0).round()}%',
        CamadaClima.ar => c.aqi == null ? '—' : '${c.aqi}',
      };

  /// Plaquinha da cidade, inteira na cor da camada: valor em destaque e o nome ao lado.
  Widget _etiquetaCidade(CelulaClima c) {
    // sem chuva a cidade não tem cor na camada de chuva: usa o azul bem claro do começo da escala
    final cor = _cor(c, alpha: 1) ?? paradasChuva.first.$2;
    final fg = textoSobre(cor);
    final selecionada = identical(c, _selecionada);
    final icone = switch (_camada) {
      CamadaClima.chuva => c.chovendo ? Icons.cloud : Icons.wb_sunny_outlined,
      CamadaClima.temperatura => Icons.thermostat,
      CamadaClima.umidade => Icons.water_drop_outlined,
      CamadaClima.ar => Icons.air,
    };
    return GestureDetector(
      onTap: () => _abrirDetalhe(c),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selecionada ? kTinta : Colors.white, width: selecionada ? 2.5 : 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(_textoCurto(c), style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
            Container(width: 1, height: 13, margin: const EdgeInsets.symmetric(horizontal: 6), color: fg.withValues(alpha: 0.4)),
            Text(c.nome ?? '', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
          ]),
        ),
        // perninha ligando a plaquinha ao ponto da cidade
        Container(width: 2, height: 10, color: cor),
      ]),
    );
  }

  /// Play/pausa e linha do tempo do radar.
  Widget _controleRadar() {
    final fmt = DateFormat('HH:mm');
    final atual = _quadros[_quadro];
    final minutos = DateTime.now().difference(atual.hora).inMinutes;
    return Card(
      key: const ValueKey('radar'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
        child: SizedBox(
          width: 230,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: _tocando ? 'Pausar' : 'Tocar',
                    onPressed: () => setState(() => _tocando = !_tocando),
                    icon: Icon(_tocando ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34, color: kTinta),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Radar · ${fmt.format(atual.hora)}', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800)),
                        Text(
                          minutos <= 10 ? 'agora há pouco' : 'há $minutos min',
                          style: const TextStyle(fontSize: 11.5, color: kTintaSuave),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // um tracinho por quadro; o atual fica laranja
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    for (var i = 0; i < _quadros.length; i++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _tocando = false;
                            _quadro = i;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              color: i == _quadro ? kSinal : (i < _quadro ? kTinta.withValues(alpha: 0.55) : kAreia),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Padding(padding: EdgeInsets.only(left: 10), child: AtribuicaoRadar()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalhes de uma cidade, mostrados ao tocar: agora, UV, ar e os próximos 7 dias.
class _Detalhe extends StatefulWidget {
  final CelulaClima celula;
  final DateTime? atualizadoEm;
  const _Detalhe({required this.celula, required this.atualizadoEm});

  @override
  State<_Detalhe> createState() => _DetalheState();
}

class _DetalheState extends State<_Detalhe> {
  late final Future<List<PrevisaoDia>?> _semana = buscarPrevisao7Dias(widget.celula.centro.latitude, widget.celula.centro.longitude);

  @override
  Widget build(BuildContext context) {
    final c = widget.celula;
    final chuva = c.chuvaMm ?? 0;
    final fmt = DateFormat('HH:mm');
    Widget dado(String valor, String rotulo) => SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor, style: Theme.of(context).textTheme.titleLarge),
          Text(rotulo, style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('${c.nome} · ${c.uf}', style: Theme.of(context).textTheme.titleLarge)),
                if (c.regiao != null) Etiqueta(c.regiao!, cor: kAreia),
              ],
            ),
            Text(
              '${c.codigo != null ? descricaoTempo(c.codigo!) : 'Tempo atual'}'
              '${widget.atualizadoEm != null ? ' · atualizado às ${fmt.format(widget.atualizadoEm!)}' : ''}',
              style: const TextStyle(color: kTintaSuave),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${c.temperatura!.round()}°', style: GoogleFonts.fraunces(fontSize: 56, fontWeight: FontWeight.w700, height: 1)),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('sensação de ${(c.sensacao ?? c.temperatura!).round()}°', style: const TextStyle(fontSize: 15)),
                ),
                const Spacer(),
                if (c.codigo != null) Icon(iconeTempo(c.codigo!), size: 40, color: kTinta),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Etiqueta(rotuloTemperatura(c.temperatura!), cor: corTemperatura(c.temperatura!)),
                Etiqueta(
                  c.chovendo && chuva < 0.1 ? 'Chovendo' : rotuloChuva(chuva),
                  cor: c.chovendo ? kChuva : kAreia,
                  icone: c.chovendo ? Icons.cloud : null,
                ),
                if (c.umidade != null) Etiqueta(rotuloUmidade(c.umidade!), cor: corUmidade(c.umidade!)),
                if (c.aqi != null) Etiqueta(rotuloAr(c.aqi!), cor: corAr(c.aqi!.toDouble()), icone: Icons.air),
                if (c.uv != null && c.uv! >= 3) Etiqueta(rotuloUv(c.uv!), cor: corUv(c.uv!), icone: Icons.wb_sunny_outlined),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              runSpacing: 14,
              children: [
                dado('${chuva.toStringAsFixed(1)} mm', 'chuva na última hora'),
                dado('${(c.chuva6hMm ?? 0).toStringAsFixed(1)} mm', 'previstos nas próximas 6h'),
                dado('${(c.umidade ?? 0).round()}%', 'umidade do ar'),
                dado('${(c.ventoKmh ?? 0).round()} km/h', 'vento'),
                if (c.uv != null) dado(c.uv!.toStringAsFixed(1), 'índice UV agora'),
                if (c.aqi != null)
                  dado('${c.aqi}', c.pm25 != null ? 'qualidade do ar · PM2,5 ${c.pm25!.round()} µg/m³' : 'qualidade do ar'),
              ],
            ),
            const Rotulo('Próximos 7 dias'),
            FutureBuilder<List<PrevisaoDia>?>(
              future: _semana,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 170, child: Center(child: LinearProgressIndicator()));
                }
                final dias = snap.data;
                if (dias == null || dias.isEmpty) {
                  return const Text('Não foi possível carregar a previsão da semana.', style: TextStyle(color: kTintaSuave));
                }
                return _GraficoSemana(dias: dias);
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Text(
                'Dados do centro da cidade, por previsão e qualidade do ar do Open-Meteo.',
                style: TextStyle(fontSize: 12, color: kTintaSuave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma coluna por dia: ícone, máxima/mínima, barra de chuva e UV.
class _GraficoSemana extends StatelessWidget {
  final List<PrevisaoDia> dias;
  const _GraficoSemana({required this.dias});

  static const _semana = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    final maiorChuva = dias.map((d) => d.chuvaMm).fold(10.0, (a, b) => a > b ? a : b);
    final hoje = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
      decoration: BoxDecoration(
        color: kPapelClaro,
        border: Border.all(color: kLinha),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in dias)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.data.year == hoje.year && d.data.month == hoje.month && d.data.day == hoje.day ? 'hoje' : _semana[d.data.weekday - 1],
                    style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w800, color: kTintaSuave),
                  ),
                  const SizedBox(height: 4),
                  Icon(iconeTempo(d.codigo), size: 22, color: codigoChuva(d.codigo) ? kChuva : kTinta),
                  const SizedBox(height: 4),
                  Text('${d.maxima.round()}°', style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  Text('${d.minima.round()}°', style: const TextStyle(fontSize: 12, color: kTintaSuave)),
                  const SizedBox(height: 6),
                  // barra de chuva proporcional ao maior volume da semana (mínimo de 10 mm na escala)
                  SizedBox(
                    height: 46,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 14,
                        height: d.chuvaMm < 0.1 ? 2 : (4 + 42 * d.chuvaMm / maiorChuva),
                        decoration: BoxDecoration(
                          color: d.chuvaMm < 0.1 ? kLinha : corChuva(d.chuvaMm / 6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(d.chuvaMm < 0.1 ? '—' : '${d.chuvaMm.round()}mm', style: const TextStyle(fontSize: 10.5)),
                  Text('${d.probChuva}%', style: const TextStyle(fontSize: 10.5, color: kTintaSuave)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: corUv(d.uvMax), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      'UV${d.uvMax.round()}',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: textoSobre(corUv(d.uvMax))),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
