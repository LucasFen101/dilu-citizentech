import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Botões de emergência, contatos de confiança e telefones úteis.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  List<Contato> _contatos = [];
  bool _carregando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final c = await Api.contatos();
      if (mounted) setState(() => _contatos = c);
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Registra o pedido no banco (que avisa os vizinhos) e oferece avisar os contatos.
  Future<void> _emergencia(String tipo) async {
    final pedirAjuda = tipo == 'AJUDA';
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(pedirAjuda ? Icons.crisis_alert : Icons.verified_user, color: pedirAjuda ? kBrasa : kMusgo, size: 40),
        title: Text(pedirAjuda ? 'Pedir ajuda agora?' : 'Avisar que está seguro?'),
        content: Text(pedirAjuda
            ? 'Vamos avisar os moradores do seu bairro e preparar uma mensagem com a sua localização para os seus contatos. '
                'Se a vida estiver em risco, ligue 193 agora.'
            : 'Vamos encerrar seus pedidos de ajuda e preparar uma mensagem tranquilizando seus contatos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size(120, 44), backgroundColor: pedirAjuda ? kBrasa : kMusgo),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(pedirAjuda ? 'Pedir ajuda' : 'Estou seguro'),
          ),
        ],
      ),
    );
    if (confirma != true) return;

    setState(() => _enviando = true);
    try {
      // só o pedido de ajuda precisa do ponto no mapa. Sem GPS (ou se demorar demais),
      // o pedido vai sem localização: nunca com um ponto inventado.
      final pos = pedirAjuda ? await posicaoAtual().timeout(const Duration(seconds: 8), onTimeout: () => null) : null;
      final r = await Api.emergencia(tipo, pos?.latitude, pos?.longitude, null);
      if (!mounted) return;
      final msg = mensagemEmergencia(
        pedirAjuda: pedirAjuda,
        nome: r.nomeUsuario,
        link: pos == null ? null : linkMapa(pos.latitude, pos.longitude),
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AvisarContatos(resultado: r, mensagem: msg, pedirAjuda: pedirAjuda, comLocalizacao: pos != null),
      );
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _novoContato() async {
    final nome = TextEditingController();
    final tel = TextEditingController();
    final par = TextEditingController();
    final chave = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo contato de emergência'),
        content: Form(
          key: chave,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: nome,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone com DDD', hintText: '11 91234-5678'),
              validator: (v) => (v == null || v.replaceAll(RegExp(r'\D'), '').length < 10) ? 'Telefone inválido' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(controller: par, decoration: const InputDecoration(labelText: 'Parentesco (opcional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () {
              if (chave.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final dados = (nome.text.trim(), tel.text.trim(), par.text.trim());
    nome.dispose();
    tel.dispose();
    par.dispose();
    if (ok != true) return;
    try {
      await Api.criarContato(dados.$1, dados.$2, dados.$3.isEmpty ? null : dados.$3);
      await _carregar();
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    }
  }

  Future<void> _remover(Contato c) async {
    try {
      await Api.removerContato(c.id);
      await _carregar();
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 96,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kBrasa, textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            onPressed: _enviando ? null : () => _emergencia('AJUDA'),
            icon: _enviando ? const SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)) : const Icon(Icons.crisis_alert, size: 36),
            label: const Text('PRECISO DE AJUDA'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kMusgo),
            onPressed: _enviando ? null : () => _emergencia('SEGURO'),
            icon: const Icon(Icons.verified_user),
            label: const Text('ESTOU SEGURO'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '"Preciso de ajuda" avisa os vizinhos do seu bairro e prepara uma mensagem de WhatsApp com a sua localização para os seus contatos.',
          style: TextStyle(fontSize: 13, color: kTintaSuave),
        ),
        const Rotulo('Telefones de emergência'),
        Row(children: [
          for (final t in const [('193', 'Bombeiros'), ('199', 'Defesa Civil'), ('190', 'Polícia')])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64), padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => ligar(t.$1),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(t.$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(t.$2, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(child: Rotulo('Meus contatos de confiança')),
          TextButton.icon(onPressed: _novoContato, icon: const Icon(Icons.person_add_alt), label: const Text('Adicionar')),
        ]),
        if (_carregando)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()))
        else if (_contatos.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Você ainda não tem contatos. Adicione alguém para avisar rapidamente em uma emergência.'),
            ),
          )
        else
          for (final c in _contatos)
            Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: kAreia, foregroundColor: kTinta, child: Icon(Icons.person_outline)),
                title: Text(c.nome),
                subtitle: Text('${c.telefone}${c.parentesco != null ? ' · ${c.parentesco}' : ''}'),
                trailing: IconButton(
                  tooltip: 'Remover ${c.nome}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remover(c),
                ),
              ),
            ),
      ],
    );
  }
}

/// Lista de contatos com botão para abrir o WhatsApp com a mensagem pronta.
class _AvisarContatos extends StatelessWidget {
  final ResultadoEmergencia resultado;
  final String mensagem;
  final bool pedirAjuda;
  final bool comLocalizacao;
  const _AvisarContatos({required this.resultado, required this.mensagem, required this.pedirAjuda, required this.comLocalizacao});

  @override
  Widget build(BuildContext context) {
    final bairro = resultado.bairro;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.check_circle, color: kMusgo, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: Text(pedirAjuda ? 'Pedido registrado' : 'Aviso registrado', style: Theme.of(context).textTheme.titleLarge),
              ),
            ]),
            const SizedBox(height: 6),
            Text(pedirAjuda
                ? '${bairro != null ? 'Os moradores de $bairro que usam o Dilu foram avisados.' : 'Não identificamos o seu bairro para avisar os vizinhos.'} '
                    'Ligue também para a Defesa Civil (199) ou os Bombeiros (193).'
                : 'Seus pedidos de ajuda foram encerrados.'),
            if (pedirAjuda && !comLocalizacao)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kAreia, borderRadius: BorderRadius.circular(10)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.location_off_outlined, color: kBrasa),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Não conseguimos a sua localização, então o pedido foi sem o ponto no mapa. '
                      'Ao ligar ou escrever, diga onde você está (rua, número e um ponto de referência).',
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            if (resultado.contatos.isEmpty)
              const Text('Você não tem contatos cadastrados. Adicione na tela de Emergência para avisar por WhatsApp.')
            else ...[
              const Text('Avisar por WhatsApp:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final c in resultado.contatos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
                    onPressed: () async {
                      final ok = await abrirWhatsApp(c.telefone, mensagem);
                      if (!ok && context.mounted) aviso(context, 'Não foi possível abrir o WhatsApp.', erro: true);
                    },
                    icon: const Icon(Icons.chat),
                    label: Text('Avisar ${c.nome}'),
                  ),
                ),
            ],
            if (pedirAjuda) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () => ligar('199'), icon: const Icon(Icons.call), label: const Text('Ligar para a Defesa Civil (199)')),
            ],
          ],
        ),
      ),
    );
  }
}
