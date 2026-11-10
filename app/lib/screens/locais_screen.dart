import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ícone e cor de cada tipo de local seguro.
IconData iconeLocal(String tipo) => switch (tipo) {
      'PONTO_ALTO' => Icons.terrain,
      'ACOLHIMENTO' => Icons.volunteer_activism,
      'PONTO_ENCONTRO' => Icons.groups,
      _ => Icons.inventory_2_outlined,
    };

Color corLocal(String tipo) => switch (tipo) {
      'PONTO_ALTO' => kAgua,
      'ACOLHIMENTO' => kSinal,
      'PONTO_ENCONTRO' => kTinta,
      _ => kMusgo,
    };

/// Aba "Seguros": locais seguros indicados pela comunidade + o que fazer.
class LocaisScreen extends StatelessWidget {
  /// Parte que abre primeiro: 0 = locais seguros, 1 = o que fazer (kit e dicas).
  final int abaInicial;
  const LocaisScreen({super.key, this.abaInicial = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: abaInicial,
      child: const Column(
        children: [
          Material(
            color: kPapelClaro,
            child: TabBar(tabs: [Tab(icon: Icon(Icons.shield), text: 'Locais seguros'), Tab(icon: Icon(Icons.checklist), text: 'O que fazer')]),
          ),
          Expanded(child: TabBarView(children: [_ListaLocais(), _Dicas()])),
        ],
      ),
    );
  }
}

class _ListaLocais extends StatefulWidget {
  const _ListaLocais();

  @override
  State<_ListaLocais> createState() => _ListaLocaisState();
}

/// Mapa e lista dos locais seguros perto de você. Moradores cadastram e os
/// vizinhos avaliam se o local é mesmo seguro (tudo guardado no Oracle).
class _ListaLocaisState extends State<_ListaLocais> with AutomaticKeepAliveClientMixin {
  final _mapa = MapController();
  LatLng _pos = kLocalPadrao;
  bool _semGps = false;
  List<LocalSeguro> _locais = [];
  String? _filtro; // tipo escolhido (null = todos)
  bool _carregando = true;
  bool _semConexao = false;
  final _ocupados = <int>{};

  @override
  bool get wantKeepAlive => true;

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

  Future<void> _carregar({bool mostrarCarregando = true}) async {
    if (mostrarCarregando) setState(() => _carregando = true);
    final gps = await posicaoAtual();
    final pos = gps ?? kLocalPadrao;
    try {
      final l = await Api.locaisSeguros(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _pos = pos;
        _semGps = gps == null;
        _locais = l;
        _semConexao = false;
      });
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

  Future<void> _acao(int id, Future<void> Function() f, String sucesso) async {
    setState(() => _ocupados.add(id));
    try {
      await f();
      if (mounted) aviso(context, sucesso);
      await _carregar(mostrarCarregando: false);
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _ocupados.remove(id));
    }
  }

  Future<void> _novo() async {
    final salvou = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NovoLocalScreen(inicio: _pos)));
    if (salvou == true) {
      if (mounted) aviso(context, 'Obrigado! Os vizinhos do bairro foram avisados.');
      _carregar(mostrarCarregando: false);
    }
  }

  String _ha(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'há ${d.inMinutes < 1 ? 1 : d.inMinutes} min';
    if (d.inHours < 24) return 'há ${d.inHours} h';
    return 'há ${d.inDays} dia(s)';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_carregando) return const Esqueleto();
    if (_semConexao && _locais.isEmpty) return EstadoTela.semConexao(aoTentar: _carregar);
    final visiveis = _filtro == null ? _locais : _locais.where((l) => l.tipo == _filtro).toList();
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
                child: Text('Sem localização: mostrando a região da Mooca, em São Paulo. Permita a localização para ver os locais perto de você.'),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 240,
              child: FlutterMap(
                mapController: _mapa,
                options: MapOptions(initialCenter: _pos, initialZoom: 14, minZoom: 10, maxZoom: 18),
                children: [
                  camadaBase(context),
                  MarkerLayer(markers: [
                    Marker(
                      point: _pos,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(color: kAgua, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      ),
                    ),
                    for (final l in visiveis)
                      Marker(
                        point: LatLng(l.latitude, l.longitude),
                        width: 30,
                        height: 42,
                        alignment: Alignment.topCenter,
                        child: Tooltip(message: l.nome, child: MarcadorGota(cor: corLocal(l.tipo), largura: 30)),
                      ),
                  ]),
                  atribuicaoMapa(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // filtro por tipo
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(null, 'Todos', Icons.shield_outlined, kTinta),
              for (final t in tiposLocal) _chip(t.$1, t.$2, iconeLocal(t.$1), corLocal(t.$1)),
            ]),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _novo, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Indicar um local seguro')),
          const Rotulo('Perto de você'),
          if (visiveis.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_locais.isEmpty
                    ? 'Ainda não há locais seguros indicados perto de você. Conhece um lugar alto para deixar o carro, '
                        'uma igreja que acolhe pessoas ou um ponto de doação? Indique e ajude os vizinhos.'
                    : 'Nenhum local deste tipo perto de você.'),
              ),
            ),
          for (final l in visiveis) _cartao(l),
          const SizedBox(height: 12),
          Card(
            color: kTinta,
            child: ListTile(
              leading: const Icon(Icons.call, color: kPapel),
              title: const Text('Defesa Civil: 199', style: TextStyle(color: kPapel, fontWeight: FontWeight.w800)),
              subtitle: Text('Em risco, ligue antes de sair de casa.', style: TextStyle(color: kPapel.withValues(alpha: 0.8))),
              onTap: () => ligar('199'),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Locais indicados e avaliados pelos moradores. Não são abrigos oficiais da Defesa Civil.',
              style: TextStyle(fontSize: 12, color: kTintaSuave)),
        ],
      ),
    );
  }

  Widget _chip(String? tipo, String rotulo, IconData icone, Color cor) {
    final sel = _filtro == tipo;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(icone, size: 18, color: sel ? kPapel : cor),
        label: Text(rotulo),
        selected: sel,
        showCheckmark: false,
        selectedColor: cor,
        labelStyle: TextStyle(color: sel ? kPapel : kTinta, fontWeight: FontWeight.w700),
        onSelected: (_) => setState(() => _filtro = tipo),
      ),
    );
  }

  Widget _cartao(LocalSeguro l) {
    final ocupado = _ocupados.contains(l.id);
    final cor = corLocal(l.tipo);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _mapa.move(LatLng(l.latitude, l.longitude), 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 18, backgroundColor: cor, child: Icon(iconeLocal(l.tipo), color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(nomeTipoLocal(l.tipo), style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
              Etiqueta(l.distanciaKm < 1 ? '${(l.distanciaKm * 1000).round()} m' : '${l.distanciaKm.toStringAsFixed(1)} km', cor: kAreia),
            ]),
            if (l.descricao != null && l.descricao!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l.descricao!),
            ],
            const SizedBox(height: 6),
            Text(
              [if (l.bairro != null) l.bairro!, 'indicado ${_ha(l.criadoEm)}', if (l.meu) 'por você'].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: kTintaSuave),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.thumb_up_alt_outlined, size: 16, color: kMusgo),
              const SizedBox(width: 4),
              Text('${l.votosSeguro} é seguro', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 14),
              const Icon(Icons.thumb_down_alt_outlined, size: 16, color: kBrasa),
              const SizedBox(width: 4),
              Text('${l.votosInseguro} não é', style: const TextStyle(fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                  onPressed: () => abrirRota(l.latitude, l.longitude),
                  icon: const Icon(Icons.directions, size: 20),
                  label: const Text('Como chegar'),
                ),
              ),
              const SizedBox(width: 8),
              if (l.meu)
                IconButton.outlined(
                  tooltip: 'Remover do mapa',
                  onPressed: ocupado ? null : () => _acao(l.id, () => Api.removerLocal(l.id), 'Local removido.'),
                  icon: const Icon(Icons.delete_outline, color: kBrasa),
                )
              else ...[
                _voto(l, true, ocupado),
                const SizedBox(width: 6),
                _voto(l, false, ocupado),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  /// Botão de voto: fica preenchido quando é o voto atual da pessoa.
  Widget _voto(LocalSeguro l, bool seguro, bool ocupado) {
    final marcado = l.meuVoto == (seguro ? 'S' : 'N');
    final cor = seguro ? kMusgo : kBrasa;
    return IconButton(
      tooltip: seguro ? 'É seguro' : 'Não é seguro',
      style: IconButton.styleFrom(
        backgroundColor: marcado ? cor : Colors.transparent,
        side: BorderSide(color: cor, width: 1.4),
        minimumSize: const Size(42, 42),
      ),
      onPressed: ocupado || marcado
          ? null
          : () => _acao(l.id, () => Api.avaliarLocal(l.id, seguro), seguro ? 'Obrigado pela confirmação!' : 'Aviso registrado.'),
      icon: Icon(seguro ? Icons.thumb_up_alt_outlined : Icons.thumb_down_alt_outlined, color: marcado ? Colors.white : cor),
    );
  }
}

/// Indicar um local seguro: arraste o mapa até o pino, escolha o tipo e dê um nome.
class NovoLocalScreen extends StatefulWidget {
  final LatLng inicio;
  const NovoLocalScreen({super.key, required this.inicio});

  @override
  State<NovoLocalScreen> createState() => _NovoLocalScreenState();
}

class _NovoLocalScreenState extends State<NovoLocalScreen> {
  final _mapa = MapController();
  final _nome = TextEditingController();
  final _descricao = TextEditingController();
  String _tipo = 'PONTO_ALTO';
  late LatLng _centro = widget.inicio;
  bool _salvando = false;

  @override
  void dispose() {
    _mapa.dispose();
    _nome.dispose();
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _minhaPosicao() async {
    final p = await posicaoAtual();
    if (p != null && mounted) _mapa.move(p, 17);
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().length < 2) {
      aviso(context, 'Dê um nome para o local (ex.: "Estacionamento do mercado, piso 2").', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      await Api.cadastrarLocal(
          nome: _nome.text.trim(), tipo: _tipo, descricao: _descricao.text, latitude: _centro.latitude, longitude: _centro.longitude);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final explicacao = tiposLocal.firstWhere((t) => t.$1 == _tipo).$3;
    return Scaffold(
      appBar: AppBar(title: const Text('Indicar local seguro')),
      body: Column(children: [
        SizedBox(
          height: 260,
          child: Stack(children: [
            FlutterMap(
              mapController: _mapa,
              options: MapOptions(
                initialCenter: _centro,
                initialZoom: 16,
                onPositionChanged: (cam, _) => _centro = cam.center, // o pino fica fixo no centro
              ),
              children: [camadaBase(context), atribuicaoMapa()],
            ),
            IgnorePointer(
              child: Center(
                child: Padding(padding: const EdgeInsets.only(bottom: 44), child: MarcadorGota(cor: corLocal(_tipo), largura: 32)),
              ),
            ),
            const Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Arraste o mapa até o pino ficar em cima do local.', textAlign: TextAlign.center),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 30,
              child: FloatingActionButton.small(
                heroTag: 'local-minha-posicao',
                tooltip: 'Minha localização',
                backgroundColor: kPapelClaro,
                foregroundColor: kTinta,
                elevation: 0,
                onPressed: _minhaPosicao,
                child: const Icon(Icons.my_location),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
            const Text('Que tipo de local é?', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in tiposLocal)
                ChoiceChip(
                  avatar: Icon(iconeLocal(t.$1), size: 18, color: _tipo == t.$1 ? kPapel : corLocal(t.$1)),
                  label: Text(t.$2),
                  selected: _tipo == t.$1,
                  showCheckmark: false,
                  selectedColor: corLocal(t.$1),
                  labelStyle: TextStyle(color: _tipo == t.$1 ? kPapel : kTinta, fontWeight: FontWeight.w700),
                  onSelected: (_) => setState(() => _tipo = t.$1),
                ),
            ]),
            const SizedBox(height: 6),
            Text(explicacao, style: const TextStyle(color: kTintaSuave)),
            const SizedBox(height: 14),
            TextField(
              controller: _nome,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome do local', hintText: 'Ex.: Estacionamento do mercado, piso 2', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descricao,
              maxLength: 300,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Detalhes (opcional)', hintText: 'Ex.: aberto 24h, a água nunca chegou aqui'),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(onPressed: _salvando ? null : _salvar, icon: const Icon(Icons.check), label: const Text('Indicar local')),
            const SizedBox(height: 8),
            const Text('Os vizinhos do bairro recebem um aviso e podem avaliar se o local é mesmo seguro.',
                style: TextStyle(fontSize: 12.5, color: kTintaSuave)),
          ]),
        ),
      ]),
    );
  }
}

/// Kit de emergência: checklist de preparo. O que já foi separado fica salvo no aparelho.
class _Kit extends StatelessWidget {
  const _Kit();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<int>>(
      valueListenable: Preferencias.kit,
      builder: (context, prontos, _) {
        final total = itensKit.length;
        final n = prontos.where((i) => i < total).length;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(n == total ? Icons.verified_outlined : Icons.backpack_outlined, color: n == total ? kMusgo : kTinta),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Meu kit de emergência', style: Theme.of(context).textTheme.titleMedium)),
                    Text('$n de $total', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Deixe uma mochila pronta perto da porta. Marque o que você já separou.',
                      style: TextStyle(color: kTintaSuave)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: n / total, minHeight: 7, backgroundColor: kAreia, color: n == total ? kMusgo : kSinal),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < total; i++)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: kMusgo,
                  value: prontos.contains(i),
                  onChanged: (_) => Preferencias.alternarItemKit(i),
                  title: Text(
                    itensKit[i],
                    style: TextStyle(
                      fontSize: 15,
                      color: prontos.contains(i) ? kTintaSuave : kTinta,
                      decoration: prontos.contains(i) ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
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
        'Se a chuva apertar, leve o carro para um ponto alto antes de a água subir (veja os locais seguros).',
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
        const _Kit(),
        const SizedBox(height: 6),
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
