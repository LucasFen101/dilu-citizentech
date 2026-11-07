/// Risco de enchente ESTIMADO por cidade, sem depender de relatos de usuários.
///
/// Base: chuva acumulada nos últimos 3 dias + chuva prevista (hoje e 2 dias),
/// da previsão do Open-Meteo. Reforço: vazão do rio no modelo global GloFAS
/// (Open-Meteo Flood API), que sobe o nível em 1 degrau quando está muito
/// acima da média. É uma estimativa, não substitui os alertas da Defesa Civil.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const niveisRisco = ['BAIXO', 'MODERADO', 'ALTO', 'CRITICO'];

/// Pontuação de chuva (mm ponderados) que separa cada nível.
const limitesPontosChuva = [25.0, 50.0, 90.0];

class RiscoCidade {
  final CelulaClima cidade;
  double? chuvaRecente3d; // mm nos 3 dias anteriores
  double? chuvaPrevista3d; // mm previstos de hoje até daqui a 2 dias
  double? vazaoAtual; // m³/s (modelo global)
  double? razaoVazao; // maior vazão da semana ÷ vazão média esperada
  double pontos = 0;
  int indice = 0;
  bool reforcoRio = false;
  bool temDados = false;

  RiscoCidade(this.cidade);

  String get nivel => niveisRisco[indice];
}

/// Razão entre a maior vazão prevista e a média esperada (null se não houver dado útil).
double? razaoVazao(List<num?> vazao, List<num?> media) {
  final v = vazao.whereType<num>().toList();
  final m = media.whereType<num>().toList();
  if (v.isEmpty || m.isEmpty) return null;
  final mediaGeral = m.reduce((a, b) => a + b) / m.length;
  if (mediaGeral <= 0) return null;
  return v.reduce((a, b) => a > b ? a : b) / mediaGeral;
}

/// Calcula pontos e nível de risco a partir da chuva e da vazão já preenchidas.
void calcularRisco(RiscoCidade r) {
  final recente = r.chuvaRecente3d;
  final prevista = r.chuvaPrevista3d;
  if (recente == null || prevista == null) return;
  r.temDados = true;
  // a chuva que ainda vai cair pesa mais do que a que já caiu
  r.pontos = recente * 0.4 + prevista * 0.6;
  var i = 0;
  for (final limite in limitesPontosChuva) {
    if (r.pontos >= limite) i++;
  }
  // rio: só conta se a vazão for relevante (≥ 20 m³/s) e estiver ≥ 2x acima da média
  r.reforcoRio = (r.razaoVazao ?? 0) >= 2.0 && (r.vazaoAtual ?? 0) >= 20;
  if (r.reforcoRio && i < 3) i++;
  r.indice = i;
}

/// Preenche a chuva (resposta do Open-Meteo com past_days=3 e forecast_days=3).
void aplicarChuvaDiaria(List<RiscoCidade> lista, dynamic json) {
  final respostas = json is List ? json : [json];
  for (var i = 0; i < lista.length && i < respostas.length; i++) {
    final daily = (respostas[i] as Map<String, dynamic>)['daily'] as Map<String, dynamic>?;
    final mm = (daily?['precipitation_sum'] as List?)?.map((e) => (e as num?)?.toDouble() ?? 0.0).toList();
    if (mm == null || mm.length < 6) continue;
    lista[i].chuvaRecente3d = mm[0] + mm[1] + mm[2];
    lista[i].chuvaPrevista3d = mm[3] + mm[4] + mm[5];
  }
}

/// Preenche a vazão dos rios (resposta da Flood API).
void aplicarVazao(List<RiscoCidade> lista, dynamic json) {
  final respostas = json is List ? json : [json];
  for (var i = 0; i < lista.length && i < respostas.length; i++) {
    final daily = (respostas[i] as Map<String, dynamic>)['daily'] as Map<String, dynamic>?;
    if (daily == null) continue;
    final vazao = (daily['river_discharge'] as List?)?.cast<num?>() ?? const <num?>[];
    final media = (daily['river_discharge_mean'] as List?)?.cast<num?>() ?? const <num?>[];
    lista[i].razaoVazao = razaoVazao(vazao, media);
    lista[i].vazaoAtual = vazao.isNotEmpty ? vazao.first?.toDouble() : null;
  }
}

/// Busca chuva e vazão de todas as cidades (lotes de 40, em paralelo) e calcula o risco.
/// True se conseguiu a chuva de pelo menos um lote. Se a vazão falhar, o risco sai só pela chuva.
Future<bool> buscarRisco(List<RiscoCidade> lista) async {
  if (lista.isEmpty) return false;
  const lote = 40;

  Future<dynamic> get(String host, String caminho, List<RiscoCidade> parte, Map<String, String> extra) async {
    try {
      final uri = Uri.https(host, caminho, {
        'latitude': parte.map((r) => r.cidade.centro.latitude.toStringAsFixed(3)).join(','),
        'longitude': parte.map((r) => r.cidade.centro.longitude.toStringAsFixed(3)).join(','),
        ...extra,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 25));
      return r.statusCode == 200 ? jsonDecode(r.body) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> lotePronto(List<RiscoCidade> parte) async {
    final res = await Future.wait([
      get('api.open-meteo.com', '/v1/forecast', parte,
          {'daily': 'precipitation_sum', 'past_days': '3', 'forecast_days': '3', 'timezone': 'auto'}),
      get('flood-api.open-meteo.com', '/v1/flood', parte,
          {'daily': 'river_discharge,river_discharge_mean', 'forecast_days': '7'}),
    ]);
    if (res[0] == null) return false;
    aplicarChuvaDiaria(parte, res[0]);
    if (res[1] != null) aplicarVazao(parte, res[1]);
    for (final r in parte) {
      calcularRisco(r);
    }
    return parte.any((r) => r.temDados);
  }

  final lotes = [
    for (var i = 0; i < lista.length; i += lote) lotePronto(lista.sublist(i, (i + lote).clamp(0, lista.length))),
  ];
  return (await Future.wait(lotes)).any((ok) => ok);
}
