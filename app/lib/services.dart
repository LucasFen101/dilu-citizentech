/// Serviços de apoio: sessão salva, localização, previsão de chuva e utilitários.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'models.dart';

/// Local padrão (centro de São Paulo/Mooca) quando o GPS não está disponível.
const kLocalPadrao = LatLng(-23.5590, -46.5990);

/// Guarda o token e o endereço do servidor no aparelho.
class Sessao {
  static const _kToken = 'token';
  static const _kServidor = 'servidor';

  /// Carrega token e servidor salvos. Devolve true se há sessão guardada.
  static Future<bool> restaurar() async {
    try {
      final p = await SharedPreferences.getInstance();
      Api.baseUrl = p.getString(_kServidor) ?? Api.baseUrl;
      Api.token = p.getString(_kToken);
    } catch (_) {}
    return Api.token != null;
  }

  static Future<void> salvarToken(String token) async {
    Api.token = token;
    try {
      (await SharedPreferences.getInstance()).setString(_kToken, token);
    } catch (_) {}
  }

  static Future<void> sair() async {
    Api.token = null;
    try {
      (await SharedPreferences.getInstance()).remove(_kToken);
    } catch (_) {}
    await Preferencias.apagarRetrato(); // o retrato é da conta que saiu
  }

  static Future<void> salvarServidor(String url) async {
    Api.baseUrl = url;
    try {
      (await SharedPreferences.getInstance()).setString(_kServidor, url);
    } catch (_) {}
  }
}

/// Posição atual do aparelho, ou null se não houver permissão/GPS.
Future<LatLng?> posicaoAtual() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

/// Qualidade do ar agora num ponto (Open-Meteo Air Quality, gratuita e sem chave).
Future<QualidadeAr?> buscarQualidadeAr(double lat, double lon) async {
  try {
    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'us_aqi,pm2_5,pm10',
      'timezone': 'auto',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final cur = jsonDecode(r.body)['current'] as Map<String, dynamic>;
    final aqi = cur['us_aqi'] as num?;
    if (aqi == null) return null;
    return QualidadeAr(aqi: aqi.round(), pm25: (cur['pm2_5'] as num?)?.toDouble(), pm10: (cur['pm10'] as num?)?.toDouble());
  } catch (_) {
    return null;
  }
}

/// Chuva acumulada das últimas 24h e a prevista nas próximas 6h (Open-Meteo, por hora).
/// O Open-Meteo combina modelo e observações; não é a medição de um pluviômetro.
Future<ChuvaAcumulada?> buscarChuvaAcumulada(double lat, double lon) async {
  try {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(3),
      'longitude': lon.toStringAsFixed(3),
      'hourly': 'precipitation',
      'current': 'precipitation',
      'past_days': '1',
      'forecast_days': '1',
      'timezone': 'auto',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final h = j['hourly'] as Map<String, dynamic>;
    return chuvaAcumuladaDe(
      (h['time'] as List).cast<String>(),
      (h['precipitation'] as List).map((e) => (e as num?)?.toDouble() ?? 0.0).toList(),
      (j['current'] as Map<String, dynamic>)['time'] as String,
    );
  } catch (_) {
    return null;
  }
}

/// Previsão dos próximos 7 dias (máxima, mínima, chuva, UV) para a ficha da cidade.
Future<List<PrevisaoDia>?> buscarPrevisao7Dias(double lat, double lon) async {
  try {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(3),
      'longitude': lon.toStringAsFixed(3),
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,uv_index_max',
      'forecast_days': '7',
      'timezone': 'auto',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    return previsaoDiaria(jsonDecode(r.body)['daily'] as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Previsão de chuva, calor e qualidade do ar das próximas 12 horas.
/// A previsão e o ar são pedidos em paralelo; se o ar falhar, o resto continua.
Future<Clima?> buscarClima(double lat, double lon) async {
  final ar = buscarQualidadeAr(lat, lon);
  final clima = await _buscarPrevisao12h(lat, lon);
  if (clima == null) return null;
  return Clima(chuva: clima.chuva, calor: clima.calor, ar: await ar);
}

Future<Clima?> _buscarPrevisao12h(double lat, double lon) async {
  try {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'hourly': 'precipitation,precipitation_probability,temperature_2m,apparent_temperature,uv_index',
      'forecast_days': '2',
      'timezone': 'auto',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final h = jsonDecode(r.body)['hourly'] as Map<String, dynamic>;
    final tempos = (h['time'] as List).cast<String>();
    List<double> serie(String k) => (h[k] as List).map((e) => (e as num?)?.toDouble() ?? 0.0).toList();
    final mm = serie('precipitation');
    final prob = serie('precipitation_probability');
    final temp = serie('temperature_2m');
    final sens = serie('apparent_temperature');
    final uv = serie('uv_index');

    // primeira hora que ainda não passou (os horários vêm no fuso local da previsão)
    final agora = DateTime.now();
    var inicio = tempos.indexWhere((t) => DateTime.parse(t).isAfter(agora.subtract(const Duration(hours: 1))));
    if (inicio < 0) inicio = 0;
    final fim = (inicio + 12).clamp(0, mm.length);
    if (fim <= inicio) return null;

    double maximo(List<double> l) => l.sublist(inicio, fim).reduce((a, b) => a > b ? a : b);
    return Clima(
      chuva: Chuva(
        mmProximas12h: mm.sublist(inicio, fim).fold(0.0, (a, b) => a + b),
        maxMmPorHora: maximo(mm),
        probabilidadeMax: maximo(prob).round(),
      ),
      calor: Calor(sensacaoMax: maximo(sens), temperaturaMax: maximo(temp), uvMax: maximo(uv)),
    );
  } catch (_) {
    return null;
  }
}

/// Preferências do usuário guardadas no aparelho (ex.: texto grande).
class Preferencias {
  static const _kTextoGrande = 'texto_grande';

  /// Quando verdadeiro, o app inteiro usa letras 30% maiores.
  static final ValueNotifier<bool> textoGrande = ValueNotifier(false);

  static const _kKit = 'kit';
  static const _kRetrato = 'retrato_inicio';

  /// Itens do kit de emergência já separados (posições em [itensKit]).
  static final ValueNotifier<Set<int>> kit = ValueNotifier(<int>{});

  static Future<void> carregar() async {
    try {
      final p = await SharedPreferences.getInstance();
      textoGrande.value = p.getBool(_kTextoGrande) ?? false;
      kit.value = (p.getStringList(_kKit) ?? const []).map(int.tryParse).whereType<int>().toSet();
    } catch (_) {}
  }

  static Future<void> alternarItemKit(int i) async {
    final novo = {...kit.value};
    if (!novo.remove(i)) novo.add(i);
    kit.value = novo;
    try {
      (await SharedPreferences.getInstance()).setStringList(_kKit, [for (final x in novo) '$x']);
    } catch (_) {}
  }

  /// Último retrato da tela Início (aparece na hora e continua valendo sem internet).
  static Future<RetratoInicio?> lerRetrato() async {
    try {
      final texto = (await SharedPreferences.getInstance()).getString(_kRetrato);
      return texto == null ? null : RetratoInicio.fromJson(jsonDecode(texto));
    } catch (_) {
      return null;
    }
  }

  static Future<void> salvarRetrato(RetratoInicio r) async {
    try {
      (await SharedPreferences.getInstance()).setString(_kRetrato, jsonEncode(r.toJson()));
    } catch (_) {}
  }

  static Future<void> apagarRetrato() async {
    try {
      (await SharedPreferences.getInstance()).remove(_kRetrato);
    } catch (_) {}
  }

  static Future<void> alternarTextoGrande() async {
    textoGrande.value = !textoGrande.value;
    try {
      (await SharedPreferences.getInstance()).setBool(_kTextoGrande, textoGrande.value);
    } catch (_) {}
  }
}
/// Deixa só os dígitos e acrescenta o código do Brasil (55) se faltar.
String telefoneParaWhatsApp(String telefone) {
  final d = telefone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('55') && d.length >= 12) return d;
  return '55$d';
}

/// Abre o WhatsApp com mensagem pronta para o contato.
Future<bool> abrirWhatsApp(String telefone, String mensagem) {
  final uri = Uri.parse('https://wa.me/${telefoneParaWhatsApp(telefone)}?text=${Uri.encodeComponent(mensagem)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Liga para um número (193 bombeiros, 199 Defesa Civil...).
Future<bool> ligar(String numero) => launchUrl(Uri(scheme: 'tel', path: numero));

/// Abre rota no Google Maps até o destino.
Future<bool> abrirRota(double lat, double lon) => launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon'),
      mode: LaunchMode.externalApplication,
    );

/// Link do ponto no mapa, para mandar nas mensagens.
String linkMapa(double lat, double lon) => 'https://www.google.com/maps?q=$lat,$lon';
