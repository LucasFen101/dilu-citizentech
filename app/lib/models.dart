/// Modelos de dados do app (espelham as respostas da API).
library;

import 'package:latlong2/latlong.dart';

double _num(dynamic v) => (v as num).toDouble();

DateTime? _data(dynamic v) => v == null ? null : DateTime.tryParse(v as String);

/// Relato de alagamento feito por um morador.
class Alagamento {
  final int id;
  final double latitude;
  final double longitude;
  final String? descricao;
  final int gravidade; // 1 (leve) a 4 (muito grave)
  final String? fotoUrl;
  final DateTime? criadoEm;
  final DateTime? expiraEm;
  final String? bairro;
  final String autor;
  final int confirmacoes;
  final bool confirmadoPorMim;
  final bool meu;
  final double? distanciaKm;

  Alagamento({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.gravidade,
    required this.autor,
    required this.confirmacoes,
    required this.confirmadoPorMim,
    required this.meu,
    this.descricao,
    this.fotoUrl,
    this.criadoEm,
    this.expiraEm,
    this.bairro,
    this.distanciaKm,
  });

  factory Alagamento.fromJson(Map<String, dynamic> j) => Alagamento(
        id: j['id_alagamento'] as int,
        latitude: _num(j['latitude']),
        longitude: _num(j['longitude']),
        descricao: j['descricao'] as String?,
        gravidade: (j['gravidade'] as num).toInt(),
        fotoUrl: j['foto_url'] as String?,
        criadoEm: _data(j['criado_em']),
        expiraEm: _data(j['expira_em']),
        bairro: j['bairro'] as String?,
        autor: (j['autor'] as String?) ?? 'Morador',
        confirmacoes: (j['confirmacoes'] as num).toInt(),
        confirmadoPorMim: j['confirmado_por_mim'] as bool,
        meu: j['meu'] as bool,
        distanciaKm: j['distancia_km'] == null ? null : _num(j['distancia_km']),
      );
}

/// Abrigo para onde a pessoa pode ir.
class Abrigo {
  final int id;
  final String nome;
  final String? endereco;
  final double latitude;
  final double longitude;
  final int? capacidade;
  final String? telefone;
  final String bairro;
  final double? distanciaKm;

  Abrigo({
    required this.id,
    required this.nome,
    required this.latitude,
    required this.longitude,
    required this.bairro,
    this.endereco,
    this.capacidade,
    this.telefone,
    this.distanciaKm,
  });

  factory Abrigo.fromJson(Map<String, dynamic> j) => Abrigo(
        id: j['id_abrigo'] as int,
        nome: j['nome'] as String,
        endereco: j['endereco'] as String?,
        latitude: _num(j['latitude']),
        longitude: _num(j['longitude']),
        capacidade: (j['capacidade'] as num?)?.toInt(),
        telefone: j['telefone'] as String?,
        bairro: j['bairro'] as String,
        distanciaKm: j['distancia_km'] == null ? null : _num(j['distancia_km']),
      );
}

/// Indicadores de risco de um bairro (vem da view do Oracle).
class Bairro {
  final int id;
  final String nome;
  final double score;
  final String nivel; // BAIXO, MODERADO, ALTO, CRITICO
  final int alagamentosAtivos;
  final int relatos24h;
  final int pedidosAbertos;
  final int abrigos;

  Bairro({
    required this.id,
    required this.nome,
    required this.score,
    required this.nivel,
    required this.alagamentosAtivos,
    required this.relatos24h,
    required this.pedidosAbertos,
    required this.abrigos,
  });

  factory Bairro.fromJson(Map<String, dynamic> j) => Bairro(
        id: j['id_bairro'] as int,
        nome: j['nome'] as String,
        score: _num(j['score_risco']),
        nivel: j['nivel_risco'] as String,
        alagamentosAtivos: (j['alagamentos_ativos'] as num).toInt(),
        relatos24h: (j['relatos_24h'] as num).toInt(),
        pedidosAbertos: (j['pedidos_abertos'] as num).toInt(),
        abrigos: (j['abrigos'] as num).toInt(),
      );
}

/// Mudança de nível de risco registrada no histórico do bairro.
class RegistroRisco {
  final double score;
  final String nivel;
  final DateTime? quando;

  RegistroRisco({required this.score, required this.nivel, this.quando});

  factory RegistroRisco.fromJson(Map<String, dynamic> j) => RegistroRisco(
        score: _num(j['score_risco']),
        nivel: j['nivel_risco'] as String,
        quando: _data(j['registrado_em']),
      );
}

/// Contato de emergência do usuário.
class Contato {
  final int id;
  final String nome;
  final String telefone;
  final String? parentesco;

  Contato({required this.id, required this.nome, required this.telefone, this.parentesco});

  factory Contato.fromJson(Map<String, dynamic> j) => Contato(
        id: (j['id_contato'] as num?)?.toInt() ?? 0,
        nome: j['nome'] as String,
        telefone: j['telefone'] as String,
        parentesco: j['parentesco'] as String?,
      );
}

/// Aviso gerado pelo banco (risco subiu, vizinho pediu ajuda...).
class Notificacao {
  final int id;
  final String tipo; // RISCO, AJUDA, SISTEMA
  final String titulo;
  final String? mensagem;
  final bool lida;
  final DateTime? criadoEm;

  Notificacao({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.lida,
    this.mensagem,
    this.criadoEm,
  });

  factory Notificacao.fromJson(Map<String, dynamic> j) => Notificacao(
        id: j['id_notificacao'] as int,
        tipo: j['tipo'] as String,
        titulo: j['titulo'] as String,
        mensagem: j['mensagem'] as String?,
        lida: j['lida'] == 'S',
        criadoEm: _data(j['criado_em']),
      );
}

/// Resultado de um pedido de ajuda / aviso de segurança.
class ResultadoEmergencia {
  final int idPedido;
  final String nomeUsuario;
  final List<Contato> contatos;

  ResultadoEmergencia({required this.idPedido, required this.nomeUsuario, required this.contatos});
}

/// Previsão de chuva (Open-Meteo) para as próximas horas.
class Chuva {
  final double mmProximas12h;
  final double maxMmPorHora;
  final int probabilidadeMax;

  Chuva({required this.mmProximas12h, required this.maxMmPorHora, required this.probabilidadeMax});

  /// Classificação simples para o usuário.
  String get nivel {
    if (mmProximas12h >= 20 || maxMmPorHora >= 10) return 'ALTO';
    if (mmProximas12h >= 8 || maxMmPorHora >= 4) return 'MODERADO';
    return 'BAIXO';
  }
}

/// Previsão de calor: sensação térmica e índice UV das próximas horas.
class Calor {
  final double sensacaoMax; // °C
  final double temperaturaMax; // °C
  final double uvMax;

  Calor({required this.sensacaoMax, required this.temperaturaMax, required this.uvMax});

  /// Níveis pela sensação térmica (referência: faixas de alerta de calor).
  String get nivel {
    if (sensacaoMax >= 41) return 'CRITICO';
    if (sensacaoMax >= 35) return 'ALTO';
    if (sensacaoMax >= 30) return 'MODERADO';
    return 'BAIXO';
  }
}

/// Qualidade do ar (Open-Meteo Air Quality, índice americano US AQI).
class QualidadeAr {
  final int aqi; // 0 a 500
  final double? pm25; // partículas finas, µg/m³ (fumaça de queimadas, trânsito)
  final double? pm10;

  QualidadeAr({required this.aqi, this.pm25, this.pm10});

  /// Faixas oficiais do US AQI agrupadas nos quatro níveis do Dilu.
  String get nivel => nivelAr(aqi);
}

String nivelAr(int aqi) {
  if (aqi > 200) return 'CRITICO';
  if (aqi > 150) return 'ALTO';
  if (aqi > 100) return 'MODERADO';
  return 'BAIXO';
}

/// Chuva + calor + ar juntos (previsão e qualidade do ar pedidas em paralelo).
class Clima {
  final Chuva chuva;
  final Calor calor;
  final QualidadeAr? ar;
  Clima({required this.chuva, required this.calor, this.ar});
}

/// Previsão de um dia (para o gráfico de 7 dias da cidade).
class PrevisaoDia {
  final DateTime data;
  final int codigo;
  final double maxima;
  final double minima;
  final double chuvaMm;
  final int probChuva; // %
  final double uvMax;

  PrevisaoDia({
    required this.data,
    required this.codigo,
    required this.maxima,
    required this.minima,
    required this.chuvaMm,
    required this.probChuva,
    required this.uvMax,
  });
}

/// Lê o bloco "daily" da API de previsão.
List<PrevisaoDia> previsaoDiaria(Map<String, dynamic> daily) {
  final dias = (daily['time'] as List).cast<String>();
  double v(String k, int i) => ((daily[k] as List)[i] as num?)?.toDouble() ?? 0;
  return [
    for (var i = 0; i < dias.length; i++)
      PrevisaoDia(
        data: DateTime.parse(dias[i]),
        codigo: v('weather_code', i).toInt(),
        maxima: v('temperature_2m_max', i),
        minima: v('temperature_2m_min', i),
        chuvaMm: v('precipitation_sum', i),
        probChuva: v('precipitation_probability_max', i).round(),
        uvMax: v('uv_index_max', i),
      ),
  ];
}

/// Um alerta de clima para mostrar ao usuário.
class AlertaClima {
  final String titulo;
  final String mensagem;
  final String nivel;
  AlertaClima(this.titulo, this.mensagem, this.nivel);
}

/// Transforma a previsão em alertas (só quando o nível é moderado ou maior).
List<AlertaClima> alertasDoClima(Clima c) {
  final lista = <AlertaClima>[];
  if (c.chuva.nivel != 'BAIXO') {
    lista.add(AlertaClima(
      c.chuva.nivel == 'ALTO' ? 'Chuva forte prevista' : 'Chuva moderada prevista',
      'Até ${c.chuva.mmProximas12h.toStringAsFixed(0)} mm nas próximas 12h. Evite áreas de alagamento e acompanhe o mapa.',
      c.chuva.nivel,
    ));
  }
  if (c.calor.nivel != 'BAIXO') {
    lista.add(AlertaClima(
      c.calor.nivel == 'MODERADO' ? 'Calor acima do normal' : 'Calor extremo previsto',
      'Sensação de até ${c.calor.sensacaoMax.toStringAsFixed(0)} °C e UV ${c.calor.uvMax.toStringAsFixed(0)}. '
          'Beba água, evite o sol entre 10h e 16h e redobre o cuidado com idosos e crianças.',
      c.calor.nivel,
    ));
  } else if (c.calor.uvMax >= 8) {
    // mesmo sem calor forte, o sol pode queimar (UV 8+ é "muito alto")
    lista.add(AlertaClima(
      'Índice UV muito alto',
      'UV de até ${c.calor.uvMax.toStringAsFixed(0)} nas próximas horas. Use protetor solar, chapéu e evite o sol entre 10h e 16h.',
      c.calor.uvMax >= 11 ? 'ALTO' : 'MODERADO',
    ));
  }
  final ar = c.ar;
  if (ar != null && ar.nivel != 'BAIXO') {
    lista.add(AlertaClima(
      ar.nivel == 'MODERADO' ? 'Ar ruim para grupos sensíveis' : 'Qualidade do ar ruim',
      'Índice ${ar.aqi}${ar.pm25 != null ? ' (partículas finas: ${ar.pm25!.round()} µg/m³)' : ''}. '
          'Evite exercícios ao ar livre; crianças, idosos e quem tem asma devem ficar em casa com as janelas fechadas.',
      ar.nivel,
    ));
  }
  return lista;
}

/// Números gerais do Dilu (view VW_DILU_NUMEROS do Oracle).
class NumerosDilu {
  final int moradores;
  final int relatosTotal;
  final int relatosAtivos;
  final int relatosResolvidos;
  final int confirmacoes;
  final int pedidosAjuda;
  final int pedidosAtendidos;
  final int avisosRisco;

  NumerosDilu({
    required this.moradores,
    required this.relatosTotal,
    required this.relatosAtivos,
    required this.relatosResolvidos,
    required this.confirmacoes,
    required this.pedidosAjuda,
    required this.pedidosAtendidos,
    required this.avisosRisco,
  });

  factory NumerosDilu.fromJson(Map<String, dynamic> j) => NumerosDilu(
        moradores: (j['moradores'] as num).toInt(),
        relatosTotal: (j['relatos_total'] as num).toInt(),
        relatosAtivos: (j['relatos_ativos'] as num).toInt(),
        relatosResolvidos: (j['relatos_resolvidos'] as num).toInt(),
        confirmacoes: (j['confirmacoes'] as num).toInt(),
        pedidosAjuda: (j['pedidos_ajuda'] as num).toInt(),
        pedidosAtendidos: (j['pedidos_atendidos'] as num).toInt(),
        avisosRisco: (j['avisos_risco'] as num).toInt(),
      );
}

/// Códigos WMO de tempo (Open-Meteo) que significam chuva ou tempestade.
bool codigoChuva(int c) => (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95;

/// Descrição em português do código de tempo.
String descricaoTempo(int c) {
  if (c == 0) return 'Céu limpo';
  if (c == 1) return 'Predomínio de sol';
  if (c == 2) return 'Parcialmente nublado';
  if (c == 3) return 'Nublado';
  if (c == 45 || c == 48) return 'Neblina';
  if (c >= 51 && c <= 57) return 'Garoa';
  if (c >= 61 && c <= 67) return 'Chuva';
  if (c >= 80 && c <= 82) return 'Pancadas de chuva';
  if (c >= 95) return 'Tempestade';
  return 'Tempo instável';
}

/// Uma cidade do mapa de clima, com a previsão daquele ponto.
class CelulaClima {
  final LatLng centro;
  final List<LatLng> vertices; // vazio quando a célula é uma cidade (ponto)
  final String? nome; // só para cidades
  final String? uf;
  final String? regiao; // Norte, Nordeste, Centro-Oeste, Sudeste ou Sul
  double? temperatura; // °C
  double? sensacao; // °C
  double? umidade; // %
  double? chuvaMm; // mm na última hora
  double? chuva6hMm; // mm previstos nas próximas 6h
  double? ventoKmh;
  int? codigo; // código WMO
  double? uv; // índice UV agora
  int? aqi; // qualidade do ar (US AQI)
  double? pm25; // partículas finas, µg/m³

  CelulaClima({required this.centro, this.vertices = const [], this.nome, this.uf, this.regiao});

  bool get temDados => temperatura != null;

  /// Está chovendo agora (volume medido ou código de chuva).
  bool get chovendo => (chuvaMm ?? 0) >= 0.1 || (codigo != null && codigoChuva(codigo!));
}

/// Números pessoais do usuário (view VW_RESUMO_USUARIO do Oracle).
class ResumoUsuario {
  final int relatosTotal;
  final int relatosAtivos;
  final int relatosResolvidos;
  final int confirmacoesRecebidas;
  final int confirmacoesDadas;
  final int pedidosAjuda;

  ResumoUsuario({
    required this.relatosTotal,
    required this.relatosAtivos,
    required this.relatosResolvidos,
    required this.confirmacoesRecebidas,
    required this.confirmacoesDadas,
    required this.pedidosAjuda,
  });

  factory ResumoUsuario.fromJson(Map<String, dynamic> j) => ResumoUsuario(
        relatosTotal: (j['relatos_total'] as num).toInt(),
        relatosAtivos: (j['relatos_ativos'] as num).toInt(),
        relatosResolvidos: (j['relatos_resolvidos'] as num).toInt(),
        confirmacoesRecebidas: (j['confirmacoes_recebidas'] as num).toInt(),
        confirmacoesDadas: (j['confirmacoes_dadas'] as num).toInt(),
        pedidosAjuda: (j['pedidos_ajuda'] as num).toInt(),
      );
}

/// Um alagamento que o próprio usuário relatou.
class MeuRelato {
  final int id;
  final int gravidade;
  final String? descricao;
  final String status; // ATIVO, RESOLVIDO ou EXPIRADO
  final DateTime? criadoEm;
  final String? bairro;
  final int confirmacoes;

  MeuRelato({
    required this.id,
    required this.gravidade,
    required this.status,
    required this.confirmacoes,
    this.descricao,
    this.criadoEm,
    this.bairro,
  });

  factory MeuRelato.fromJson(Map<String, dynamic> j) => MeuRelato(
        id: j['id_alagamento'] as int,
        gravidade: (j['gravidade'] as num).toInt(),
        descricao: j['descricao'] as String?,
        status: j['status'] as String,
        criadoEm: _data(j['criado_em']),
        bairro: j['bairro'] as String?,
        confirmacoes: (j['confirmacoes'] as num).toInt(),
      );
}