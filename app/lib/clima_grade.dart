/// Leitura da previsão do tempo (Open-Meteo aceita várias coordenadas numa só chamada).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Preenche as células com a resposta da API (lista, se houve várias coordenadas).
void aplicarPrevisao(List<CelulaClima> celulas, dynamic json) {
  final lista = json is List ? json : [json];
  for (var i = 0; i < celulas.length && i < lista.length; i++) {
    final r = lista[i] as Map<String, dynamic>;
    final cur = r['current'] as Map<String, dynamic>?;
    if (cur == null) continue;
    final c = celulas[i];
    double? n(String k) => (cur[k] as num?)?.toDouble();
    c.temperatura = n('temperature_2m');
    c.sensacao = n('apparent_temperature');
    c.umidade = n('relative_humidity_2m');
    c.chuvaMm = n('precipitation');
    c.ventoKmh = n('wind_speed_10m');
    c.codigo = (cur['weather_code'] as num?)?.toInt();

    // soma da chuva prevista nas 6 horas seguintes (horários no mesmo formato, comparáveis como texto)
    final h = r['hourly'] as Map<String, dynamic>?;
    if (h != null) {
      final tempos = (h['time'] as List).cast<String>();
      final mm = h['precipitation'] as List;
      final agora = cur['time'] as String;
      var inicio = tempos.indexWhere((t) => t.compareTo(agora) > 0);
      if (inicio < 0) inicio = tempos.length;
      var soma = 0.0;
      for (var k = inicio; k < inicio + 6 && k < mm.length; k++) {
        soma += (mm[k] as num?)?.toDouble() ?? 0;
      }
      c.chuva6hMm = soma;
    }
  }
}

/// Busca o clima atual das células. Divide em lotes de 40 pontos (chamadas em paralelo).
/// True se pelo menos um lote deu certo.
Future<bool> buscarGrade(List<CelulaClima> celulas) async {
  if (celulas.isEmpty) return false;
  const lote = 40;

  Future<bool> buscarLote(List<CelulaClima> parte) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': parte.map((c) => c.centro.latitude.toStringAsFixed(3)).join(','),
        'longitude': parte.map((c) => c.centro.longitude.toStringAsFixed(3)).join(','),
        'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
        'hourly': 'precipitation',
        'forecast_days': '1',
        'timezone': 'auto',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return false;
      aplicarPrevisao(parte, jsonDecode(r.body));
      return parte.any((c) => c.temDados);
    } catch (_) {
      return false;
    }
  }

  final lotes = <Future<bool>>[
    for (var i = 0; i < celulas.length; i += lote)
      buscarLote(celulas.sublist(i, (i + lote).clamp(0, celulas.length))),
  ];
  final resultados = await Future.wait(lotes);
  return resultados.any((ok) => ok);
}
