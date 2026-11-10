import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../cidades_br.dart';
import '../models.dart';
import '../risco_enchente.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';
import 'locais_screen.dart';
import 'lugares_screen.dart';
import 'report_screen.dart';

/// Lugares do app para onde a tela Início pode levar.
enum Destino { risco, relatos, clima, locaisSeguros, kit, sos, conta }

/// De onde veio o ponto usado nos cálculos.
enum _Origem { gps, lugar, padrao }

/// Tela inicial: responde "estou em risco agora?" para o ponto exato do morador.
///
/// Junta num só lugar o risco de enchente calculado para a posição atual, a chuva
/// acumulada, os alertas de clima, os lugares salvos e o que a vizinhança relatou.
/// O último resultado fica guardado no aparelho: aparece na hora ao abrir o app e
/// continua visível se a internet cair.
class InicioScreen extends StatefulWidget {
  final String? nome;
  final void Function(Destino) aoIr;
  const InicioScreen({super.key, this.nome, required this.aoIr});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  static final _cidades = gerarCidadesBrasil();
  static const _raioRelatosKm = 10.0;

  int _vez = 0; // descarta respostas de uma atualização antiga
  bool _carregando = true;
  bool _semInternet = false; // previsão do tempo não respondeu
  bool _semServidor = false; // API do Dilu não respondeu

  LatLng? _pos;
  _Origem _origem = _Origem.gps;
  String? _apelidoOrigem;
  String _local = '';

  RetratoInicio? _retrato;
  RiscoCidade? _aqui;
  List<Lugar> _lugares = [];
  final _riscoLugares = <int, RiscoCidade>{};
  Clima? _clima;
  ChuvaAcumulada? _acumulada;
  List<Alagamento>? _relatos;
  List<LocalSeguro>? _locais;
  DateTime? _atualizadoEm;

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  Future<void> _abrir() async {
    final salvo = await Preferencias.lerRetrato();
    if (mounted && salvo != null) setState(() => _retrato = salvo);
    await _carregar();
  }

  /// Nome amigável do ponto: a cidade conhecida mais próxima.
  String _rotuloLocal(LatLng p) {
    final c = cidadeMaisProxima(_cidades, p, maxKm: double.infinity);
    if (c == null) return 'Seu local';
    final km = const Distance().as(LengthUnit.Kilometer, p, c.centro);
    return km <= 40 ? '${c.nome} · ${c.uf}' : 'a ${km.round()} km de ${c.nome} · ${c.uf}';
  }

  Future<List<Lugar>?> _buscarLugares() async {
    try {
      return await Api.lugares();
    } on ApiException {
      return null;
    }
  }

  Future<void> _carregar() async {
    final vez = ++_vez;
    setState(() => _carregando = true);

    // posição e lugares salvos ao mesmo tempo; a posição tem limite de espera
    // para a tela não ficar presa se o navegador não responder ao pedido de GPS
    final r = await Future.wait<Object?>([
      posicaoAtual().timeout(const Duration(seconds: 12), onTimeout: () => null),
      _buscarLugares(),
    ]);
    if (!mounted || vez != _vez) return;
    final gps = r[0] as LatLng?;
    final lugares = r[1] as List<Lugar>?;

    // sem GPS, usa a casa (ou o primeiro lugar salvo); só no fim, o ponto padrão
    Lugar? casa;
    if (gps == null && lugares != null && lugares.isNotEmpty) {
      casa = lugares.firstWhere((l) => l.tipo == 'CASA', orElse: () => lugares.first);
    }
    final pos = gps ?? (casa != null ? LatLng(casa.latitude, casa.longitude) : kLocalPadrao);
    setState(() {
      _pos = pos;
      _origem = gps != null ? _Origem.gps : (casa != null ? _Origem.lugar : _Origem.padrao);
      _apelidoOrigem = casa?.apelido;
      _local = _rotuloLocal(pos);
      _lugares = lugares ?? _lugares;
      _semServidor = lugares == null;
    });

    // cada bloco preenche a tela assim que chega
    await Future.wait([
      _carregarRisco(vez, pos, lugares ?? const []),
      _carregarClima(vez, pos),
      _carregarVizinhanca(vez, pos),
    ]);
    if (!mounted || vez != _vez) return;
    setState(() => _carregando = false);
    _guardarRetrato();
  }

  /// Risco de enchente do ponto atual e de cada lugar salvo, numa só consulta.
  Future<void> _carregarRisco(int vez, LatLng pos, List<Lugar> lugares) async {
    final aqui = RiscoCidade(CelulaClima(centro: pos, nome: 'Aqui'));
    final dosLugares = {
      for (final l in lugares) l.id: RiscoCidade(CelulaClima(centro: LatLng(l.latitude, l.longitude), nome: l.apelido)),
    };
    final ok = await buscarRisco([aqui, ...dosLugares.values]);
    if (!mounted || vez != _vez) return;
    setState(() {
      _semInternet = !ok;
      if (ok && aqui.temDados) {
        _aqui = aqui;
        _atualizadoEm = DateTime.now();
        _riscoLugares
          ..clear()
          ..addAll(dosLugares);
      }
    });
  }

  Future<void> _carregarClima(int vez, LatLng pos) async {
    final r = await Future.wait<Object?>([
      buscarClima(pos.latitude, pos.longitude),
      buscarChuvaAcumulada(pos.latitude, pos.longitude),
    ]);
    if (!mounted || vez != _vez) return;
    setState(() {
      _clima = (r[0] as Clima?) ?? _clima;
      _acumulada = (r[1] as ChuvaAcumulada?) ?? _acumulada;
    });
  }

  /// Relatos e locais seguros perto do ponto (vêm do banco do Dilu).
  Future<void> _carregarVizinhanca(int vez, LatLng pos) async {
    try {
      final r = await Future.wait<Object>([
        Api.alagamentos(pos.latitude, pos.longitude, raioKm: _raioRelatosKm),
        Api.locaisSeguros(pos.latitude, pos.longitude),
      ]);
      if (!mounted || vez != _vez) return;
      setState(() {
        _relatos = r[0] as List<Alagamento>;
        _locais = r[1] as List<LocalSeguro>;
      });
    } on ApiException {
      if (mounted && vez == _vez) setState(() => _semServidor = true);
    }
  }

  List<AlertaClima> get _alertas => [
        if (_acumulada != null && alertaChuvaAcumulada(_acumulada!) != null) alertaChuvaAcumulada(_acumulada!)!,
        if (_clima != null) ...alertasDoClima(_clima!),
      ];

  /// Relato ativo mais próximo, se estiver a até 2 km (entra no painel de risco).
  Alagamento? get _relatoBemPerto {
    Alagamento? perto;
    for (final a in _relatos ?? const <Alagamento>[]) {
      final km = a.distanciaKm;
      if (km != null && km <= 2 && (perto == null || km < perto.distanciaKm!)) perto = a;
    }
    return perto;
  }

  void _guardarRetrato() {
    final a = _aqui;
    if (a == null || !a.temDados || _semInternet) return;
    final novo = RetratoInicio(
      quando: _atualizadoEm ?? DateTime.now(),
      local: _local,
      nivel: a.nivel,
      chuva3dias: a.chuvaRecente3d ?? 0,
      chuvaPrevista: a.chuvaPrevista3d ?? 0,
      alertas: _alertas,
    );
    _retrato = novo;
    Preferencias.salvarRetrato(novo);
  }

  Future<void> _adicionarCasa() async {
    final salvou = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const NovoLugarScreen()));
    if (salvou == true) _carregar();
  }

  Future<void> _relatar() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(inicial: _pos ?? kLocalPadrao, temGps: _pos != null && _origem == _Origem.gps)),
    );
    if (ok == true) _carregar();
  }

  String _saudacao() {
    final h = DateTime.now().hour;
    final periodo = h < 5 ? 'Boa noite' : (h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite'));
    final nome = widget.nome?.trim().split(' ').first;
    return (nome == null || nome.isEmpty) ? periodo : '$periodo, $nome';
  }

  static String _dist(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm');
    final aoVivo = _aqui != null && !_semInternet;
    final alertas = aoVivo ? _alertas : (_retrato?.alertas ?? const <AlertaClima>[]);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Text(_saudacao(), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          if (_semInternet && _retrato != null)
            _Faixa(
              icone: Icons.cloud_off,
              texto: 'Sem internet. Mostrando os dados de ${fmt.format(_retrato!.quando)}.',
              acao: 'Tentar de novo',
              aoTocar: _carregar,
            )
          else if (!_carregando && _origem == _Origem.lugar)
            _Faixa(icone: Icons.location_off_outlined, texto: 'Sem GPS agora: mostrando o lugar salvo "$_apelidoOrigem".')
          else if (!_carregando && _origem == _Origem.padrao)
            _Faixa(
              icone: Icons.location_off_outlined,
              texto: 'Sem localização: mostrando o centro de São Paulo. Permita a localização ou salve a sua casa.',
              acao: 'Salvar minha casa',
              aoTocar: _adicionarCasa,
            ),
          _painelRisco(aoVivo),
          const Rotulo('Chuva e clima neste ponto'),
          _cartaoClima(),
          if (alertas.isNotEmpty) const SizedBox(height: 2),
          for (final a in alertas) _CartaoAlerta(a),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kSinal, foregroundColor: kTinta, minimumSize: const Size.fromHeight(56)),
                  onPressed: _relatar,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Relatar alagamento')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kBrasa, side: const BorderSide(color: kBrasa, width: 1.6), minimumSize: const Size.fromHeight(56)),
                  onPressed: () => widget.aoIr(Destino.sos),
                  icon: const Icon(Icons.crisis_alert),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Preciso de ajuda')),
                ),
              ),
            ]),
          ),
          const Rotulo('Seus lugares'),
          _cartaoLugares(),
          const Rotulo('Perto de você'),
          _cartaoVizinhanca(),
          const Rotulo('Seu preparo'),
          _cartaoKit(),
          const SizedBox(height: 14),
          Text(
            '${_atualizadoEm != null ? 'Atualizado às ${DateFormat('HH:mm').format(_atualizadoEm!)}. ' : ''}'
            'Risco e chuva: estimativa do Dilu com dados do Open-Meteo. Relatos e locais seguros: moradores.',
            style: const TextStyle(fontSize: 12, color: kTintaSuave),
          ),
        ],
      ),
    );
  }

  // ---- painel principal: o risco no ponto do morador -------------------------
  Widget _painelRisco(bool aoVivo) {
    final a = _aqui;
    final String? nivel = aoVivo ? a!.nivel : _retrato?.nivel;
    final local = aoVivo || _retrato == null ? _local : _retrato!.local;
    final recente = aoVivo ? a!.chuvaRecente3d : _retrato?.chuva3dias;
    final prevista = aoVivo ? a!.chuvaPrevista3d : _retrato?.chuvaPrevista;
    final papel70 = kPapel.withValues(alpha: 0.72);

    Widget conteudo;
    if (nivel == null) {
      conteudo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_carregando ? 'Calculando o risco no seu ponto…' : 'Não foi possível calcular o risco agora.',
            style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600, color: kPapel, height: 1.2)),
        const SizedBox(height: 14),
        if (_carregando)
          const LinearProgressIndicator(backgroundColor: Colors.white24)
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kPapel, side: const BorderSide(color: kPapel), minimumSize: const Size(0, 44)),
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
      ]);
    } else {
      final posicao = niveisRisco.indexOf(nivel);
      final indice = posicao < 0 ? 0 : posicao;
      conteudo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fraseRisco(nivel), style: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w600, color: kPapel, height: 1.15)),
        const SizedBox(height: 8),
        Text(orientacaoRisco(nivel), style: TextStyle(fontSize: 14.5, color: kPapel.withValues(alpha: 0.85), height: 1.35)),
        // o que os vizinhos viram pesa junto com a estimativa de chuva
        if (_relatoBemPerto != null) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.groups_outlined, size: 19, color: kSinal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vizinhos relataram alagamento a ${_dist(_relatoBemPerto!.distanciaKm!)} de você.',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kSinal),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        _EscalaRisco(indice: indice),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Numero(valor: '${(recente ?? 0).round()} mm', rotulo: 'nos últimos 3 dias')),
          Expanded(child: _Numero(valor: '${(prevista ?? 0).round()} mm', rotulo: 'previstos em 3 dias')),
          if (aoVivo && a!.reforcoRio) const Expanded(child: _Numero(valor: 'Rio alto', rotulo: 'vazão acima da média')),
        ]),
        if (indice >= 2) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSinal, foregroundColor: kTinta, minimumSize: const Size.fromHeight(48)),
            onPressed: () => ligar('199'),
            icon: const Icon(Icons.call),
            label: const Text('Ligar para a Defesa Civil (199)'),
          ),
        ],
      ]);
    }

    return Semantics(
      container: true,
      label: nivel == null ? 'Risco de enchente' : 'Risco de enchente ${rotuloNivel(nivel)} em $local',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: kTinta, borderRadius: BorderRadius.circular(16)),
        child: Stack(children: [
          const Positioned.fill(child: Ondas()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Gota(largura: 11, cor: nivel == null ? kSinal : corNivel(nivel)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'RISCO DE ENCHENTE${local.isEmpty ? '' : ' · ${local.toUpperCase()}'}',
                    style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: papel70),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              conteudo,
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text('Estimativa do Dilu para este ponto. Não é alerta oficial.',
                      style: TextStyle(fontSize: 11.5, color: kPapel.withValues(alpha: 0.6))),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: kPapel, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  onPressed: () => widget.aoIr(Destino.risco),
                  child: const Text('Mapa do Brasil'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---- chuva acumulada + resumo das próximas 12 horas -------------------------
  Widget _cartaoClima() {
    final c = _clima;
    if (_acumulada == null && c == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _carregando
              ? const LinearProgressIndicator()
              : const Text('Previsão indisponível agora. Puxe a tela para baixo para tentar de novo.', style: TextStyle(color: kTintaSuave)),
        ),
      );
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.aoIr(Destino.clima),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_acumulada != null) ...[
              const Text('Chuva que já caiu e a prevista (mm)', style: TextStyle(fontSize: 12.5, color: kTintaSuave)),
              const SizedBox(height: 6),
              ChuvaAcumuladaLinha(chuva: _acumulada!),
            ],
            if (c != null) ...[
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _Fato(icone: Icons.umbrella_outlined, valor: '${c.chuva.probabilidadeMax}%', rotulo: 'chance de chuva em 12h')),
                Expanded(child: _Fato(icone: Icons.thermostat, valor: '${c.calor.sensacaoMax.round()}°', rotulo: 'sensação máxima')),
                Expanded(
                  child: c.ar != null
                      ? _Fato(icone: Icons.air, valor: '${c.ar!.aqi}', rotulo: rotuloAr(c.ar!.aqi).toLowerCase())
                      : _Fato(icone: Icons.wb_sunny_outlined, valor: c.calor.uvMax.round().toString(), rotulo: 'UV máximo'),
                ),
              ]),
            ],
            if (_clima != null && _acumulada != null && _alertas.isEmpty) ...[
              const SizedBox(height: 10),
              const Row(children: [
                Icon(Icons.check_circle_outline, size: 18, color: kMusgo),
                SizedBox(width: 6),
                Expanded(child: Text('Sem alertas de chuva, calor, UV ou ar para as próximas horas.', style: TextStyle(fontSize: 13))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  // ---- lugares salvos, cada um com o seu nível de risco ------------------------
  Widget _cartaoLugares() {
    if (_lugares.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_semServidor
                ? 'Sem conexão com o servidor do Dilu: seus lugares não puderam ser carregados.'
                : 'Salve sua casa, o trabalho ou a faculdade para ver o risco de enchente de cada um aqui, mesmo quando você estiver longe.'),
            if (!_semServidor) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: _adicionarCasa,
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Salvar minha casa'),
              ),
            ],
          ]),
        ),
      );
    }
    return Card(
      child: Column(children: [
        for (var i = 0; i < _lugares.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
          _linhaLugar(_lugares[i]),
        ],
      ]),
    );
  }

  Widget _linhaLugar(Lugar l) {
    final r = _riscoLugares[l.id];
    return InkWell(
      onTap: () => widget.aoIr(Destino.conta),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(iconeLugar(l.tipo), color: kTinta),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.apelido, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              Text(
                r != null && r.temDados
                    ? '${r.chuvaRecente3d!.round()} mm em 3 dias · ${r.chuvaPrevista3d!.round()} mm previstos'
                    : (l.bairro ?? 'Toque para ver a chuva'),
                style: const TextStyle(fontSize: 12.5, color: kTintaSuave),
              ),
            ]),
          ),
          if (r != null && r.temDados)
            Etiqueta(rotuloNivel(r.nivel), cor: corNivel(r.nivel))
          else if (_carregando)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
    );
  }

  // ---- o que a vizinhança relatou e indicou -------------------------------------
  Widget _cartaoVizinhanca() {
    final relatos = _relatos;
    final locais = _locais;
    if (relatos == null || locais == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _semServidor
              ? Row(children: [
                  const Icon(Icons.cloud_off, color: kBrasa),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Sem conexão com o servidor do Dilu: relatos e locais seguros indisponíveis.')),
                  TextButton(onPressed: _carregar, child: const Text('Tentar')),
                ])
              : const LinearProgressIndicator(),
        ),
      );
    }
    Alagamento? perto;
    for (final a in relatos) {
      if (perto == null || (a.distanciaKm ?? 1e9) < (perto.distanciaKm ?? 1e9)) perto = a;
    }
    final local = locais.isEmpty ? null : locais.first; // a API já devolve do mais próximo ao mais distante
    return Card(
      child: Column(children: [
        _LinhaVizinhanca(
          icone: SizedBox(width: 26, child: Center(child: MarcadorGota(cor: perto == null ? kMusgo : corGravidade(perto.gravidade), largura: 20))),
          titulo: relatos.isEmpty
              ? 'Nenhum alagamento relatado por perto'
              : (relatos.length == 1 ? '1 alagamento relatado por perto' : '${relatos.length} alagamentos relatados por perto'),
          detalhe: perto == null
              ? 'Nos últimos relatos, em até ${_raioRelatosKm.round()} km.'
              : 'O mais próximo: ${rotuloGravidade(perto.gravidade).toLowerCase()}'
                  '${perto.distanciaKm != null ? ', a ${_dist(perto.distanciaKm!)}' : ''}'
                  '${perto.bairro != null ? ' · ${perto.bairro}' : ''}',
          acao: 'Ver',
          aoTocar: () => widget.aoIr(Destino.relatos),
        ),
        const Divider(height: 1, indent: 14, endIndent: 14),
        _LinhaVizinhanca(
          icone: CircleAvatar(
            radius: 13,
            backgroundColor: local == null ? kAreia : corLocal(local.tipo),
            child: Icon(local == null ? Icons.shield_outlined : iconeLocal(local.tipo), size: 15, color: local == null ? kTinta : Colors.white),
          ),
          titulo: local == null ? 'Nenhum local seguro indicado por perto' : local.nome,
          detalhe: local == null
              ? 'Conhece um ponto alto ou um lugar que acolhe pessoas? Indique.'
              : '${nomeTipoLocal(local.tipo)} · a ${_dist(local.distanciaKm)}'
                  '${locais.length > 1 ? ' · mais ${locais.length - 1} por perto' : ''}',
          acao: local == null ? 'Indicar' : 'Ver',
          aoTocar: () => widget.aoIr(Destino.locaisSeguros),
        ),
      ]),
    );
  }

  // ---- kit de emergência ----------------------------------------------------------
  Widget _cartaoKit() => ValueListenableBuilder<Set<int>>(
        valueListenable: Preferencias.kit,
        builder: (_, prontos, _) {
          final total = itensKit.length;
          final n = prontos.where((i) => i < total).length;
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.aoIr(Destino.kit),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(n == total ? Icons.verified_outlined : Icons.backpack_outlined, color: n == total ? kMusgo : kTinta),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n == total ? 'Kit de emergência completo' : 'Kit de emergência: $n de $total itens prontos',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: n / total, minHeight: 7, backgroundColor: kAreia, color: n == total ? kMusgo : kSinal),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: kTintaSuave),
                ]),
              ),
            ),
          );
        },
      );
}

/// Régua de quatro degraus: acende até o nível atual, cada degrau na sua cor.
class _EscalaRisco extends StatelessWidget {
  final int indice;
  const _EscalaRisco({required this.indice});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < niveisRisco.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 3 ? 5 : 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: i <= indice ? corNivel(niveisRisco[i]) : kPapel.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: i == 3 && indice == 3 ? Border.all(color: kPapel.withValues(alpha: 0.5)) : null,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                rotuloNivel(niveisRisco[i]),
                style: GoogleFonts.manrope(
                  fontSize: 11.5,
                  fontWeight: i == indice ? FontWeight.w800 : FontWeight.w500,
                  color: i == indice ? kPapel : kPapel.withValues(alpha: 0.5),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Número grande em texto claro (dentro do painel escuro).
class _Numero extends StatelessWidget {
  final String valor;
  final String rotulo;
  const _Numero({required this.valor, required this.rotulo});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(valor, style: GoogleFonts.fraunces(fontSize: 20, fontWeight: FontWeight.w600, color: kPapel)),
        Text(rotulo, style: TextStyle(fontSize: 12, color: kPapel.withValues(alpha: 0.7))),
      ]);
}

/// Dado curto com ícone (resumo do clima).
class _Fato extends StatelessWidget {
  final IconData icone;
  final String valor;
  final String rotulo;
  const _Fato({required this.icone, required this.valor, required this.rotulo});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 18, color: kAgua),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(valor, style: GoogleFonts.manrope(fontSize: 15.5, fontWeight: FontWeight.w800)),
            Text(rotulo, style: const TextStyle(fontSize: 11.5, color: kTintaSuave)),
          ]),
        ),
      ]);
}

/// Aviso em faixa (sem internet, sem GPS...).
class _Faixa extends StatelessWidget {
  final IconData icone;
  final String texto;
  final String? acao;
  final VoidCallback? aoTocar;
  const _Faixa({required this.icone, required this.texto, this.acao, this.aoTocar});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(color: kAreia, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icone, size: 20, color: kTinta),
          const SizedBox(width: 10),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(texto, style: const TextStyle(fontSize: 13.5)))),
          if (acao != null) TextButton(onPressed: aoTocar, child: Text(acao!)),
        ]),
      );
}

/// Alerta de clima com a borda na cor do nível.
class _CartaoAlerta extends StatelessWidget {
  final AlertaClima alerta;
  const _CartaoAlerta(this.alerta);

  @override
  Widget build(BuildContext context) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: corNivel(alerta.nivel), width: 2)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(alerta.titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
              Etiqueta(rotuloNivel(alerta.nivel), cor: corNivel(alerta.nivel)),
            ]),
            const SizedBox(height: 6),
            Text(alerta.mensagem),
          ]),
        ),
      );
}

class _LinhaVizinhanca extends StatelessWidget {
  final Widget icone;
  final String titulo;
  final String detalhe;
  final String acao;
  final VoidCallback aoTocar;
  const _LinhaVizinhanca({required this.icone, required this.titulo, required this.detalhe, required this.acao, required this.aoTocar});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            icone,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(detalhe, style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
              ]),
            ),
            TextButton(onPressed: aoTocar, child: Text(acao)),
          ]),
        ),
      );
}
