import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ícone e nome de cada tipo de lugar.
IconData iconeLugar(String tipo) => switch (tipo) {
      'CASA' => Icons.home_outlined,
      'TRABALHO' => Icons.work_outline,
      'ESTUDO' => Icons.school_outlined,
      'FAMILIA' => Icons.family_restroom,
      _ => Icons.place_outlined,
    };

const tiposLugar = <(String, String)>[
  ('CASA', 'Casa'),
  ('TRABALHO', 'Trabalho'),
  ('ESTUDO', 'Faculdade/escola'),
  ('FAMILIA', 'Família'),
  ('OUTRO', 'Outro'),
];

/// Linha com a chuva que já caiu (1h, 3h, 6h, 24h) e a prevista nas próximas 6h.
class ChuvaAcumuladaLinha extends StatelessWidget {
  final ChuvaAcumulada chuva;
  const ChuvaAcumuladaLinha({super.key, required this.chuva});

  @override
  Widget build(BuildContext context) {
    Widget celula(String rotulo, double mm, {bool previsto = false}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: previsto ? kPapel : (mm < 0.1 ? kPapel : corChuva(mm / 3).withValues(alpha: 0.85)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: previsto ? kTinta.withValues(alpha: 0.35) : kLinha, style: BorderStyle.solid),
            ),
            child: Column(children: [
              Text(mm < 0.1 ? '0' : mm.toStringAsFixed(mm < 10 ? 1 : 0),
                  style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: previsto || mm < 0.1 ? kTinta : textoSobre(corChuva(mm / 3)))),
              Text(rotulo,
                  style: TextStyle(
                      fontSize: 10.5, color: previsto || mm < 0.1 ? kTintaSuave : textoSobre(corChuva(mm / 3)).withValues(alpha: 0.85))),
            ]),
          ),
        );
    return Row(children: [
      celula('1h', chuva.h1),
      celula('3h', chuva.h3),
      celula('6h', chuva.h6),
      celula('24h', chuva.h24),
      const SizedBox(width: 6),
      celula('próx. 6h', chuva.proximas6h, previsto: true),
    ]);
  }
}

/// Seção "Meus lugares" (usada na Conta): cada lugar com a chuva acumulada.
class MeusLugares extends StatefulWidget {
  const MeusLugares({super.key});

  @override
  State<MeusLugares> createState() => _MeusLugaresState();
}

class _MeusLugaresState extends State<MeusLugares> {
  List<Lugar>? _lugares;
  final _chuva = <int, ChuvaAcumulada?>{};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final l = await Api.lugares();
      if (!mounted) return;
      setState(() => _lugares = l);
      // chuva de cada lugar em paralelo (no máximo 5 lugares)
      await Future.wait(l.map((lugar) async {
        final c = await buscarChuvaAcumulada(lugar.latitude, lugar.longitude);
        if (mounted) setState(() => _chuva[lugar.id] = c);
      }));
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    }
  }

  Future<void> _adicionar() async {
    final salvou = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const NovoLugarScreen()));
    if (salvou == true) _carregar();
  }

  Future<void> _remover(Lugar l) async {
    try {
      await Api.removerLugar(l.id);
      _carregar();
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lugares = _lugares;
    if (lugares == null) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    return Column(children: [
      if (lugares.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Adicione sua casa, trabalho ou faculdade para ver quanto choveu em cada um e receber os alertas de clima desses lugares no sino.'),
          ),
        ),
      for (final l in lugares)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(iconeLugar(l.tipo), color: kTinta),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.apelido, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (l.bairro != null) Text(l.bairro!, style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
                  ]),
                ),
                if (_chuva[l.id] != null && _chuva[l.id]!.nivel != 'BAIXO')
                  Etiqueta('Atenção', cor: corNivel(_chuva[l.id]!.nivel), icone: Icons.water_drop),
                IconButton(tooltip: 'Remover ${l.apelido}', onPressed: () => _remover(l), icon: const Icon(Icons.close, size: 20)),
              ]),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chuva.containsKey(l.id)
                    ? (_chuva[l.id] == null
                        ? const Text('Chuva indisponível agora.', style: TextStyle(color: kTintaSuave))
                        : ChuvaAcumuladaLinha(chuva: _chuva[l.id]!))
                    : const LinearProgressIndicator(),
              ),
            ]),
          ),
        ),
      if (lugares.length < 5)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton.icon(onPressed: _adicionar, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Adicionar lugar')),
        ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Chuva em mm. 1h, 3h, 6h e 24h: o que já caiu; "próx. 6h": o previsto. Fonte: Open-Meteo.',
            style: TextStyle(fontSize: 12, color: kTintaSuave)),
      ),
    ]);
  }
}

/// Escolher um lugar no mapa: arraste o mapa até o pino ficar em cima do lugar.
class NovoLugarScreen extends StatefulWidget {
  const NovoLugarScreen({super.key});

  @override
  State<NovoLugarScreen> createState() => _NovoLugarScreenState();
}

class _NovoLugarScreenState extends State<NovoLugarScreen> {
  final _mapa = MapController();
  final _nome = TextEditingController(text: 'Casa');
  String _tipo = 'CASA';
  LatLng _centro = kLocalPadrao;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _irParaMinhaPosicao();
  }

  @override
  void dispose() {
    _mapa.dispose();
    _nome.dispose();
    super.dispose();
  }

  Future<void> _irParaMinhaPosicao() async {
    final p = await posicaoAtual();
    if (p != null && mounted) {
      _mapa.move(p, 16);
      setState(() => _centro = p);
    }
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      aviso(context, 'Dê um nome para o lugar.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      await Api.salvarLugar(nome, _tipo, _centro.latitude, _centro.longitude);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo lugar')),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapa,
              options: MapOptions(
                initialCenter: _centro,
                initialZoom: 15,
                onPositionChanged: (cam, _) => _centro = cam.center, // sem setState: o pino é fixo no centro
              ),
              children: [camadaBase(context), atribuicaoMapa()],
            ),
            // pino fixo no centro da tela
            const IgnorePointer(
              child: Center(
                child: Padding(padding: EdgeInsets.only(bottom: 44), child: MarcadorGota(cor: kSinal, largura: 32)),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: const [
                    Icon(Icons.pan_tool_alt_outlined, size: 20, color: kTintaSuave),
                    SizedBox(width: 8),
                    Expanded(child: Text('Arraste o mapa até o pino laranja ficar em cima do lugar.')),
                  ]),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 34,
              child: FloatingActionButton.small(
                heroTag: 'lugar-minha-posicao',
                tooltip: 'Minha localização',
                backgroundColor: kPapelClaro,
                foregroundColor: kTinta,
                elevation: 0,
                onPressed: _irParaMinhaPosicao,
                child: const Icon(Icons.my_location),
              ),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in tiposLugar)
                  ChoiceChip(
                    avatar: Icon(iconeLugar(t.$1), size: 18, color: _tipo == t.$1 ? kPapel : kTinta),
                    label: Text(t.$2),
                    selected: _tipo == t.$1,
                    showCheckmark: false,
                    selectedColor: kTinta,
                    labelStyle: TextStyle(color: _tipo == t.$1 ? kPapel : kTinta, fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() {
                      // troca o nome sugerido se a pessoa ainda não escreveu um nome próprio
                      final sugestoes = tiposLugar.map((e) => e.$2).toSet();
                      if (_nome.text.isEmpty || sugestoes.contains(_nome.text)) _nome.text = t.$2;
                      _tipo = t.$1;
                    }),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _nome, maxLength: 40, decoration: const InputDecoration(labelText: 'Nome do lugar', counterText: '')),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: const Icon(Icons.check),
                label: const Text('Salvar lugar'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
