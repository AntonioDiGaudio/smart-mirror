import 'dart:async';

import 'package:flutter/material.dart';

import 'jarvis.dart';

const giorniSettimana = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];
const mesi = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
];

String nomeGiorno(DateTime d) => '${giorniSettimana[d.weekday - 1]} ${d.day}';

String nomeGiornoCorto(DateTime d) {
  final g = giorniSettimana[d.weekday - 1];
  return '${g[0].toUpperCase()}${g.substring(1, 3)} ${d.day}';
}

/// Dopo questo tempo senza tocchi una pagina (meteo, foto) torna allo specchio.
const tornaAlloSpecchioDopo = Duration(seconds: 90);

class PaginaACasaDaSola extends StatefulWidget {
  final Widget child;
  const PaginaACasaDaSola({super.key, required this.child});

  @override
  State<PaginaACasaDaSola> createState() => _PaginaACasaDaSolaState();
}

class _PaginaACasaDaSolaState extends State<PaginaACasaDaSola> {
  Timer? _timer;

  void _riparti() {
    _timer?.cancel();
    _timer = Timer(tornaAlloSpecchioDopo, () {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  void initState() {
    super.initState();
    _riparti();
    // Anche i comandi vocali contano come "la sto usando".
    Jarvis.istanza.attivita.addListener(_riparti);
  }

  @override
  void dispose() {
    Jarvis.istanza.attivita.removeListener(_riparti);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: (_) => _riparti(), child: widget.child);
}

class BottoneChiudi extends StatelessWidget {
  const BottoneChiudi({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close, size: 30, color: Colors.white70),
        tooltip: 'Torna allo specchio',
      );
}
