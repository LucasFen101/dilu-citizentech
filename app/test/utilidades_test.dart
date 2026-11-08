import 'package:alerta_enchente/cidades_br.dart';
import 'package:alerta_enchente/clima_grade.dart';
import 'package:alerta_enchente/models.dart';
import 'package:alerta_enchente/risco_enchente.dart';
import 'package:latlong2/latlong.dart';
import 'package:alerta_enchente/services.dart';
import 'package:alerta_enchente/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telefone vira formato do WhatsApp com DDI 55', () {
    expect(telefoneParaWhatsApp('(11) 91234-5678'), '5511912345678');
    expect(telefoneParaWhatsApp('+55 11 91234-5678'), '5511912345678');
  });

  test('previsão de chuva é classificada por volume', () {
    expect(Chuva(mmProximas12h: 2, maxMmPorHora: 1, probabilidadeMax: 30).nivel, 'BAIXO');
    expect(Chuva(mmProximas12h: 10, maxMmPorHora: 3, probabilidadeMax: 70).nivel, 'MODERADO');
    expect(Chuva(mmProximas12h: 25, maxMmPorHora: 12, probabilidadeMax: 90).nivel, 'ALTO');
  });

  test('calor é classificado pela sensação térmica', () {
    Calor c(double s) => Calor(sensacaoMax: s, temperaturaMax: s - 2, uvMax: 8);
    expect(c(26).nivel, 'BAIXO');
    expect(c(32).nivel, 'MODERADO');
    expect(c(37).nivel, 'ALTO');
    expect(c(43).nivel, 'CRITICO');
  });

  test('alertas do clima só aparecem acima do nível baixo', () {
    final tranquilo = Clima(
      chuva: Chuva(mmProximas12h: 1, maxMmPorHora: 0.5, probabilidadeMax: 20),
      calor: Calor(sensacaoMax: 25, temperaturaMax: 24, uvMax: 3),
    );
    final extremo = Clima(
      chuva: Chuva(mmProximas12h: 30, maxMmPorHora: 12, probabilidadeMax: 95),
      calor: Calor(sensacaoMax: 38, temperaturaMax: 35, uvMax: 10),
    );
    expect(alertasDoClima(tranquilo), isEmpty);
    expect(alertasDoClima(extremo).length, 2);
  });

  test('rótulos de risco e gravidade', () {
    expect(rotuloNivel('CRITICO'), 'Crítico');
    expect(rotuloGravidade(4), 'Muito grave');
  });

  test('alagamento é lido do JSON da API', () {
    final a = Alagamento.fromJson({
      'id_alagamento': 7,
      'latitude': -23.559,
      'longitude': -46.599,
      'descricao': null,
      'gravidade': 3,
      'foto_url': null,
      'criado_em': '2026-11-05T10:00:00',
      'expira_em': '2026-11-05T19:00:00',
      'bairro': 'Mooca',
      'autor': 'Ana',
      'confirmacoes': 2,
      'confirmado_por_mim': false,
      'meu': true,
      'distancia_km': 1,
    });
    expect(a.bairro, 'Mooca');
    expect(a.distanciaKm, 1.0);
    expect(a.meu, isTrue);
  });

  group('mapa de clima', () {
    test('previsão de várias coordenadas é distribuída nas células', () {
      final g = gerarCidadesBrasil().take(2).toList();
      List<String> horas() => [for (var h = 0; h < 24; h++) '2026-11-07T${h.toString().padLeft(2, '0')}:00'];
      Map<String, dynamic> resposta(double temp, double mm) => {
            'current': {
              'time': '2026-11-07T14:30',
              'temperature_2m': temp,
              'apparent_temperature': temp + 2,
              'relative_humidity_2m': 70,
              'precipitation': mm,
              'weather_code': mm > 0 ? 61 : 1,
              'wind_speed_10m': 12.0,
            },
            'hourly': {'time': horas(), 'precipitation': List.generate(24, (h) => h >= 15 && h < 21 ? 1.0 : 0.0)},
          };
      aplicarPrevisao(g, [resposta(31, 0), resposta(18, 2.5)]);
      expect(g[0].chovendo, isFalse);
      expect(g[1].chovendo, isTrue);
      expect(g[1].temperatura, 18);
      expect(g[0].chuva6hMm, 6); // 15h às 20h, uma por hora
    });

    test('códigos e rótulos de tempo', () {
      expect(codigoChuva(61), isTrue);
      expect(codigoChuva(3), isFalse);
      expect(descricaoTempo(95), 'Tempestade');
    });
  });

  group('risco de enchente', () {
    RiscoCidade cidade(double recente, double prevista, {double? razao, double? vazao}) {
      final r = RiscoCidade(gerarCidadesBrasil().first)
        ..chuvaRecente3d = recente
        ..chuvaPrevista3d = prevista
        ..razaoVazao = razao
        ..vazaoAtual = vazao;
      calcularRisco(r);
      return r;
    }

    test('o nível sobe com a chuva somada (40% recente + 60% prevista)', () {
      expect(cidade(5, 10).nivel, 'BAIXO'); // 8
      expect(cidade(30, 40).nivel, 'MODERADO'); // 36
      expect(cidade(60, 80).nivel, 'ALTO'); // 72
      expect(cidade(100, 150).nivel, 'CRITICO'); // 130
    });

    test('a chuva prevista pesa mais do que a que já caiu', () {
      expect(cidade(0, 50).pontos, greaterThan(cidade(50, 0).pontos));
    });

    test('rio muito acima da média sobe um degrau, mas só se a vazão for relevante', () {
      expect(cidade(30, 40, razao: 2.5, vazao: 100).nivel, 'ALTO'); // moderado + 1
      expect(cidade(30, 40, razao: 2.5, vazao: 0.8).nivel, 'MODERADO'); // vazão irrelevante (ruído do modelo)
      expect(cidade(100, 150, razao: 3, vazao: 500).nivel, 'CRITICO'); // não passa do máximo
    });

    test('razão da vazão e leitura das respostas da API', () {
      expect(razaoVazao([100, 200], [100, 100]), 2.0);
      expect(razaoVazao([null], [null]), isNull);
      expect(razaoVazao([5], [0]), isNull);
      final lista = [RiscoCidade(gerarCidadesBrasil().first)];
      aplicarChuvaDiaria(lista, {'daily': {'precipitation_sum': [1, 2, 3, 4, 5, 6]}});
      expect(lista.first.chuvaRecente3d, 6);
      expect(lista.first.chuvaPrevista3d, 15);
    });
  });
  group('clima do Brasil', () {
    test('a lista de cidades cobre as cinco regiões, sem repetir cidade', () {
      final cs = gerarCidadesBrasil();
      expect(cs.length, greaterThanOrEqualTo(80));
      expect(cs.map((c) => '${c.nome}-${c.uf}').toSet().length, cs.length);
      expect(cs.map((c) => c.regiao).toSet(), {'Norte', 'Nordeste', 'Centro-Oeste', 'Sudeste', 'Sul'});
      // todas dentro do retângulo do território brasileiro
      expect(cs.every((c) => c.centro.latitude > -34 && c.centro.latitude < 6 && c.centro.longitude > -74 && c.centro.longitude < -34), isTrue);
    });

    test('as 27 capitais estão na lista', () {
      const capitais = ['Manaus', 'Belém', 'Porto Velho', 'Rio Branco', 'Boa Vista', 'Macapá', 'Palmas', 'São Luís', 'Teresina', 'Fortaleza',
        'Natal', 'João Pessoa', 'Recife', 'Maceió', 'Aracaju', 'Salvador', 'Brasília', 'Goiânia', 'Campo Grande', 'Cuiabá', 'São Paulo',
        'Rio de Janeiro', 'Belo Horizonte', 'Vitória', 'Curitiba', 'Florianópolis', 'Porto Alegre'];
      final nomes = gerarCidadesBrasil().map((c) => c.nome).toSet();
      expect(capitais.where((c) => !nomes.contains(c)), isEmpty);
    });

    test('tocar perto de uma cidade devolve ela; no meio do oceano, nada', () {
      final cs = gerarCidadesBrasil();
      expect(cidadeMaisProxima(cs, const LatLng(-8.1, -34.9))?.nome, 'Recife');
      expect(cidadeMaisProxima(cs, const LatLng(-20, -20)), isNull);
    });
  });

  group('conta', () {
    test('resumo e relatos do usuário são lidos do JSON da API', () {
      final r = ResumoUsuario.fromJson({
        'relatos_total': 3,
        'relatos_ativos': 1,
        'relatos_resolvidos': 2,
        'confirmacoes_recebidas': 5,
        'confirmacoes_dadas': 4,
        'pedidos_ajuda': 0,
      });
      expect(r.relatosTotal, 3);
      expect(r.confirmacoesRecebidas, 5);

      final m = MeuRelato.fromJson({
        'id_alagamento': 9,
        'gravidade': 2,
        'descricao': null,
        'status': 'ATIVO',
        'criado_em': '2026-11-08T10:00:00',
        'bairro': 'Mooca',
        'confirmacoes': 1,
      });
      expect(m.status, 'ATIVO');
      expect(m.bairro, 'Mooca');
    });
  });
}