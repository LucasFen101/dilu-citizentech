/// Cidades usadas no mapa de clima do Brasil: as 27 capitais e as principais
/// cidades de cada região (coordenadas aproximadas do centro urbano).
library;

import 'package:latlong2/latlong.dart';

import 'models.dart';

/// As cinco regiões do IBGE, com centro e zoom para o mapa focar nelas.
const regioesBrasil = <(String, LatLng, double)>[
  ('Norte', LatLng(-5.0, -60.0), 4.7),
  ('Nordeste', LatLng(-9.0, -40.0), 5.2),
  ('Centro-Oeste', LatLng(-16.0, -54.0), 5.2),
  ('Sudeste', LatLng(-21.5, -45.0), 5.7),
  ('Sul', LatLng(-27.5, -51.5), 5.8),
];

// (nome, UF, região, latitude, longitude)
const _cidades = <(String, String, String, double, double)>[
  // Norte
  ('Manaus', 'AM', 'Norte', -3.119, -60.022),
  ('Belém', 'PA', 'Norte', -1.456, -48.490),
  ('Porto Velho', 'RO', 'Norte', -8.762, -63.904),
  ('Rio Branco', 'AC', 'Norte', -9.975, -67.824),
  ('Boa Vista', 'RR', 'Norte', 2.820, -60.673),
  ('Macapá', 'AP', 'Norte', 0.035, -51.071),
  ('Palmas', 'TO', 'Norte', -10.249, -48.325),
  ('Santarém', 'PA', 'Norte', -2.443, -54.708),
  ('Marabá', 'PA', 'Norte', -5.368, -49.118),
  ('Altamira', 'PA', 'Norte', -3.203, -52.206),
  ('Tabatinga', 'AM', 'Norte', -4.250, -69.940),
  ('Ji-Paraná', 'RO', 'Norte', -10.885, -61.951),
  ('Cruzeiro do Sul', 'AC', 'Norte', -7.631, -72.670),
  ('Araguaína', 'TO', 'Norte', -7.192, -48.207),
  // Nordeste
  ('São Luís', 'MA', 'Nordeste', -2.530, -44.303),
  ('Teresina', 'PI', 'Nordeste', -5.089, -42.802),
  ('Fortaleza', 'CE', 'Nordeste', -3.732, -38.527),
  ('Natal', 'RN', 'Nordeste', -5.795, -35.209),
  ('João Pessoa', 'PB', 'Nordeste', -7.115, -34.861),
  ('Recife', 'PE', 'Nordeste', -8.047, -34.877),
  ('Maceió', 'AL', 'Nordeste', -9.666, -35.735),
  ('Aracaju', 'SE', 'Nordeste', -10.947, -37.073),
  ('Salvador', 'BA', 'Nordeste', -12.971, -38.501),
  ('Imperatriz', 'MA', 'Nordeste', -5.526, -47.492),
  ('Sobral', 'CE', 'Nordeste', -3.689, -40.350),
  ('Juazeiro do Norte', 'CE', 'Nordeste', -7.213, -39.315),
  ('Mossoró', 'RN', 'Nordeste', -5.188, -37.344),
  ('Campina Grande', 'PB', 'Nordeste', -7.230, -35.881),
  ('Petrolina', 'PE', 'Nordeste', -9.389, -40.503),
  ('Caruaru', 'PE', 'Nordeste', -8.284, -35.969),
  ('Feira de Santana', 'BA', 'Nordeste', -12.267, -38.967),
  ('Vitória da Conquista', 'BA', 'Nordeste', -14.866, -40.839),
  ('Barreiras', 'BA', 'Nordeste', -12.153, -44.990),
  ('Ilhéus', 'BA', 'Nordeste', -14.793, -39.046),
  ('Parnaíba', 'PI', 'Nordeste', -2.905, -41.777),
  // Centro-Oeste
  ('Brasília', 'DF', 'Centro-Oeste', -15.794, -47.882),
  ('Goiânia', 'GO', 'Centro-Oeste', -16.686, -49.264),
  ('Campo Grande', 'MS', 'Centro-Oeste', -20.469, -54.620),
  ('Cuiabá', 'MT', 'Centro-Oeste', -15.601, -56.097),
  ('Dourados', 'MS', 'Centro-Oeste', -22.221, -54.806),
  ('Rondonópolis', 'MT', 'Centro-Oeste', -16.470, -54.636),
  ('Sinop', 'MT', 'Centro-Oeste', -11.864, -55.502),
  ('Anápolis', 'GO', 'Centro-Oeste', -16.327, -48.953),
  ('Rio Verde', 'GO', 'Centro-Oeste', -17.798, -50.926),
  ('Corumbá', 'MS', 'Centro-Oeste', -19.007, -57.651),
  ('Alta Floresta', 'MT', 'Centro-Oeste', -9.876, -56.086),
  // Sudeste
  ('São Paulo', 'SP', 'Sudeste', -23.551, -46.633),
  ('Rio de Janeiro', 'RJ', 'Sudeste', -22.907, -43.173),
  ('Belo Horizonte', 'MG', 'Sudeste', -19.917, -43.935),
  ('Vitória', 'ES', 'Sudeste', -20.315, -40.313),
  ('Campinas', 'SP', 'Sudeste', -22.907, -47.063),
  ('Santos', 'SP', 'Sudeste', -23.961, -46.334),
  ('Ribeirão Preto', 'SP', 'Sudeste', -21.178, -47.810),
  ('São José do Rio Preto', 'SP', 'Sudeste', -20.812, -49.376),
  ('Sorocaba', 'SP', 'Sudeste', -23.502, -47.458),
  ('Presidente Prudente', 'SP', 'Sudeste', -22.126, -51.389),
  ('Uberlândia', 'MG', 'Sudeste', -18.919, -48.277),
  ('Juiz de Fora', 'MG', 'Sudeste', -21.761, -43.350),
  ('Montes Claros', 'MG', 'Sudeste', -16.735, -43.861),
  ('Governador Valadares', 'MG', 'Sudeste', -18.851, -41.949),
  ('Campos dos Goytacazes', 'RJ', 'Sudeste', -21.754, -41.324),
  ('Volta Redonda', 'RJ', 'Sudeste', -22.523, -44.104),
  ('Cachoeiro de Itapemirim', 'ES', 'Sudeste', -20.849, -41.113),
  ('Linhares', 'ES', 'Sudeste', -19.391, -40.072),
  ('Uberaba', 'MG', 'Sudeste', -19.748, -47.932),
  ('Poços de Caldas', 'MG', 'Sudeste', -21.787, -46.561),
  // Sul
  ('Curitiba', 'PR', 'Sul', -25.429, -49.271),
  ('Florianópolis', 'SC', 'Sul', -27.595, -48.548),
  ('Porto Alegre', 'RS', 'Sul', -30.035, -51.218),
  ('Londrina', 'PR', 'Sul', -23.310, -51.162),
  ('Maringá', 'PR', 'Sul', -23.425, -51.938),
  ('Foz do Iguaçu', 'PR', 'Sul', -25.547, -54.588),
  ('Joinville', 'SC', 'Sul', -26.304, -48.846),
  ('Blumenau', 'SC', 'Sul', -26.919, -49.066),
  ('Chapecó', 'SC', 'Sul', -27.100, -52.615),
  ('Caxias do Sul', 'RS', 'Sul', -29.168, -51.179),
  ('Pelotas', 'RS', 'Sul', -31.771, -52.342),
  ('Santa Maria', 'RS', 'Sul', -29.684, -53.807),
  ('Passo Fundo', 'RS', 'Sul', -28.262, -52.406),
  ('Uruguaiana', 'RS', 'Sul', -29.755, -57.088),
  ('Cascavel', 'PR', 'Sul', -24.955, -53.456),
  ('Ponta Grossa', 'PR', 'Sul', -25.095, -50.162),
  ('Lages', 'SC', 'Sul', -27.816, -50.326),
];

/// Cria uma célula de clima para cada cidade da lista.
List<CelulaClima> gerarCidadesBrasil() => [
      for (final c in _cidades)
        CelulaClima(centro: LatLng(c.$4, c.$5), nome: c.$1, uf: c.$2, regiao: c.$3),
    ];

/// A cidade mais próxima do ponto tocado, se estiver a até [maxKm] km.
CelulaClima? cidadeMaisProxima(List<CelulaClima> cidades, LatLng p, {double maxKm = 350}) {
  const dist = Distance();
  CelulaClima? melhor;
  var menor = double.infinity;
  for (final c in cidades) {
    final km = dist.as(LengthUnit.Kilometer, p, c.centro).toDouble();
    if (km < menor) {
      menor = km;
      melhor = c;
    }
  }
  return menor <= maxKm ? melhor : null;
}
