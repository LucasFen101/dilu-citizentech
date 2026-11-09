import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Aba "Conta": dados do morador, números pessoais, os relatos que ele fez,
/// preferências e informações sobre o Dilu (ODS, fontes dos dados e limites).
class ContaScreen extends StatefulWidget {
  final Future<void> Function() aoSair;
  const ContaScreen({super.key, required this.aoSair});

  @override
  State<ContaScreen> createState() => _ContaScreenState();
}

class _ContaScreenState extends State<ContaScreen> {
  Map<String, dynamic>? _eu;
  ResumoUsuario? _resumo;
  List<MeuRelato> _relatos = [];
  bool _carregando = true;
  bool _semConexao = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final res = await Future.wait([Api.eu(), Api.resumo(), Api.meusRelatos()]);
      if (!mounted) return;
      setState(() {
        _eu = res[0] as Map<String, dynamic>;
        _resumo = res[1] as ResumoUsuario;
        _relatos = res[2] as List<MeuRelato>;
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

  Future<void> _encerrar(MeuRelato r) async {
    try {
      await Api.resolver(r.id);
      if (mounted) aviso(context, 'Relato marcado como resolvido.');
      await _carregar();
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    }
  }

  Future<void> _sair() async {
    final sair = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
        ],
      ),
    );
    if (sair == true) await widget.aoSair();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Esqueleto(cartoes: 3);
    if (_semConexao && _eu == null) {
      return EstadoTela.semConexao(aoTentar: () {
        setState(() => _carregando = true);
        _carregar();
      });
    }
    final nome = (_eu?['nome'] as String?) ?? 'Morador';
    final bairro = _eu?['bairro'] as String?;
    final r = _resumo;
    final fmt = DateFormat('dd/MM HH:mm');
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // cabeçalho com a inicial do nome
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: kTinta,
                  child: Text(nome.characters.first.toUpperCase(),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: kPapel)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nome, style: Theme.of(context).textTheme.titleLarge),
                    Text((_eu?['email'] as String?) ?? '', style: const TextStyle(color: kTintaSuave)),
                    const SizedBox(height: 6),
                    if (bairro != null)
                      Etiqueta(bairro, cor: kAreia, icone: Icons.location_on_outlined)
                    else
                      const Text('Bairro ainda não identificado', style: TextStyle(fontSize: 12.5, color: kTintaSuave)),
                  ]),
                ),
              ]),
            ),
          ),
          const Rotulo('Meus números'),
          if (r != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(runSpacing: 14, children: [
                  for (final i in [
                    ('${r.relatosTotal}', 'relatos feitos'),
                    ('${r.relatosResolvidos}', 'relatos resolvidos'),
                    ('${r.confirmacoesRecebidas}', 'confirmações nos meus relatos'),
                    ('${r.confirmacoesDadas}', 'relatos que confirmei'),
                    ('${r.pedidosAjuda}', 'pedidos de ajuda'),
                    ('${r.relatosAtivos}', 'relatos ativos agora'),
                  ])
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.$1, style: Theme.of(context).textTheme.headlineSmall),
                        Text(i.$2, style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
                      ]),
                    ),
                ]),
              ),
            ),
          const Rotulo('Meus relatos'),
          if (_relatos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Você ainda não relatou nenhum alagamento. Quando relatar, ele aparece aqui.'),
              ),
            ),
          for (final m in _relatos)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Etiqueta(rotuloGravidade(m.gravidade), cor: corGravidade(m.gravidade)),
                    const SizedBox(width: 8),
                    Etiqueta(
                      switch (m.status) { 'ATIVO' => 'Ativo', 'RESOLVIDO' => 'Resolvido', _ => 'Expirado' },
                      cor: switch (m.status) { 'ATIVO' => kSinal, 'RESOLVIDO' => kMusgo, _ => kAreia },
                    ),
                    const Spacer(),
                    Text('${m.confirmacoes} confirmação(ões)', style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
                  ]),
                  const SizedBox(height: 8),
                  Text(m.descricao?.isNotEmpty == true ? m.descricao! : descricaoGravidade(m.gravidade)),
                  const SizedBox(height: 4),
                  Text('${m.bairro ?? 'Local sem bairro'}${m.criadoEm != null ? ' · ${fmt.format(m.criadoEm!)}' : ''}',
                      style: const TextStyle(fontSize: 12.5, color: kTintaSuave)),
                  if (m.status == 'ATIVO') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      onPressed: () => _encerrar(m),
                      icon: const Icon(Icons.done_all),
                      label: const Text('A água baixou: encerrar'),
                    ),
                  ],
                ]),
              ),
            ),
          const Rotulo('Preferências'),
          Card(
            child: ValueListenableBuilder<bool>(
              valueListenable: Preferencias.textoGrande,
              builder: (_, grande, _) => SwitchListTile(
                value: grande,
                onChanged: (_) => Preferencias.alternarTextoGrande(),
                activeThumbColor: kTinta,
                title: const Text('Texto grande', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Aumenta as letras do app inteiro.'),
              ),
            ),
          ),
          const Rotulo('Sobre o Dilu'),
          Card(
            child: Column(children: const [
              ExpansionTile(
                leading: Icon(Icons.public, color: kAgua),
                title: Text('Objetivos de Desenvolvimento Sustentável', style: TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Ods('ODS 11 · Cidades e comunidades sustentáveis',
                      'Meta 11.5: reduzir o número de pessoas afetadas por desastres relacionados à água. O Dilu mostra onde há risco de enchente, '
                          'reúne relatos da vizinhança e indica abrigos e telefones de emergência.'),
                  _Ods('ODS 13 · Ação contra a mudança global do clima',
                      'Meta 13.1: reforçar a resiliência e a capacidade de adaptação a riscos relacionados ao clima. O app acompanha chuva, calor e umidade '
                          'em todo o Brasil e orienta o que fazer antes, durante e depois de eventos extremos.'),
                  _Ods('ODS 3 · Saúde e bem-estar',
                      'Alertas de calor extremo, UV muito alto e ar poluído (como fumaça de queimadas), com orientações para idosos, crianças '
                          'e quem tem asma, além do botão de emergência que avisa contatos e vizinhos.'),
                ],
              ),
              Divider(height: 1),
              ExpansionTile(
                leading: Icon(Icons.storage_outlined, color: kAgua),
                title: Text('De onde vêm os dados', style: TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Linha('Mapa', '© OpenStreetMap contributors, licença ODbL.'),
                  _Linha('Chuva, temperatura, umidade, vento e UV', 'Previsão do Open-Meteo, para 83 cidades do Brasil.'),
                  _Linha('Qualidade do ar', 'Índice US AQI e partículas finas (PM2,5) do Open-Meteo Air Quality (modelo CAMS, da União Europeia).'),
                  _Linha('Radar de chuva', 'Imagens das últimas 2 horas do RainViewer, que reúne radares meteorológicos do mundo todo.'),
                  _Linha('Vazão dos rios', 'Modelo global GloFAS, pela API de enchentes do Open-Meteo.'),
                  _Linha('Relatos e confirmações', 'Feitos pelos moradores e guardados no banco Oracle do Dilu.'),
                  _Linha('Locais de abrigo', 'Escolas, ginásios e centros comunitários do OpenStreetMap (consulta Overpass).'),
                ],
              ),
              Divider(height: 1),
              ExpansionTile(
                leading: Icon(Icons.info_outline, color: kAgua),
                title: Text('Limites importantes', style: TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Linha('Risco estimado', 'É uma estimativa por modelo, a partir da chuva acumulada e prevista. Não substitui os alertas oficiais da Defesa Civil.'),
                  _Linha('Previsão por cidade', 'Representa o centro da cidade. Para ver a chuva real, ligue o radar na aba Clima.'),
                  _Linha('Radar', 'A cobertura de radares no Brasil não é completa: em partes do Norte e do Centro-Oeste pode haver chuva que o radar não mostra.'),
                  _Linha('Abrigos', 'Os locais da lista são escolas, ginásios e centros comunitários que costumam virar abrigo, não abrigos abertos. '
                      '"Funcionando agora" é informado pelos moradores. Confirme sempre com a Defesa Civil (199).'),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kBrasa, side: const BorderSide(color: kBrasa, width: 1.4)),
            onPressed: _sair,
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Sair da conta'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Ods extends StatelessWidget {
  final String titulo;
  final String texto;
  const _Ods(this.titulo, this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(texto, style: const TextStyle(color: kTintaSuave)),
        ]),
      );
}

class _Linha extends StatelessWidget {
  final String titulo;
  final String texto;
  const _Linha(this.titulo, this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(texto, style: const TextStyle(color: kTintaSuave)),
        ]),
      );
}
