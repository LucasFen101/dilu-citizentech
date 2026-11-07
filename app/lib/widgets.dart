/// Peças visuais próprias do Dilu: gota, logo, marcador do mapa e etiquetas.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import 'services.dart';
import 'theme.dart';

/// Desenha a gota (forma da marca). Com [apontaBaixo] vira um alfinete de mapa.
class _GotaPainter extends CustomPainter {
  final Color cor;
  final bool apontaBaixo;
  final bool furo;
  _GotaPainter(this.cor, this.apontaBaixo, this.furo);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final r = w / 2;
    if (apontaBaixo) {
      canvas.translate(0, h);
      canvas.scale(1, -1);
    }
    final caminho = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.62, h * 0.18, w, h * 0.42, w, h - r)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r), clockwise: true)
      ..cubicTo(0, h * 0.42, w * 0.38, h * 0.18, w / 2, 0)
      ..close();
    canvas.drawPath(caminho, Paint()..color = cor);
    if (furo) {
      canvas.drawCircle(Offset(w / 2, h - r), r * 0.42, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_GotaPainter o) => o.cor != cor || o.apontaBaixo != apontaBaixo || o.furo != furo;
}

/// Gota simples (ícone da marca).
class Gota extends StatelessWidget {
  final double largura;
  final Color cor;
  const Gota({super.key, required this.largura, this.cor = kSinal});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(largura, largura * 1.45),
        painter: _GotaPainter(cor, false, false),
      );
}

/// Alfinete em formato de gota para o mapa.
class MarcadorGota extends StatelessWidget {
  final Color cor;
  final double largura;
  const MarcadorGota({super.key, required this.cor, this.largura = 34});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(largura, largura * 1.4),
        painter: _GotaPainter(cor, true, true),
      );
}

/// Logo: "dilu" com uma gota no lugar do acento sobre o "u".
class DiluLogo extends StatelessWidget {
  final double tamanho;
  final Color cor;
  final Color corGota;
  const DiluLogo({super.key, this.tamanho = 48, this.cor = kTinta, this.corGota = kSinal});

  @override
  Widget build(BuildContext context) {
    final estilo = GoogleFonts.fraunces(
      fontSize: tamanho,
      fontWeight: FontWeight.w700,
      color: cor,
      height: 1,
      letterSpacing: -tamanho * 0.02,
    );
    final larguraGota = tamanho * 0.17;
    return Semantics(
      label: 'Dilu',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('dil', style: estilo),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Text('u', style: estilo),
                Positioned(
                  left: tamanho * 0.29 - larguraGota / 2,
                  top: -tamanho * 0.04,
                  child: Gota(largura: larguraGota, cor: corGota),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ondas concêntricas, como gotas caindo na água (fundo decorativo).
class Ondas extends StatelessWidget {
  final Color cor;
  const Ondas({super.key, this.cor = kPapel});

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _OndasPainter(cor), size: Size.infinite));
}

class _OndasPainter extends CustomPainter {
  final Color cor;
  _OndasPainter(this.cor);

  @override
  void paint(Canvas canvas, Size s) {
    final centro = Offset(s.width * 0.82, s.height * 0.78);
    for (var i = 1; i <= 9; i++) {
      final raio = i * 38.0;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = cor.withValues(alpha: (0.20 - i * 0.018).clamp(0.02, 0.2));
      // elipse achatada = perspectiva de uma superfície de água
      canvas.drawOval(Rect.fromCenter(center: centro, width: raio * 2.4, height: raio * 0.9), p);
    }
  }

  @override
  bool shouldRepaint(_OndasPainter o) => o.cor != cor;
}

/// Etiqueta chapada (substitui o "chip" padrão do Material).
class Etiqueta extends StatelessWidget {
  final String texto;
  final Color cor;
  final IconData? icone;
  const Etiqueta(this.texto, {super.key, required this.cor, this.icone});

  @override
  Widget build(BuildContext context) {
    final fg = textoSobre(cor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icone != null) ...[Icon(icone, size: 15, color: fg), const SizedBox(width: 5)],
        Text(texto.toUpperCase(),
            style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: fg)),
      ]),
    );
  }
}

/// Título de seção em caixa-alta pequena.
class Rotulo extends StatelessWidget {
  final String texto;
  const Rotulo(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(texto.toUpperCase(),
            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: kTintaSuave)),
      );
}

// Dessatura o mapa e esquenta os tons para combinar com o papel do Dilu.
const _filtroPapel = ColorFilter.matrix(<double>[
  0.327, 0.429, 0.043, 0, 56, //
  0.127, 0.629, 0.043, 0, 52, //
  0.127, 0.429, 0.243, 0, 37, //
  0, 0, 0, 1, 0,
]);

/// Camada base do mapa (OpenStreetMap) com o filtro da identidade visual.
TileLayer camadaBase(BuildContext context) => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'br.alertaenchente.alerta_enchente',
      retinaMode: RetinaMode.isHighDensity(context),
      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _filtroPapel, child: tile),
    );

/// Crédito do OpenStreetMap, sempre visível (a licença dos dados exige citar a fonte).
/// Tocar abre a página oficial de direitos autorais do OSM.
Widget atribuicaoMapa() => const _AtribuicaoOsm();

class _AtribuicaoOsm extends StatelessWidget {
  const _AtribuicaoOsm();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Semantics(
        button: true,
        label: 'Mapa com dados dos colaboradores do OpenStreetMap. Abrir direitos autorais.',
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: kPapelClaro.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(5)),
            child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10.5, color: kTinta, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
/// Botão "Aa" que liga/desliga o modo de texto grande (acessibilidade).
class BotaoTextoGrande extends StatelessWidget {
  final Color? cor;
  const BotaoTextoGrande({super.key, this.cor});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: Preferencias.textoGrande,
        builder: (_, grande, _) => IconButton(
          tooltip: grande ? 'Voltar ao texto normal' : 'Aumentar o texto',
          isSelected: grande,
          style: IconButton.styleFrom(
            foregroundColor: cor ?? kTinta,
            backgroundColor: grande ? kSinal.withValues(alpha: 0.3) : Colors.transparent,
          ),
          icon: const Icon(Icons.text_increase),
          onPressed: Preferencias.alternarTextoGrande,
        ),
      );
}

/// Manchas de cor suaves (degradê radial) sobre pontos do mapa, sem polígonos.
/// Lê a câmera do mapa para acompanhar zoom e arrasto. Cor nula = não pinta.
class ManchasMapa extends StatelessWidget {
  final List<(LatLng, Color?)> pontos;
  final double raioKm;
  const ManchasMapa({super.key, required this.pontos, this.raioKm = 230});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: _ManchasPainter(camera, pontos, raioKm)),
    );
  }
}

class _ManchasPainter extends CustomPainter {
  final MapCamera camera;
  final List<(LatLng, Color?)> pontos;
  final double raioKm;
  _ManchasPainter(this.camera, this.pontos, this.raioKm);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pontos) {
      final cor = p.$2;
      if (cor == null) continue;
      final centro = camera.latLngToScreenOffset(p.$1);
      // metros por pixel naquele ponto e zoom (tiles de 256 px)
      final mPorPx = 156543.03392 * cos(p.$1.latitudeInRad) / pow(2, camera.zoom);
      final raioPx = raioKm * 1000 / mPorPx;
      if (centro.dx < -raioPx || centro.dy < -raioPx || centro.dx > size.width + raioPx || centro.dy > size.height + raioPx) continue;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [cor, cor.withValues(alpha: cor.a * 0.55), cor.withValues(alpha: 0)],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: centro, radius: raioPx));
      canvas.drawCircle(centro, raioPx, paint);
    }
  }

  @override
  bool shouldRepaint(_ManchasPainter o) => true; // a câmera muda a cada gesto
}