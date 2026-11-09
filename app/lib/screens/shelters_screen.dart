import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

/// Abrigos: (1) os que estão funcionando agora, marcados por moradores e confirmados
/// por vizinhos (guardados no Oracle); (2) locais perto de você que costumam virar
/// abrigo em enchentes (escolas, ginásios, centros comunitários do OpenStreetMap).
class _ListaAbrigosState extends State<_ListaAbrigos> with AutomaticKeepAliveClientMixin {
  final _mapa = MapController();
  LatLng _pos = kLocalPadrao;
  bool _semGps = false;
  List<Abrigo> _ativos = [];
  List<LocalApoio>? _locais; // null = busca no OpenStreetMap falhou
  bool _carregando = true;
  bool _semConexao = false;
  final _ocupados = <String>{}; // botões aguardando resposta

  @override
  bool get wantKeepAlive => true; // trocar para "O que fazer" e voltar não refaz a busca

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
    setState(() => _carregando = true);
    final gps = await posicaoAtual();
    final pos = gps ?? kLocalPadrao;
    // abrigos ativos (API) e locais do OpenStreetMap em paralelo
    final locais = buscarLocaisApoio(pos.latitude, pos.longitude);
    try {
      final ativos = await Api.abrigos(pos.latitude, pos.longitude);
      final l = await locais;
      if (!mounted) return;
      setState(() {
        _pos = pos;
        _semGps = gps == null;
        _ativos = ativos.where((a) => (a.distanciaKm ?? 0) <= 30).toList();
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

  /// Recarrega só os abrigos ativos (depois de marcar, confirmar ou encerrar).
  Future<void> _recarregarAtivos() async {
    try {
      final ativos = await Api.abrigos(_pos.latitude, _pos.longitude);
      if (mounted) setState(() => _ativos = ativos.where((a) => (a.distanciaKm ?? 0) <= 30).toList());
    } on ApiException catch (_) {}
  }

  Abrigo? _ativoDo(LocalApoio l) {
    for (final a in _ativos) {
      if (a.refOsm == l.refOsm) return a;
    }
    return null;
  }

  Future<void> _acao(String chave, Future<void> Function() f, String sucesso) async {
    setState(() => _ocupados.add(chave));
    try {
      await f();
      if (mounted) aviso(context, sucesso);
      await _recarregarAtivos();
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _ocupados.remove(chave));
    }
  }

  Future<void> _marcar(LocalApoio l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Este local está recebendo pessoas?'),
        content: Text(
          'Você vai avisar os vizinhos que "${l.nome}" está funcionando como abrigo agora. '
          'Marque só se você viu ou recebeu a informação da Defesa Civil, da escola ou da prefeitura.\n\n'
          'O aviso some em 24 horas se ninguém confirmar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sim, avisar')),
        ],
      ),
    );
    if (ok == true) await _acao(l.refOsm, () => Api.ativarAbrigo(l), 'Obrigado! Os vizinhos foram avisados.');
  }

  String _ha(DateTime? t) {
    if (t == null) return '';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 60) return 'há ${m < 1 ? 1 : m} min';
    final h = m ~/ 60;
    return h < 24 ? 'há $h h' : 'há ${h ~/ 24} dia(s)';
  }

  Color _corLocal(LocalApoio l) => switch (l.prioridade) { 0 => kAgua, 1 => kTinta, _ => kTintaSuave };

  void _focar(double lat, double lon) => _mapa.move(LatLng(lat, lon), 16);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_carregando) return const Esqueleto();
    if (_semConexao && _ativos.isEmpty && _locais == null) return EstadoTela.semConexao(aoTentar: _carregar);
    final locais = _locais ?? const <LocalApoio>[];
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
          // mapa com os locais e os abrigos ativos
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 250,
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
                    for (final l in locais)
                      if (_ativoDo(l) == null)
                        Marker(
                          point: LatLng(l.latitude, l.longitude),
                          width: 18,
                          height: 18,
                          child: Tooltip(
                            message: l.nome,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _corLocal(l),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ),
                    for (final a in _ativos)
                      Marker(
                        point: LatLng(a.latitude, a.longitude),
                        width: 30,
                        height: 42,
                        alignment: Alignment.topCenter,
                        child: Tooltip(message: '${a.nome} (funcionando)', child: const MarcadorGota(cor: kSinal, largura: 30)),
                      ),
                  ]),
                  atribuicaoMapa(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(spacing: 14, runSpacing: 4, children: [
            _Legenda(cor: kSinal, texto: 'funcionando agora'),
            _Legenda(cor: kAgua, texto: 'ginásio / centro comunitário'),
            _Legenda(cor: kTinta, texto: 'escola pública'),
            _Legenda(cor: kTintaSuave, texto: 'outras escolas'),
          ]),

          const Rotulo('Funcionando agora'),
          if (_ativos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhum abrigo marcado por moradores perto de você agora. '
                    'Se um dos locais abaixo estiver recebendo pessoas, toque em "Está aberto" para avisar os vizinhos.'),
              ),
            ),
          for (final a in _ativos) _cartaoAtivo(a),

          const Rotulo('Locais que costumam virar abrigo'),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Em enchentes, a Defesa Civil costuma abrir abrigos em escolas, ginásios e centros comunitários. '
              'Estes são os mais perto de você. Eles não estão abertos o tempo todo: confirme antes de ir.',
              style: TextStyle(color: kTintaSuave),
            ),
          ),
          if (_locais == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off, color: kBrasa),
                title: const Text('Não foi possível buscar os locais no mapa agora.'),
                trailing: TextButton(onPressed: _carregar, child: const Text('Tentar de novo')),
              ),
            )
          else if (locais.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhum local encontrado perto de você no OpenStreetMap.'))),
          for (final l in locais.take(25)) _cartaoLocal(l),

          const SizedBox(height: 12),
          Card(
            color: kTinta,
            child: ListTile(
              leading: const Icon(Icons.call, color: kPapel),
              title: const Text('Defesa Civil: 199', style: TextStyle(color: kPapel, fontWeight: FontWeight.w800)),
              subtitle: Text('Ligue para saber quais abrigos estão abertos.', style: TextStyle(color: kPapel.withValues(alpha: 0.8))),
              onTap: () => ligar('199'),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Locais: © OpenStreetMap contributors. Abrigos "funcionando agora" são informados pelos moradores.',
              style: TextStyle(fontSize: 12, color: kTintaSuave)),
        ],
      ),
    );
  }

  Widget _cartaoAtivo(Abrigo a) {
    final chave = 'a${a.id}';
    final ocupado = _ocupados.contains(chave);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kSinal, width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const MarcadorGota(cor: kSinal, largura: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(a.nome, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (a.distanciaKm != null) Etiqueta('${a.distanciaKm!.toStringAsFixed(1)} km', cor: kAreia),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Etiqueta(a.daComunidade ? 'Marcado por moradores' : 'Oficial', cor: a.daComunidade ? kSinal : kMusgo),
            Etiqueta('${a.confirmacoes} confirmação(ões)', cor: kAreia),
          ]),
          const SizedBox(height: 6),
          Text([
            if (a.endereco != null) a.endereco!,
            if (a.bairro != null) a.bairro!,
            if (a.daComunidade && a.criadoEm != null) 'aberto ${_ha(a.criadoEm)}',
          ].join(' · '), style: const TextStyle(color: kTintaSuave)),
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
            const SizedBox(width: 8),
            if (a.daComunidade && a.meu)
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), foregroundColor: kBrasa, side: const BorderSide(color: kBrasa)),
                  onPressed: ocupado ? null : () => _acao(chave, () => Api.encerrarAbrigo(a.id), 'Abrigo encerrado.'),
                  icon: const Icon(Icons.block),
                  label: const Text('Fechou/lotou'),
                ),
              )
            else if (a.daComunidade && !a.confirmadoPorMim)
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: ocupado ? null : () => _acao(chave, () => Api.confirmarAbrigo(a.id), 'Confirmação registrada.'),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Confirmar'),
                ),
              )
            else if (a.confirmadoPorMim)
              const Expanded(child: Center(child: Etiqueta('Você confirmou', cor: kMusgo, icone: Icons.check))),
          ]),
          if (a.telefone != null)
            TextButton.icon(onPressed: () => ligar(a.telefone!), icon: const Icon(Icons.call), label: Text(a.telefone!)),
        ]),
      ),
    );
  }

  Widget _cartaoLocal(LocalApoio l) {
    final ativo = _ativoDo(l);
    final ocupado = _ocupados.contains(l.refOsm);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _focar(l.latitude, l.longitude),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _corLocal(l), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(l.nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              Etiqueta(l.distanciaKm < 1 ? '${(l.distanciaKm * 1000).round()} m' : '${l.distanciaKm.toStringAsFixed(1)} km', cor: kAreia),
            ]),
            const SizedBox(height: 4),
            Text('${l.tipo}${l.endereco != null ? ' · ${l.endereco}' : ''}', style: const TextStyle(color: kTintaSuave)),
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
              Expanded(
                child: ativo != null
                    ? const Center(child: Etiqueta('Funcionando agora', cor: kSinal, icone: Icons.home_work))
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42), foregroundColor: kAgua, side: const BorderSide(color: kAgua)),
                        onPressed: ocupado ? null : () => _marcar(l),
                        icon: const Icon(Icons.campaign_outlined, size: 20),
                        label: const Text('Está aberto'),
                      ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  final Color cor;
  final String texto;
  const _Legenda({required this.cor, required this.texto});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(texto, style: const TextStyle(fontSize: 12, color: kTintaSuave)),
      ]);
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
