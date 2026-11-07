/// Identidade visual do Dilu.
///
/// Conceito: "dilúvio". Tinta petróleo (a água funda) sobre papel quente
/// (o mapa de papel), com um único laranja de sinalização, que é a gota.
/// Sem sombras, sem gradientes: linhas finas e tipografia editorial.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---- paleta -------------------------------------------------------------
const kTinta = Color(0xFF0F2A2E); // petróleo escuro: texto, botões, marca
const kTintaSuave = Color(0xFF55696B); // texto secundário
const kPapel = Color(0xFFF4EFE6); // fundo
const kPapelClaro = Color(0xFFFBF8F2); // superfícies
const kLinha = Color(0x330F2A2E); // contornos finos
const kAreia = Color(0xFFEADFC8); // destaques suaves
const kAgua = Color(0xFF1B6E78); // água / informação
const kSinal = Color(0xFFFF6B35); // a gota: único acento vivo
const kBrasa = Color(0xFFB3202F); // emergência (SOS)
const kMusgo = Color(0xFF2F7D5B); // seguro / resolvido

const _kBaixo = Color(0xFF3E8E7E);
const _kModerado = Color(0xFFE0A526);
const _kAlto = Color(0xFFE4572E);
const _kCritico = Color(0xFF7A1F2B);
const _kLeve = Color(0xFF4F8FA3);

ThemeData construirTema() {
  const esquema = ColorScheme.light(
    primary: kTinta,
    onPrimary: kPapel,
    secondary: kSinal,
    onSecondary: kTinta,
    surface: kPapelClaro,
    onSurface: kTinta,
    error: kBrasa,
    onError: Colors.white,
    outline: kLinha,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: esquema);
  final corpo = GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: kTinta, displayColor: kTinta);
  TextStyle titulo(double tamanho, [FontWeight peso = FontWeight.w600]) =>
      GoogleFonts.fraunces(fontSize: tamanho, fontWeight: peso, color: kTinta, height: 1.15);
  final texto = corpo.copyWith(
    headlineLarge: titulo(34, FontWeight.w700),
    headlineMedium: titulo(28, FontWeight.w700),
    headlineSmall: titulo(24),
    titleLarge: titulo(22),
    titleMedium: titulo(18),
  );

  const raio = 10.0;
  final contorno = RoundedRectangleBorder(borderRadius: BorderRadius.circular(raio));

  return base.copyWith(
    scaffoldBackgroundColor: kPapel,
    textTheme: texto,
    appBarTheme: AppBarTheme(
      backgroundColor: kPapel,
      foregroundColor: kTinta,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: titulo(22),
      shape: const Border(bottom: BorderSide(color: kLinha)),
    ),
    cardTheme: CardThemeData(
      color: kPapelClaro,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kLinha)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kTinta,
        foregroundColor: kPapel,
        minimumSize: const Size.fromHeight(52),
        shape: contorno,
        textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kTinta,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: kTinta, width: 1.4),
        shape: contorno,
        textStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAgua,
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kPapelClaro,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(raio), borderSide: const BorderSide(color: kLinha)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(raio), borderSide: const BorderSide(color: kLinha)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(raio), borderSide: const BorderSide(color: kTinta, width: 2)),
      labelStyle: const TextStyle(color: kTintaSuave),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(contorno),
        side: const WidgetStatePropertyAll(BorderSide(color: kTinta, width: 1.2)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kTinta : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kPapel : kTinta),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kPapel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 70,
      indicatorColor: kSinal.withValues(alpha: 0.28),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? kTinta : kTintaSuave, size: 26)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.manrope(
          fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: kTinta)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: kTinta,
      unselectedLabelColor: kTintaSuave,
      indicatorColor: kSinal,
      dividerColor: kLinha,
      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kPapel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: titulo(22),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kPapel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kTinta,
      contentTextStyle: GoogleFonts.manrope(color: kPapel, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: contorno,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: kTinta,
      collapsedIconColor: kTinta,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kSinal),
    dividerColor: kLinha,
  );
}

/// Cor de cada nível de risco do bairro.
Color corNivel(String nivel) => switch (nivel) {
      'CRITICO' => _kCritico,
      'ALTO' => _kAlto,
      'MODERADO' => _kModerado,
      _ => _kBaixo,
    };

String rotuloNivel(String nivel) => switch (nivel) {
      'CRITICO' => 'Crítico',
      'ALTO' => 'Alto',
      'MODERADO' => 'Moderado',
      _ => 'Baixo',
    };

/// Cor de cada gravidade de alagamento (1 a 4).
Color corGravidade(int g) => switch (g) {
      4 => _kCritico,
      3 => _kAlto,
      2 => _kModerado,
      _ => _kLeve,
    };

String rotuloGravidade(int g) => switch (g) {
      4 => 'Muito grave',
      3 => 'Grave',
      2 => 'Moderado',
      _ => 'Leve',
    };

String descricaoGravidade(int g) => switch (g) {
      4 => 'Água muito alta, risco para pessoas e veículos',
      3 => 'Rua intransitável para carros',
      2 => 'Acúmulo de água, passagem difícil',
      _ => 'Poças e água na calçada',
    };

/// Cor de texto legível sobre um fundo (escuro sobre cores claras).
Color textoSobre(Color fundo) => fundo.computeLuminance() > 0.45 ? kTinta : Colors.white;

/// Mostra uma mensagem rápida na parte de baixo da tela.
void aviso(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? kBrasa : kTinta,
    ));
}


// ---- escalas de cor do mapa de clima -------------------------------------
Color _escala(double v, List<(double, Color)> paradas) {
  if (v <= paradas.first.$1) return paradas.first.$2;
  for (var i = 1; i < paradas.length; i++) {
    if (v <= paradas[i].$1) {
      final a = paradas[i - 1], b = paradas[i];
      return Color.lerp(a.$2, b.$2, (v - a.$1) / (b.$1 - a.$1))!;
    }
  }
  return paradas.last.$2;
}

/// Chuva em mm/h: do céu seco ao temporal.
const paradasChuva = <(double, Color)>[
  (0, Color(0xFFDCE8F5)),
  (0.2, Color(0xFFA9CBEA)),
  (1, Color(0xFF6FA5DA)),
  (3, Color(0xFF3C78C2)),
  (8, Color(0xFF23479A)),
  (15, Color(0xFF1B2A6B)),
];

/// Temperatura em °C: do frio (azul) ao calor extremo (vinho).
const paradasTemperatura = <(double, Color)>[
  (8, Color(0xFF2B4C9B)),
  (14, Color(0xFF5B93C8)),
  (19, Color(0xFF9FCDBE)),
  (23, Color(0xFFE8DCA0)),
  (27, Color(0xFFF0B84A)),
  (31, Color(0xFFE4572E)),
  (36, Color(0xFF9E1F2E)),
];

/// Umidade relativa em %: do ar seco (areia) ao muito úmido (petróleo).
const paradasUmidade = <(double, Color)>[
  (30, Color(0xFFEADFC8)),
  (60, Color(0xFFA8D0C6)),
  (85, Color(0xFF2E8A94)),
  (100, Color(0xFF145A66)),
];

Color corChuva(double mm) => _escala(mm, paradasChuva);
Color corTemperatura(double c) => _escala(c, paradasTemperatura);
Color corUmidade(double u) => _escala(u, paradasUmidade);

/// Azul da nuvem de chuva.
const kChuva = Color(0xFF2F6DB5);

String rotuloChuva(double mm) => mm < 0.1 ? 'Sem chuva' : (mm < 2.5 ? 'Chuva fraca' : (mm < 7.5 ? 'Chuva moderada' : 'Chuva forte'));

String rotuloTemperatura(double c) =>
    c < 12 ? 'Muito frio' : (c < 18 ? 'Frio' : (c < 26 ? 'Agradável' : (c < 31 ? 'Quente' : (c < 36 ? 'Muito quente' : 'Calor extremo'))));

String rotuloUmidade(double u) => u < 40 ? 'Ar seco' : (u < 70 ? 'Confortável' : (u < 85 ? 'Úmido' : 'Muito úmido'));