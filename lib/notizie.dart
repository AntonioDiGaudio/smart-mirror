import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'comuni.dart';
import 'jarvis.dart';

class Notizia {
  final String titolo, fonte;
  final DateTime? quando;
  Notizia(this.titolo, this.fonte, this.quando);
}

/// Notizie da Google News (feed RSS pubblico, in italiano, senza chiavi).
/// Senza argomento: le principali di oggi in Italia.
Future<List<Notizia>> cercaNotizie(String? argomento) async {
  final parametri = {'hl': 'it', 'gl': 'IT', 'ceid': 'IT:it'};
  final url = argomento == null || argomento.isEmpty
      ? Uri.https('news.google.com', '/rss', parametri)
      : Uri.https('news.google.com', '/rss/search', {'q': '$argomento when:7d', ...parametri});

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final String corpo;
  try {
    final risposta = await (await client.getUrl(url)).close();
    if (risposta.statusCode != 200) throw HttpException('HTTP ${risposta.statusCode}', uri: url);
    corpo = await risposta.transform(utf8.decoder).join();
  } finally {
    client.close();
  }

  final notizie = <Notizia>[];
  for (final item in XmlDocument.parse(corpo).findAllElements('item').take(15)) {
    final fonte = item.getElement('source')?.innerText.trim() ?? '';
    var titolo = item.getElement('title')?.innerText.trim() ?? '';
    // Google aggiunge " - Fonte" in fondo al titolo.
    if (fonte.isNotEmpty && titolo.endsWith(' - $fonte')) {
      titolo = titolo.substring(0, titolo.length - fonte.length - 3);
    }
    DateTime? quando;
    try {
      quando = HttpDate.parse(item.getElement('pubDate')?.innerText.trim() ?? '').toLocal();
    } catch (_) {}
    if (titolo.isNotEmpty) notizie.add(Notizia(titolo, fonte, quando));
  }
  // Prima le più recenti.
  notizie.sort((a, b) => (b.quando ?? DateTime(2000)).compareTo(a.quando ?? DateTime(2000)));
  return notizie;
}

/// Toglie dalla frase detta le parole di contorno: "notizie sulla juventus" -> "juventus".
String pulisciArgomento(String frase) {
  const contorno = {
    'cerca', 'cercare', 'cercami', 'trova', 'trovami', 'notizie', 'notizia', 'news', 'ultime',
    'le', 'la', 'il', 'lo', 'gli', 'i', 'un', 'una', 'su', 'sul', 'sulla', 'sullo', 'sui', 'sugli',
    'sulle', 'di', 'del', 'della', 'dello', 'dei', 'degli', 'delle', 'internet', 'per', 'favore',
    // Riempitivi di chi parla: "sì, è sulla Juventus", "vorrei le notizie su…".
    'si', 'sì', 'è', 'e', 'ehm', 'allora', 'ok', 'okay', 'vorrei', 'voglio', 'dimmi', 'mi',
    'cosa', 'che', 'ci', 'sono', 'qualcosa', 'tutto', 'tutte', 'parla', 'parlami',
  };
  final parole = frase.toLowerCase().split(' ').where((p) => p.isNotEmpty).toList();
  while (parole.isNotEmpty && contorno.contains(parole.first)) {
    parole.removeAt(0);
  }
  while (parole.isNotEmpty && {'per', 'favore', 'grazie'}.contains(parole.last)) {
    parole.removeLast();
  }
  final testo = parole.join(' ');
  return testo.isEmpty ? testo : '${testo[0].toUpperCase()}${testo.substring(1)}';
}

String fa(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min fa';
  if (diff.inHours < 24) return '${diff.inHours} ${diff.inHours == 1 ? 'ora' : 'ore'} fa';
  return '${diff.inDays} ${diff.inDays == 1 ? 'giorno' : 'giorni'} fa';
}

class PaginaNotizie extends StatefulWidget {
  final String? argomento;
  final List<Notizia> notizie;
  const PaginaNotizie({super.key, required this.argomento, required this.notizie});

  @override
  State<PaginaNotizie> createState() => _PaginaNotizieState();
}

class _PaginaNotizieState extends State<PaginaNotizie> {
  int _attuale = 0;
  late final _chiavi = List.generate(widget.notizie.length, (_) => GlobalKey());

  // "Jarvis avanti / indietro": legge la notizia successiva o precedente.
  String? _comando(Azione a) {
    final n = widget.notizie.length;
    if (a == Azione.avanti) {
      if (_attuale >= n - 1) return 'Signore, non ci sono altre notizie. Il mondo, per oggi, ha finito.';
      _vai(_attuale + 1);
    } else if (a == Azione.indietro) {
      if (_attuale <= 0) return 'Signore, questa è la prima notizia.';
      _vai(_attuale - 1);
    } else {
      return null;
    }
    return widget.notizie[_attuale].titolo;
  }

  void _vai(int i) {
    setState(() => _attuale = i);
    final ctx = _chiavi[i].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.3, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
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
    final titolo = widget.argomento == null ? 'Ultime notizie' : 'Notizie: ${widget.argomento}';
    return PaginaACasaDaSola(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public, color: Colors.white54, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(titolo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300)),
                    ),
                    const BottoneChiudi(),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 140),
                    itemCount: widget.notizie.length,
                    itemBuilder: (_, i) {
                      final n = widget.notizie[i];
                      final scelta = i == _attuale;
                      return GestureDetector(
                        key: _chiavi[i],
                        onTap: () => _vai(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                  color: scelta ? const Color(0xFF4FC3F7) : Colors.white12, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.titolo,
                                  style: TextStyle(
                                      fontSize: 19,
                                      color: scelta ? Colors.white : Colors.white60,
                                      height: 1.25)),
                              const SizedBox(height: 4),
                              Text([n.fonte, fa(n.quando)].where((s) => s.isNotEmpty).join('  ·  '),
                                  style: const TextStyle(fontSize: 13, color: Colors.white38)),
                            ],
                          ),
                        ),
                      );
                    },
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
