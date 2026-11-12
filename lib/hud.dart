import 'dart:math';

import 'package:flutter/material.dart';

/// Stile futuristico "HUD". Il fondo resta nero: dietro il vetro bidirezionale
/// il nero fa da specchio, quindi linee e griglie sono sottili e tenui.
class Hud {
  static const ciano = Color(0xFF4FE3FF);
  static const cianoTenue = Color(0x334FE3FF);
  static const ambra = Color(0xFFFFB547);
  static const rosso = Color(0xFFFF5B6B);

  static TextStyle orbitron(double size,
          {double peso = 400, Color colore = Colors.white, double spaziatura = 0, double? altezza}) =>
      TextStyle(
        fontFamily: 'Orbitron',
        fontSize: size,
        color: colore,
        letterSpacing: spaziatura,
        height: altezza,
        fontVariations: [FontVariation('wght', peso)],
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle testo(double size,
          {FontWeight peso = FontWeight.w500, Color colore = Colors.white70, double spaziatura = 1}) =>
      TextStyle(
        fontFamily: 'Rajdhani',
        fontSize: size,
        fontWeight: peso,
        color: colore,
        letterSpacing: spaziatura,
      );

  static const etichetta = TextStyle(
    fontFamily: 'Rajdhani',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: ciano,
    letterSpacing: 3,
  );
}

/// Sfondo: griglia prospettica in basso, angoli a staffa, linee di scansione.
class SfondoHud extends StatelessWidget {
  const SfondoHud({super.key});

  @override
  Widget build(BuildContext context) =>
      const RepaintBoundary(child: CustomPaint(painter: _PittoreSfondo(), size: Size.infinite));
}

class _PittoreSfondo extends CustomPainter {
  const _PittoreSfondo();

  @override
  void paint(Canvas canvas, Size s) {
    final linea = Paint()
      ..color = Hud.ciano.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Griglia prospettica sul "pavimento".
    final orizzonte = s.height * 0.72;
    final fuga = Offset(s.width / 2, s.height * 0.45);
    for (var k = -12; k <= 12; k++) {
      final x = s.width / 2 + k * s.width / 10;
      final inizio = Offset.lerp(fuga, Offset(x, s.height), (orizzonte - fuga.dy) / (s.height - fuga.dy))!;
      canvas.drawLine(inizio, Offset(x, s.height), linea);
    }
    for (var k = 0; k < 7; k++) {
      final t = pow(k / 6, 1.8).toDouble();
      final y = orizzonte + (s.height - orizzonte) * t;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), linea);
    }
    // Linea dell'orizzonte un po' più marcata, sfumata ai lati.
    canvas.drawLine(
      Offset(0, orizzonte),
      Offset(s.width, orizzonte),
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.transparent,
          Hud.ciano.withValues(alpha: 0.22),
          Colors.transparent,
        ]).createShader(Rect.fromLTWH(0, orizzonte, s.width, 1))
        ..strokeWidth = 1,
    );

    // Angoli a staffa.
    final staffa = Paint()
      ..color = Hud.ciano.withValues(alpha: 0.45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const l = 26.0, m = 10.0;
    for (final (x, y, dx, dy) in [
      (m, m, 1.0, 1.0),
      (s.width - m, m, -1.0, 1.0),
      (m, s.height - m, 1.0, -1.0),
      (s.width - m, s.height - m, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * l)
          ..lineTo(x, y)
          ..lineTo(x + dx * l, y),
        staffa,
      );
    }

    // Righello in alto con tacche.
    final tacca = Paint()
      ..color = Hud.ciano.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var x = s.width * 0.3; x <= s.width * 0.7; x += 8) {
      final lunga = ((x - s.width * 0.3) / 8).round() % 5 == 0;
      canvas.drawLine(Offset(x, 14), Offset(x, lunga ? 22 : 18), tacca);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Quadrante circolare dell'orologio: tacche dei minuti, arco dei secondi.
class QuadranteHud extends StatelessWidget {
  final DateTime ora;
  final Widget child;
  final double diametro;
  const QuadranteHud({super.key, required this.ora, required this.child, this.diametro = 220});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: diametro,
        child: CustomPaint(
          painter: _PittoreQuadrante(ora.second + ora.millisecond / 1000),
          child: Center(child: child),
        ),
      );
}

class _PittoreQuadrante extends CustomPainter {
  final double secondi;
  _PittoreQuadrante(this.secondi);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 6;

    // Anello esterno tenue.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Hud.ciano.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // 60 tacche, quelle dei 5 minuti più lunghe.
    for (var k = 0; k < 60; k++) {
      final a = -pi / 2 + k * pi / 30;
      final lunga = k % 5 == 0;
      final passata = k <= secondi;
      final p = Paint()
        ..color = passata ? Hud.ciano.withValues(alpha: lunga ? 0.9 : 0.55) : Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = lunga ? 2 : 1;
      final dentro = r - (lunga ? 12 : 7);
      canvas.drawLine(c + Offset(cos(a), sin(a)) * dentro, c + Offset(cos(a), sin(a)) * (r - 2), p);
    }

    // Arco dei secondi con alone.
    final arco = Rect.fromCircle(center: c, radius: r + 3);
    final sweep = 2 * pi * (secondi / 60);
    canvas.drawArc(
        arco,
        -pi / 2,
        sweep,
        false,
        Paint()
          ..color = Hud.ciano.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawArc(
        arco,
        -pi / 2,
        sweep,
        false,
        Paint()
          ..color = Hud.ciano
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2);

    // Anello interno tratteggiato.
    final interno = r - 22;
    for (var k = 0; k < 36; k++) {
      final a = k * pi / 18;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: interno),
          a,
          pi / 36,
          false,
          Paint()
            ..color = Hud.ciano.withValues(alpha: 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_PittoreQuadrante old) => old.secondi != secondi;
}

/// Pannello con angoli tagliati e bordo luminoso.
class PannelloHud extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color colore;
  const PannelloHud({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 10),
    this.colore = Hud.ciano,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PittorePannello(colore),
        child: Padding(padding: padding, child: child),
      );
}

class _PittorePannello extends CustomPainter {
  final Color colore;
  _PittorePannello(this.colore);

  @override
  void paint(Canvas canvas, Size s) {
    const t = 12.0;
    final forma = Path()
      ..moveTo(t, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height - t)
      ..lineTo(s.width - t, s.height)
      ..lineTo(0, s.height)
      ..lineTo(0, t)
      ..close();
    canvas.drawPath(
        forma,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colore.withValues(alpha: 0.10), colore.withValues(alpha: 0.02)],
          ).createShader(Offset.zero & s));
    canvas.drawPath(
        forma,
        Paint()
          ..color = colore.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    // Trattino luminoso sull'angolo tagliato.
    canvas.drawLine(
        const Offset(0, t),
        const Offset(t, 0),
        Paint()
          ..color = colore
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_PittorePannello old) => old.colore != colore;
}

/// Pulsante HUD con angoli tagliati.
class BottoneHud extends StatelessWidget {
  final IconData icona;
  final String testo;
  final VoidCallback onTap;
  const BottoneHud({super.key, required this.icona, required this.testo, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: PannelloHud(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icona, size: 18, color: Hud.ciano),
              const SizedBox(width: 8),
              Text(testo.toUpperCase(), style: Hud.testo(15, peso: FontWeight.w600, colore: Colors.white, spaziatura: 3)),
            ],
          ),
        ),
      );
}

/// Barra della batteria a segmenti.
class BatteriaHud extends StatelessWidget {
  final int livello;
  final bool inCarica;
  const BatteriaHud({super.key, required this.livello, required this.inCarica});

  @override
  Widget build(BuildContext context) {
    final colore = livello <= 30 && !inCarica ? Hud.rosso : Hud.ciano;
    final pieni = (livello / 10).ceil();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < 10; k++)
          Container(
            width: 4,
            height: 12,
            margin: const EdgeInsets.only(right: 2),
            color: k < pieni ? colore.withValues(alpha: 0.85) : colore.withValues(alpha: 0.12),
          ),
        const SizedBox(width: 8),
        Text('$livello%', style: Hud.orbitron(11, colore: colore.withValues(alpha: 0.85))),
        if (inCarica) ...[
          const SizedBox(width: 4),
          Icon(Icons.bolt, size: 14, color: colore),
        ],
      ],
    );
  }
}

/// CPU e RAM usate e disco libero, in piccolo accanto alla batteria.
class RisorseHud extends StatelessWidget {
  final double? cpu;
  final double ram;
  final double discoLiberoGb;
  const RisorseHud({super.key, required this.cpu, required this.ram, required this.discoLiberoGb});

  @override
  Widget build(BuildContext context) {
    Widget voce(String etichetta, String valore, {bool allarme = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(etichetta, style: Hud.etichetta.copyWith(fontSize: 11, letterSpacing: 1,
                color: (allarme ? Hud.rosso : Hud.ciano).withValues(alpha: 0.7))),
            const SizedBox(width: 4),
            Text(valore, style: Hud.orbitron(11, colore: allarme ? Hud.rosso : Colors.white70)),
          ],
        );
    final gb = discoLiberoGb < 10 ? discoLiberoGb.toStringAsFixed(1) : discoLiberoGb.round().toString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        voce('CPU', cpu == null ? '--' : '${cpu!.round()}%', allarme: (cpu ?? 0) > 85),
        const SizedBox(width: 10),
        voce('RAM', '${ram.round()}%', allarme: ram > 90),
        const SizedBox(width: 10),
        voce('DISCO', '$gb GB', allarme: discoLiberoGb < 1),
      ],
    );
  }
}
