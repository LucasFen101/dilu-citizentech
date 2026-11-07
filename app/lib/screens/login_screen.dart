import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets.dart';

/// Entrar ou criar conta.
class LoginScreen extends StatefulWidget {
  final VoidCallback aoEntrar;
  const LoginScreen({super.key, required this.aoEntrar});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _telefone = TextEditingController();
  final _senha = TextEditingController();
  bool _criarConta = false;
  bool _carregando = false;
  bool _verSenha = false;

  @override
  void dispose() {
    for (final c in [_nome, _email, _telefone, _senha]) {
      c.dispose(); // libera os controladores (boa prática de memória)
    }
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      String token;
      if (_criarConta) {
        // a localização é opcional: serve para descobrir o bairro do morador
        final pos = await posicaoAtual();
        token = await Api.cadastrar(
          nome: _nome.text.trim(),
          email: _email.text.trim(),
          senha: _senha.text,
          telefone: _telefone.text.trim().isEmpty ? null : _telefone.text.trim(),
          latitude: pos?.latitude,
          longitude: pos?.longitude,
        );
      } else {
        token = await Api.entrar(_email.text.trim(), _senha.text);
      }
      await Sessao.salvarToken(token);
      widget.aoEntrar();
    } on ApiException catch (e) {
      if (mounted) aviso(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Permite apontar o app para outro servidor (ex.: celular na mesma rede Wi-Fi).
  Future<void> _configurarServidor() async {
    final c = TextEditingController(text: Api.baseUrl);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Endereço do servidor'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'http://192.168.0.10:8000'),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    c.dispose();
    if (novo != null && novo.isNotEmpty) {
      await Sessao.salvarServidor(novo.replaceAll(RegExp(r'/+$'), ''));
      if (mounted) aviso(context, 'Servidor: ${Api.baseUrl}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPapel,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // cabeçalho escuro com ondas
            Container(
              color: kTinta,
              child: Stack(
                children: [
                  const Positioned.fill(child: Ondas()),
                  const Positioned(top: 8, right: 8, child: SafeArea(child: BotaoTextoGrande(cor: kPapel))),
                  SafeArea(
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 44, 28, 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const DiluLogo(tamanho: 76, cor: kPapel),
                              const SizedBox(height: 18),
                              Text(
                                'Avise antes que\na água chegue.',
                                style: GoogleFonts.fraunces(
                                    fontSize: 26, fontStyle: FontStyle.italic, fontWeight: FontWeight.w400, color: kPapel, height: 1.2),
                              ),
                              const SizedBox(height: 10),
                              Text('Alagamentos reportados e confirmados por quem mora perto.',
                                  style: GoogleFonts.manrope(fontSize: 14.5, color: kPapel.withValues(alpha: 0.75))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: false, label: Text('Entrar')),
                            ButtonSegment(value: true, label: Text('Criar conta')),
                          ],
                          selected: {_criarConta},
                          onSelectionChanged: (s) => setState(() => _criarConta = s.first),
                        ),
                        const SizedBox(height: 20),
                        if (_criarConta) ...[
                          TextFormField(
                            controller: _nome,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Nome'),
                            validator: (v) => (v == null || v.trim().length < 2) ? 'Informe seu nome' : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'E-mail'),
                          validator: (v) =>
                              (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'E-mail inválido' : null,
                        ),
                        const SizedBox(height: 12),
                        if (_criarConta) ...[
                          TextFormField(
                            controller: _telefone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Telefone (opcional)'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _senha,
                          obscureText: !_verSenha,
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            suffixIcon: IconButton(
                              tooltip: _verSenha ? 'Ocultar senha' : 'Mostrar senha',
                              icon: Icon(_verSenha ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _verSenha = !_verSenha),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6) ? 'Mínimo de 6 caracteres' : null,
                          onFieldSubmitted: (_) => _enviar(),
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _carregando ? null : _enviar,
                          child: _carregando
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3, color: kPapel))
                              : Text(_criarConta ? 'Criar conta' : 'Entrar'),
                        ),
                        if (_criarConta)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Vamos pedir sua localização só para saber em qual bairro você mora e te avisar sobre riscos.',
                              style: TextStyle(fontSize: 13, color: kTintaSuave),
                            ),
                          ),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _configurarServidor, child: const Text('Configurar servidor')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}