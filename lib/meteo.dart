import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'comuni.dart';
import 'hud.dart';
import 'jarvis.dart';

class Citta {
  final String nome;
  final double lat, lon;
  const Citta(this.nome, this.lat, this.lon);
}

class Ora {
  final DateTime quando;
  final double temperatura;
  final int codice, pioggia;
  final bool giorno;
  Ora(this.quando, this.temperatura, this.codice, this.pioggia, this.giorno);
}

class Giorno {
  final DateTime data;
  final double minima, massima;
  final int codice, pioggia;
  Giorno(this.data, this.minima, this.massima, this.codice, this.pioggia);
}

class Previsioni {
  final double temperatura;
  final int codice;
  final bool giorno;
  final List<Giorno> giorni;
  final List<Ora> ore;
  final DateTime scaricate;
  Previsioni(this.temperatura, this.codice, this.giorno, this.giorni, this.ore, this.scaricate);

  Giorno get oggi => giorni.first;

  List<Ora> oreDel(DateTime giorno) => [
        for (final o in ore)
          if (o.quando.year == giorno.year &&
              o.quando.month == giorno.month &&
              o.quando.day == giorno.day)
            o,
      ];
}

Future<Previsioni> scaricaPrevisioni(Citta c) async {
  final url = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': '${c.lat}',
    'longitude': '${c.lon}',
    'current': 'temperature_2m,weather_code,is_day',
    'hourly': 'temperature_2m,weather_code,precipitation_probability,is_day',
    'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
    'timezone': 'Europe/Rome',
    'forecast_days': '7',
  });
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final Map<String, dynamic> j;
  try {
    final risposta = await (await client.getUrl(url)).close();
    if (risposta.statusCode != 200) throw HttpException('HTTP ${risposta.statusCode}', uri: url);
    j = jsonDecode(await risposta.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }

  double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  int i(dynamic v) => (v as num?)?.toInt() ?? 0;

  final cur = j['current'] as Map<String, dynamic>;
  final h = j['hourly'] as Map<String, dynamic>;
  final g = j['daily'] as Map<String, dynamic>;
  final hTempi = h['time'] as List;
  final gTempi = g['time'] as List;

  return Previsioni(
    d(cur['temperature_2m']),
    i(cur['weather_code']),
    cur['is_day'] == 1,
    [
      for (var k = 0; k < gTempi.length; k++)
        Giorno(
          DateTime.parse(gTempi[k] as String),
          d((g['temperature_2m_min'] as List)[k]),
          d((g['temperature_2m_max'] as List)[k]),
          i((g['weather_code'] as List)[k]),
          i((g['precipitation_probability_max'] as List)[k]),
        ),
    ],
    [
      for (var k = 0; k < hTempi.length; k++)
        Ora(
          DateTime.parse(hTempi[k] as String),
          d((h['temperature_2m'] as List)[k]),
          i((h['weather_code'] as List)[k]),
          i((h['precipitation_probability'] as List)[k]),
          (h['is_day'] as List)[k] == 1,
        ),
    ],
    DateTime.now(),
  );
}

// Codici meteo WMO usati da Open-Meteo.
String descrizioneMeteo(int c) {
  if (c == 0) return 'Sereno';
  if (c == 1) return 'Poco nuvoloso';
  if (c == 2) return 'Parz. nuvoloso';
  if (c == 3) return 'Coperto';
  if (c == 45 || c == 48) return 'Nebbia';
  if (c >= 51 && c <= 57) return 'Pioggerella';
  if (c == 61 || c == 80) return 'Pioggia debole';
  if (c == 63 || c == 81) return 'Pioggia';
  if (c == 65 || c == 82) return 'Pioggia forte';
  if (c == 66 || c == 67) return 'Pioggia gelata';
  if (c >= 71 && c <= 77) return 'Neve';
  if (c == 85 || c == 86) return 'Rovesci di neve';
  if (c == 95) return 'Temporale';
  if (c == 96 || c == 99) return 'Temporale e grandine';
  return '';
}

IconData iconaMeteo(int c, [bool giorno = true]) {
  if (c <= 1) return giorno ? Icons.wb_sunny_outlined : Icons.nightlight_outlined;
  if (c == 2) return Icons.wb_cloudy_outlined;
  if (c == 3) return Icons.cloud_outlined;
  if (c == 45 || c == 48) return Icons.foggy;
  if (c >= 51 && c <= 67) return Icons.water_drop_outlined;
  if (c >= 80 && c <= 82) return Icons.water_drop_outlined;
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return Icons.ac_unit;
  if (c >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_outlined;
}

/// Riquadro piccolo nella schermata principale. Toccandolo si aprono le previsioni.
class RiquadroMeteo extends StatelessWidget {
  final Citta citta;
  final Previsioni? previsioni;
  const RiquadroMeteo({super.key, required this.citta, required this.previsioni});

  @override
  Widget build(BuildContext context) {
    final p = previsioni;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: p == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PaginaPrevisioni(citta: citta, previsioni: p),
              )),
      child: SizedBox(
        width: 236,
        child: PannelloHud(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(citta.nome.toUpperCase(), style: Hud.etichetta),
                  const Spacer(),
                  Text('${citta.lat.toStringAsFixed(1)}N ${citta.lon.toStringAsFixed(1)}E',
                      style: Hud.testo(10, colore: Hud.ciano.withValues(alpha: 0.45), spaziatura: 1)),
                ],
              ),
              const SizedBox(height: 4),
              if (p == null)
                Text('-- °', style: Hud.orbitron(30, colore: Colors.white38))
              else
                Row(
                  children: [
                    Icon(iconaMeteo(p.codice, p.giorno), size: 30, color: Hud.ciano),
                    const SizedBox(width: 10),
                    Text('${p.temperatura.round()}°', style: Hud.orbitron(32, peso: 500, altezza: 1.1)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(descrizioneMeteo(p.codice).toUpperCase(),
                              maxLines: 2,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: Hud.testo(13, peso: FontWeight.w600, colore: Colors.white, spaziatura: 1)),
                          Text('${p.oggi.minima.round()}° / ${p.oggi.massima.round()}°',
                              style: Hud.testo(13, colore: Colors.white60)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Previsioni di una città: in alto i 7 giorni, sotto le ore del giorno scelto.
class PaginaPrevisioni extends StatefulWidget {
  final Citta citta;
  final Previsioni previsioni;
  final int giornoIniziale;
  const PaginaPrevisioni(
      {super.key, required this.citta, required this.previsioni, this.giornoIniziale = 0});

  @override
  State<PaginaPrevisioni> createState() => _PaginaPrevisioniState();
}

class _PaginaPrevisioniState extends State<PaginaPrevisioni> {
  late int _scelto = widget.giornoIniziale;

  // "Jarvis avanti / indietro": giorno successivo o precedente.
  String? _comando(Azione a) {
    final ultimo = widget.previsioni.giorni.length - 1;
    if (a == Azione.avanti) {
      if (_scelto >= ultimo) return 'Signore, oltre non mi spingo. Le previsioni finiscono qui.';
      setState(() => _scelto++);
    } else if (a == Azione.indietro) {
      if (_scelto <= 0) return 'Signore, siamo già a oggi. Il passato, per fortuna, non lo prevedo.';
      setState(() => _scelto--);
    } else {
      return null;
    }
    return Jarvis.riassuntoMeteo(widget.citta, widget.previsioni, _scelto);
  }

  @override
  void initState() {
    super.initState();
    Jarvis.istanza.registra(_comando);
  }

  @override
  void dispose() {
    Jarvis.istanza.rimuovi(_comando);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.previsioni;
    final giorno = p.giorni[_scelto];
    var ore = p.oreDel(giorno.data);
    if (_scelto == 0) {
      final adesso = DateTime.now().subtract(const Duration(hours: 1));
      ore = [for (final o in ore) if (o.quando.isAfter(adesso)) o];
    }

    return PaginaACasaDaSola(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(widget.citta.nome,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w300)),
                    const SizedBox(width: 16),
                    Text(
                      _scelto == 0 ? 'Oggi, ora per ora' : '${nomeGiorno(giorno.data)}, ora per ora',
                      style: const TextStyle(fontSize: 16, color: Colors.white54),
                    ),
                    const Spacer(),
                    const BottoneChiudi(),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: p.giorni.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, k) => _CasellaGiorno(
                      giorno: p.giorni[k],
                      etichetta: k == 0 ? 'Oggi' : nomeGiornoCorto(p.giorni[k].data),
                      scelto: k == _scelto,
                      onTap: () => setState(() => _scelto = k),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ore.length,
                    separatorBuilder: (_, _) => const VerticalDivider(color: Colors.white12, width: 1),
                    itemBuilder: (_, k) => _CasellaOra(ora: ore[k]),
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

class _CasellaGiorno extends StatelessWidget {
  final Giorno giorno;
  final String etichetta;
  final bool scelto;
  final VoidCallback onTap;
  const _CasellaGiorno(
      {required this.giorno, required this.etichetta, required this.scelto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: scelto ? Colors.white : Colors.white24, width: scelto ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(etichetta,
                style: TextStyle(fontSize: 13, color: scelto ? Colors.white : Colors.white70)),
            Icon(iconaMeteo(giorno.codice), size: 22, color: Colors.white),
            Text('${giorno.minima.round()}° ${giorno.massima.round()}°',
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
            if (giorno.pioggia > 0)
              Text('${giorno.pioggia}%',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF7FB8FF))),
          ],
        ),
      ),
    );
  }
}

class _CasellaOra extends StatelessWidget {
  final Ora ora;
  const _CasellaOra({required this.ora});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text('${ora.quando.hour.toString().padLeft(2, '0')}:00',
              style: const TextStyle(fontSize: 13, color: Colors.white54)),
          Icon(iconaMeteo(ora.codice, ora.giorno), size: 26, color: Colors.white),
          Text('${ora.temperatura.round()}°',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w300)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.water_drop, size: 11,
                  color: ora.pioggia > 0 ? const Color(0xFF7FB8FF) : Colors.white24),
              const SizedBox(width: 2),
              Text('${ora.pioggia}%',
                  style: TextStyle(
                      fontSize: 12,
                      color: ora.pioggia > 0 ? const Color(0xFF7FB8FF) : Colors.white38)),
            ],
          ),
        ],
      ),
    );
  }
}
