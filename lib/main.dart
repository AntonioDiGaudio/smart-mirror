import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'comuni.dart';
import 'hud.dart';
import 'jarvis.dart';
import 'media.dart';
import 'meteo.dart';
import 'sistema.dart';

// Città mostrate nel meteo. Per aggiungerne una basta una riga qui.
const citta = [
  Citta('Terni', 42.5636, 12.6427),
  Citta('Palermo', 38.1157, 13.3615),
];

// Sotto questa percentuale (e non in carica) compare l'avviso a schermo.
const sogliaBatteria = 30;

// Ogni quanto riscaricare il meteo (solo mentre lo schermo è acceso).
const aggiornaMeteoOgni = Duration(minutes: 15);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  Presenza.istanza.avvia();
  Jarvis.istanza
    ..citta = citta
    ..avvia();
  runApp(const SpecchioApp());
}

class SpecchioApp extends StatelessWidget {
  const SpecchioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart mirror',
      debugShowCheckedModeBanner: false,
      navigatorKey: Jarvis.istanza.navigatore,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Nero puro: dietro il vetro bidirezionale il nero fa da specchio.
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(surface: Colors.black, primary: Hud.ciano),
        // Stile futuristico in tutta l'app.
        fontFamily: 'Rajdhani',
      ),
      // Ogni tocco conta come "c'è qualcuno": lo schermo resta acceso.
      builder: (context, child) => Listener(
        onPointerDown: (_) => Presenza.istanza.segnala(),
        child: Stack(
          children: [
            ?child,
            const Positioned.fill(child: SovrapposizioneJarvis()),
            // Nessuno davanti e niente permesso per spegnere: tutto nero.
            Positioned.fill(
              child: ValueListenableBuilder(
                valueListenable: Presenza.istanza.schermoNero,
                builder: (_, nero, _) => nero
                    ? const ColoredBox(color: Colors.black)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
      home: const Specchio(),
    );
  }
}

class Specchio extends StatefulWidget {
  const Specchio({super.key});

  @override
  State<Specchio> createState() => _SpecchioState();
}

class _SpecchioState extends State<Specchio> with WidgetsBindingObserver {
  final _random = Random();
  final Map<String, Previsioni> _meteo = {};
  final List<Timer> _timer = [];

  DateTime _ora = DateTime.now();
  Offset _spostamento = Offset.zero;
  int? _batteria;
  bool _inCarica = false;
  ({double? cpu, double ram, double discoLiberoGb, double discoLiberoPerc})? _risorse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Jarvis.istanza.meteo = () => _meteo;
    _accendi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spegni();
    super.dispose();
  }

  // A schermo spento non gira niente: niente timer, niente rete.
  @override
  void didChangeAppLifecycleState(AppLifecycleState stato) {
    if (stato == AppLifecycleState.resumed) {
      _accendi();
      Presenza.istanza.segnala();
    } else if (stato == AppLifecycleState.paused || stato == AppLifecycleState.hidden) {
      _spegni();
    }
  }

  void _accendi() {
    if (_timer.isNotEmpty) return;
    setState(() => _ora = DateTime.now());
    _timer.add(Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _ora = DateTime.now());
    }));
    // Lo schermo è AMOLED: spostando tutto di qualche pixel ogni minuto
    // si evita che ora e testi restino "stampati" sul display.
    _timer.add(Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() => _spostamento = Offset(
            _random.nextDouble() * 12 - 6,
            _random.nextDouble() * 12 - 6,
          ));
    }));
    _timer.add(Timer.periodic(const Duration(minutes: 1), (_) => _aggiornaMeteo()));
    _timer.add(Timer.periodic(const Duration(seconds: 30), (_) => _aggiornaBatteria()));
    _timer.add(Timer.periodic(const Duration(seconds: 3), (_) => _aggiornaRisorse()));
    _aggiornaMeteo();
    _aggiornaBatteria();
    _aggiornaRisorse();
  }

  Future<void> _aggiornaRisorse() async {
    final r = await Sistema.risorse();
    if (r == null || !mounted) return;
    // La CPU arriva solo dalla seconda lettura: intanto si tiene quella vecchia.
    setState(() => _risorse = r.cpu == null && _risorse?.cpu != null
        ? (cpu: _risorse!.cpu, ram: r.ram, discoLiberoGb: r.discoLiberoGb, discoLiberoPerc: r.discoLiberoPerc)
        : r);
  }

  void _spegni() {
    for (final t in _timer) {
      t.cancel();
    }
    _timer.clear();
  }

  Future<void> _aggiornaBatteria() async {
    final b = await Sistema.batteria();
    if (b == null || !mounted) return;
    setState(() {
      _batteria = b.livello;
      _inCarica = b.inCarica;
    });
  }

  Future<void> _aggiornaMeteo() async {
    for (final c in citta) {
      final vecchio = _meteo[c.nome];
      if (vecchio != null && DateTime.now().difference(vecchio.scaricate) < aggiornaMeteoOgni) {
        continue;
      }
      try {
        final p = await scaricaPrevisioni(c);
        if (mounted) setState(() => _meteo[c.nome] = p);
      } catch (_) {
        // Senza rete resta l'ultimo meteo scaricato; si riprova al prossimo giro.
      }
    }
  }

  void _apri(Widget pagina) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));

  @override
  Widget build(BuildContext context) {
    final batteriaBassa = _batteria != null && !_inCarica && _batteria! <= sogliaBatteria;
    return PopScope(
      canPop: false, // È la Home: il tasto Indietro non deve chiuderla.
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Pressione lunga sullo sfondo: apre le Impostazioni di Android.
          onLongPress: Sistema.apriImpostazioni,
          child: Transform.translate(
            offset: _spostamento,
            child: Stack(
              children: [
                const Positioned.fill(child: SfondoHud()),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(30, 20, 30, 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Sinistra: orologio e comandi.
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(width: 6, height: 6, color: Hud.ciano),
                                const SizedBox(width: 8),
                                const Text('SMART MIRROR  //  J.A.R.V.I.S.', style: Hud.etichetta),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _Orologio(ora: _ora),
                            const Spacer(),
                            if (batteriaBassa) ...[
                              _AvvisoBatteria(livello: _batteria!),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              children: [
                                BottoneHud(
                                    icona: Icons.photo_outlined,
                                    testo: 'Foto',
                                    onTap: () => _apri(const PaginaFoto())),
                                const SizedBox(width: 12),
                                BottoneHud(
                                    icona: Icons.play_arrow_rounded,
                                    testo: 'Video',
                                    onTap: () => _apri(const PaginaVideo())),
                              ],
                            ),
                          ],
                        ),
                        // Centro vuoto: lì ci si specchia.
                        const Spacer(),
                        // Destra: meteo.
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('METEO  //  LIVE', style: Hud.etichetta),
                            const SizedBox(height: 8),
                            for (final c in citta) ...[
                              RiquadroMeteo(citta: c, previsioni: _meteo[c.nome]),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // In basso a destra: CPU, RAM, disco e batteria (a parte, così
                // non allarga la colonna del meteo). Spazio a destra per il microfono.
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      // A sinistra lascia libero lo spazio dei bottoni Foto e Video.
                      padding: const EdgeInsets.only(left: 280, right: 62, bottom: 30),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_risorse != null) ...[
                              RisorseHud(
                                cpu: _risorse!.cpu,
                                ram: _risorse!.ram,
                                discoLiberoGb: _risorse!.discoLiberoGb,
                              ),
                              const SizedBox(width: 14),
                            ],
                            if (_batteria != null) BatteriaHud(livello: _batteria!, inCarica: _inCarica),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Orologio extends StatelessWidget {
  final DateTime ora;
  const _Orologio({required this.ora});

  @override
  Widget build(BuildContext context) {
    String due(int n) => n.toString().padLeft(2, '0');
    final giorno = giorniSettimana[ora.weekday - 1].toUpperCase();
    return QuadranteHud(
      ora: ora,
      diametro: 214,
      child: SizedBox(
        width: 148,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text('${due(ora.hour)}:${due(ora.minute)}',
                  style: Hud.orbitron(42, peso: 500, altezza: 1.1)),
            ),
            const SizedBox(height: 6),
            Text(giorno, style: Hud.testo(13, peso: FontWeight.w600, colore: Hud.ciano, spaziatura: 4)),
            Text('${ora.day} ${mesi[ora.month - 1].toUpperCase()}',
                style: Hud.testo(15, peso: FontWeight.w500, colore: Colors.white70, spaziatura: 2)),
          ],
        ),
      ),
    );
  }
}

class _AvvisoBatteria extends StatelessWidget {
  final int livello;
  const _AvvisoBatteria({required this.livello});

  @override
  Widget build(BuildContext context) => PannelloHud(
        colore: Hud.rosso,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.battery_alert, color: Hud.rosso, size: 30),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BATTERIA $livello%', style: Hud.orbitron(15, peso: 600, colore: Hud.rosso, spaziatura: 1)),
                Text('Metti in carica lo specchio', style: Hud.testo(15, colore: Colors.white)),
              ],
            ),
          ],
        ),
      );
}
