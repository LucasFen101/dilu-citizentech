/// Cliente HTTP da API do AlertaEnchente.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';

/// Erro amigável para mostrar ao usuário.
class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);

  @override
  String toString() => message;
}

class Api {
  /// Endereço do servidor. No emulador Android, 10.0.2.2 aponta para o PC.
  static String baseUrl = kIsWeb
      ? 'http://localhost:8000'
      : (defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8000' : 'http://localhost:8000');

  /// Token JWT da sessão atual.
  static String? token;

  static Map<String, String> get _auth => {if (token != null) 'Authorization': 'Bearer $token'};
  static Map<String, String> get _json => {'Content-Type': 'application/json', ..._auth};

  /// Monta a URL completa de um arquivo enviado (ex.: foto do alagamento).
  static String arquivo(String caminho) => '$baseUrl$caminho';

  /// Executa a requisição tratando falta de rede, tempo esgotado e erros da API.
  static Future<dynamic> _enviar(Future<http.Response> Function() req, {Duration limite = const Duration(seconds: 20)}) async {
    http.Response r;
    try {
      r = await req().timeout(limite);
    } on TimeoutException {
      throw ApiException('O servidor demorou para responder. Tente novamente.');
    } catch (_) {
      throw ApiException('Não foi possível conectar ao servidor. Verifique sua internet.');
    }
    final corpo = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      var msg = 'Algo deu errado. Tente novamente.';
      if (corpo is Map && corpo['detail'] is String) {
        msg = corpo['detail'] as String;
      } else if (r.statusCode == 422) {
        msg = 'Confira os dados informados.';
      } else if (r.statusCode == 401) {
        msg = 'Sessão expirada. Entre novamente.';
      }
      throw ApiException(msg, r.statusCode);
    }
    return corpo;
  }

  static Uri _u(String caminho, [Map<String, String>? q]) => Uri.parse('$baseUrl$caminho').replace(queryParameters: q);

  // ------------------------------------------------------------- conta
  static Future<String> cadastrar({
    required String nome,
    required String email,
    required String senha,
    String? telefone,
    double? latitude,
    double? longitude,
  }) async {
    final r = await _enviar(() => http.post(_u('/auth/register'),
        headers: _json,
        body: jsonEncode({
          'nome': nome,
          'email': email,
          'senha': senha,
          'telefone': telefone,
          'latitude': latitude,
          'longitude': longitude,
        })));
    return r['token'] as String;
  }

  static Future<String> entrar(String email, String senha) async {
    final r = await _enviar(
        () => http.post(_u('/auth/login'), headers: _json, body: jsonEncode({'email': email, 'senha': senha})));
    return r['token'] as String;
  }

  static Future<Map<String, dynamic>> eu() async =>
      Map<String, dynamic>.from(await _enviar(() => http.get(_u('/me'), headers: _json)));

  static Future<ResumoUsuario> resumo() async =>
      ResumoUsuario.fromJson(Map<String, dynamic>.from(await _enviar(() => http.get(_u('/me/resumo'), headers: _json))));

  static Future<List<MeuRelato>> meusRelatos() async {
    final r = await _enviar(() => http.get(_u('/me/relatos'), headers: _json)) as List;
    return r.map((e) => MeuRelato.fromJson(e)).toList();
  }
  // ------------------------------------------------------ meus lugares
  static Future<List<Lugar>> lugares() async {
    final r = await _enviar(() => http.get(_u('/lugares'), headers: _json)) as List;
    return r.map((e) => Lugar.fromJson(e)).toList();
  }

  static Future<void> salvarLugar(String apelido, String tipo, double lat, double lon) => _enviar(() => http.post(_u('/lugares'),
      headers: _json, body: jsonEncode({'apelido': apelido, 'tipo': tipo, 'latitude': lat, 'longitude': lon})));

  static Future<void> removerLugar(int id) => _enviar(() => http.delete(_u('/lugares/$id'), headers: _json));

  // ---------------------------------------------------------- contatos
  static Future<List<Contato>> contatos() async {
    final r = await _enviar(() => http.get(_u('/contatos'), headers: _json)) as List;
    return r.map((e) => Contato.fromJson(e)).toList();
  }

  static Future<void> criarContato(String nome, String telefone, String? parentesco) => _enviar(() => http.post(
      _u('/contatos'),
      headers: _json,
      body: jsonEncode({'nome': nome, 'telefone': telefone, 'parentesco': parentesco})));

  static Future<void> removerContato(int id) => _enviar(() => http.delete(_u('/contatos/$id'), headers: _json));

  // ------------------------------------------------------- alagamentos
  static Future<List<Alagamento>> alagamentos(double lat, double lon, {double raioKm = 30}) async {
    final r = await _enviar(() => http.get(
        _u('/alagamentos', {'latitude': '$lat', 'longitude': '$lon', 'raio_km': '$raioKm'}),
        headers: _json)) as List;
    return r.map((e) => Alagamento.fromJson(e)).toList();
  }

  static Future<void> registrarAlagamento({
    required double latitude,
    required double longitude,
    required int gravidade,
    String? descricao,
    XFile? foto,
  }) async {
    final req = http.MultipartRequest('POST', _u('/alagamentos'))
      ..headers.addAll(_auth)
      ..fields['latitude'] = '$latitude'
      ..fields['longitude'] = '$longitude'
      ..fields['gravidade'] = '$gravidade';
    if (descricao != null && descricao.trim().isNotEmpty) req.fields['descricao'] = descricao.trim();
    if (foto != null) {
      final nome = foto.name.toLowerCase();
      final tipo = nome.endsWith('.png')
          ? MediaType('image', 'png')
          : nome.endsWith('.webp')
              ? MediaType('image', 'webp')
              : MediaType('image', 'jpeg');
      req.files.add(http.MultipartFile.fromBytes('foto', await foto.readAsBytes(),
          filename: foto.name, contentType: tipo));
    }
    await _enviar(() async => http.Response.fromStream(await req.send()));
  }

  static Future<void> confirmar(int id) => _enviar(() => http.post(_u('/alagamentos/$id/confirmar'), headers: _json));

  static Future<void> resolver(int id) => _enviar(() => http.post(_u('/alagamentos/$id/resolver'), headers: _json));

  // -------------------------------------------------------- emergência
  /// [lat]/[lon] nulos = sem GPS: o pedido vai sem ponto no mapa (nunca com um ponto inventado).
  static Future<ResultadoEmergencia> emergencia(String tipo, double? lat, double? lon, String? mensagem) async {
    final r = await _enviar(() => http.post(_u('/emergencia'),
        headers: _json,
        body: jsonEncode({'tipo': tipo, 'latitude': lat, 'longitude': lon, 'mensagem': mensagem})));
    return ResultadoEmergencia(
      idPedido: r['id_pedido'] as int,
      nomeUsuario: r['nome_usuario'] as String,
      contatos: (r['contatos'] as List).map((e) => Contato.fromJson(e)).toList(),
      bairro: r['bairro'] as String?,
    );
  }

  // ---------------------------------------------------- locais seguros
  static Future<List<LocalSeguro>> locaisSeguros(double lat, double lon) async {
    final r = await _enviar(() => http.get(_u('/locais-seguros', {'latitude': '$lat', 'longitude': '$lon'}), headers: _json)) as List;
    return r.map((e) => LocalSeguro.fromJson(e)).toList();
  }

  static Future<void> cadastrarLocal({
    required String nome,
    required String tipo,
    String? descricao,
    required double latitude,
    required double longitude,
  }) =>
      _enviar(() => http.post(_u('/locais-seguros'),
          headers: _json,
          body: jsonEncode({
            'nome': nome,
            'tipo': tipo,
            'descricao': (descricao?.trim().isEmpty ?? true) ? null : descricao!.trim(),
            'latitude': latitude,
            'longitude': longitude,
          })));

  static Future<void> avaliarLocal(int id, bool seguro) =>
      _enviar(() => http.post(_u('/locais-seguros/$id/avaliar'), headers: _json, body: jsonEncode({'seguro': seguro})));

  static Future<void> removerLocal(int id) => _enviar(() => http.delete(_u('/locais-seguros/$id'), headers: _json));

  static Future<List<Bairro>> indicadores() async {
    final r = await _enviar(() => http.get(_u('/bairros/indicadores'), headers: _json)) as List;
    return r.map((e) => Bairro.fromJson(e)).toList();
  }

  static Future<List<RegistroRisco>> historico(int idBairro) async {
    final r = await _enviar(() => http.get(_u('/bairros/$idBairro/historico'), headers: _json)) as List;
    return r.map((e) => RegistroRisco.fromJson(e)).toList();
  }

  static Future<NumerosDilu> numeros() async =>
      NumerosDilu.fromJson(Map<String, dynamic>.from(await _enviar(() => http.get(_u('/dilu/numeros'), headers: _json))));

  static Future<List<Notificacao>> notificacoes() async {
    final r = await _enviar(() => http.get(_u('/notificacoes'), headers: _json)) as List;
    return r.map((e) => Notificacao.fromJson(e)).toList();
  }

  static Future<void> marcarLidas() => _enviar(() => http.post(_u('/notificacoes/lidas'), headers: _json));
}
