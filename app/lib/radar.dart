/// Radar de chuva ao vivo (RainViewer, gratuito para uso educacional).
///
/// A API devolve a lista de "quadros" das últimas 2 horas (um a cada 10 min).
/// Cada quadro é um conjunto de imagens (tiles) que se encaixa sobre o mapa.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Um instante do radar.
class QuadroRadar {
  final DateTime hora;
  final String urlTiles; // modelo com {z}/{x}/{y} para o flutter_map
  QuadroRadar(this.hora, this.urlTiles);
}

/// Monta os quadros a partir da resposta da API.
/// Guarda só os [maximo] mais recentes para não pesar na memória.
List<QuadroRadar> lerQuadrosRadar(Map<String, dynamic> json, {int maximo = 7}) {
  final host = json['host'] as String;
  final passados = ((json['radar'] as Map<String, dynamic>)['past'] as List).cast<Map<String, dynamic>>();
  final ultimos = passados.length > maximo ? passados.sublist(passados.length - maximo) : passados;
  return [
    for (final q in ultimos)
      QuadroRadar(
        DateTime.fromMillisecondsSinceEpoch((q['time'] as int) * 1000),
        // 256 px, esquema de cor 2 (azul universal), suavizado e com neve
        '$host${q['path']}/256/{z}/{x}/{y}/2/1_1.png',
      ),
  ];
}

/// Busca os quadros do radar. Lista vazia se a API não responder.
Future<List<QuadroRadar>> buscarRadar() async {
  try {
    final r = await http.get(Uri.https('api.rainviewer.com', '/public/weather-maps.json')).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    return lerQuadrosRadar(jsonDecode(r.body) as Map<String, dynamic>);
  } catch (_) {
    return [];
  }
}
