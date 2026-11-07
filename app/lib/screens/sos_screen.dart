import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../services.dart';
import '../theme.dart';

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
            ? 'Vamos registrar sua localização, avisar moradores do seu bairro e preparar uma mensagem para seus contatos.'
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
      final pos = await posicaoAtual() ?? kLocalPadrao;
      final r = await Api.emergencia(tipo, pos.latitude, pos.longitude, null);
      if (!mounted) return;
      final msg = pedirAjuda
          ? 'ALERTA DILU: ${r.nomeUsuario} precisa de ajuda por causa de alagamento. Localização: ${linkMapa(pos.latitude, pos.longitude)}'
          : 'DILU: ${r.nomeUsuario} está seguro. Pode ficar tranquilo(a).';
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AvisarContatos(resultado: r, mensagem: msg, pedirAjuda: pedirAjuda),
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
        const SizedBox(height: 24),
        Text('Telefones de emergência', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
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
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Text('Meus contatos de confiança', style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(onPressed: _novoContato, icon: const Icon(Icons.person_add), label: const Text('Adicionar')),
        ]),
        if (_carregando)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
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
  const _AvisarContatos({required this.resultado, required this.mensagem, required this.pedirAjuda});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.check_circle, color: kMusgo, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: Text(pedirAjuda ? 'Pedido registrado!' : 'Aviso registrado!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(pedirAjuda
                ? 'Moradores do seu bairro foram avisados. Ligue também para a Defesa Civil (199) ou Bombeiros (193).'
                : 'Seus pedidos de ajuda foram encerrados.'),
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
