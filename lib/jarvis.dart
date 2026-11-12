import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'comuni.dart';
import 'media.dart';
import 'meteo.dart';
import 'notizie.dart';
import 'sistema.dart';

/// Comandi che una pagina aperta (foto, video, previsioni) può gestire.
enum Azione { avanti, indietro, pausa, riprendi }

/// Restituisce cosa dire (stringa vuota = gestito in silenzio) o null se la
/// pagina non sa fare quell'azione.
typedef GestoreAzione = String? Function(Azione azione);

enum StatoVoce { spento, caricamento, ascolto, sveglio, libero, problema }

/// Dopo un "Jarvis" da solo, per questi secondi basta dire il comando.
const _attesaComando = Duration(seconds: 6);

// Solo queste parole vengono riconosciute: tutto il resto diventa [unk].
// Il modello italiano le conosce tutte (verificato); i giorni sono senza accento.
const _parole = [
  'jarvis',
  'meteo', 'previsioni', 'tempo',
  'oggi', 'domani', 'dopodomani',
  'lunedi', 'martedi', 'mercoledi', 'giovedi', 'venerdi', 'sabato', 'domenica',
  'terni', 'palermo',
  'foto', 'fotografie', 'video',
  'avanti', 'prossima', 'prossimo', 'successiva', 'indietro', 'precedente',
  'pausa', 'ferma', 'stop', 'riprendi', 'play',
  'chiudi', 'esci', 'torna', 'specchio',
  'ore', 'grazie', 'settimana', 'spegni',
  'che', 'cosa', 'sai', 'fare', 'puoi', 'aiuto', 'comandi',
  'cerca', 'cercare', 'notizie', 'notizia', 'news', 'ultime', 'internet',
  'volume', 'alza', 'abbassa', 'massimo', 'minimo', 'muto',
  'zero', 'uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette', 'otto', 'nove', 'dieci',
  'basta', 'zitto', 'zitta', 'silenzio',
  '[unk]',
];

const _numeri = ['zero', 'uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette', 'otto', 'nove', 'dieci'];

/// Dopo "Jarvis cerca", per questo tempo ascolta liberamente l'argomento.
const _attesaArgomento = Duration(seconds: 12);

const _giorniSenzaAccento = ['lunedi', 'martedi', 'mercoledi', 'giovedi', 'venerdi', 'sabato', 'domenica'];

class Jarvis {
  Jarvis._();
  static final istanza = Jarvis._();

  final navigatore = GlobalKey<NavigatorState>();
  final stato = ValueNotifier(StatoVoce.spento);

  /// Cresce a ogni comando: le pagine lo usano per non chiudersi da sole.
  final attivita = ValueNotifier(0);

  /// Città e meteo attuali, forniti dalla schermata principale.
  List<Citta> citta = const [];
  Map<String, Previsioni> Function() meteo = () => const {};

  final List<GestoreAzione> _gestori = [];
  DateTime _svegloFino = DateTime(2000);

  void avvia() {
    Sistema.ascoltaVoce(_daAndroid);
    Sistema.configuraVoce(jsonEncode(_grammatica()));
  }

  /// Le frasi intere dei comandi, con e senza "jarvis" davanti. Dando frasi
  /// (non solo parole) il riconoscitore impara quali parole vanno insieme
  /// ("meteo" dopo "jarvis", "palermo" dopo "meteo") e sbaglia molto meno.
  /// Le parole sciolte restano, così capisce anche combinazioni non elencate.
  static List<String> _grammatica() {
    const meteo = ['meteo', 'previsioni', 'tempo'];
    const citta = ['', 'terni', 'palermo'];
    const quando = ['', 'oggi', 'domani', 'dopodomani', 'settimana', ..._giorniSenzaAccento];
    final comandi = <String>{
      for (final m in meteo)
        for (final c in citta)
          for (final q in quando) ...[
            [m, c, q].where((p) => p.isNotEmpty).join(' '),
            if (c.isNotEmpty && q.isNotEmpty) '$m $q $c',
          ],
      'foto', 'fotografie', 'video', 'avanti', 'indietro', 'prossima', 'precedente', 'successiva',
      'pausa', 'ferma', 'stop', 'riprendi', 'play', 'chiudi', 'esci', 'torna', 'specchio',
      'che ore sono', 'ore', 'grazie', 'spegni', 'che sai fare', 'cosa sai fare', 'cosa puoi fare',
      'aiuto', 'comandi', 'cerca', 'cerca notizie', 'notizie', 'ultime notizie', 'news', 'internet',
      'alza volume', 'abbassa volume', 'volume massimo', 'volume minimo', 'muto',
      for (final n in _numeri) 'volume $n',
      'basta', 'zitto', 'zitta', 'silenzio',
    };
    return {
      for (final c in comandi) ...[c, 'jarvis $c'],
      'jarvis',
      ..._parole,
    }.toList();
  }

  void registra(GestoreAzione g) => _gestori.add(g);
  void rimuovi(GestoreAzione g) => _gestori.remove(g);

  void _daAndroid(String tipo, String? testo) {
    switch (tipo) {
      case 'stato':
        stato.value = switch (testo) {
          'ascolto' => StatoVoce.ascolto,
          'libero' => StatoVoce.libero,
          'caricamento' => StatoVoce.caricamento,
          'spento' => StatoVoce.spento,
          _ => StatoVoce.problema,
        };
      case 'sento':
        _sveglia(const Duration(seconds: 3));
        Presenza.istanza.segnala();
      case 'frase':
        _frase(testo ?? '');
      case 'frase-libera':
        _argomentoDetto(testo ?? '');
      case 'parziale':
        // Sta ancora parlando dopo "Jarvis": il "mi dica" aspetta.
        if (_rispostaAlNome?.isActive ?? false) _programmaMiDica();
      case 'parlando':
        _staParlando = testo == 'si';
    }
  }

  // ------------------------------------------------------------ Ricerca notizie

  bool _attendoArgomento = false;
  Timer? _scadenzaArgomento;

  void _chiediArgomento() {
    _attendoArgomento = true;
    Sistema.ascoltoLibero(true);
    _scadenzaArgomento?.cancel();
    _scadenzaArgomento = Timer(_attesaArgomento, () {
      if (!_attendoArgomento) return;
      _attendoArgomento = false;
      Sistema.ascoltoLibero(false);
    });
  }

  void _argomentoDetto(String frase) {
    if (!_attendoArgomento) return;
    _attendoArgomento = false;
    _scadenzaArgomento?.cancel();
    // Ha cambiato idea e ha dato un altro comando ("Jarvis chiudi").
    if (frase.split(' ').contains('jarvis')) {
      _frase(frase);
      return;
    }
    Presenza.istanza.segnala();
    attivita.value++;
    final argomento = pulisciArgomento(frase);
    if (argomento.isEmpty) {
      dici('Signore, temo di non aver colto cosa cercare. Riproviamo, con calma.');
    } else {
      _apriNotizie(argomento);
    }
  }

  Future<void> _apriNotizie(String? argomento) async {
    final List<Notizia> trovate;
    try {
      trovate = await cercaNotizie(argomento);
    } catch (_) {
      dici('Signore, internet pare si sia preso una pausa per il tè. Non riesco a collegarmi.');
      return;
    }
    if (trovate.isEmpty) {
      dici('Signore, su $argomento il mondo tace. Il che, forse, è già una buona notizia.');
      return;
    }
    final nav = navigatore.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(
      builder: (_) => PaginaNotizie(argomento: argomento, notizie: trovate),
    ));
    final su = argomento == null
        ? 'Signore, ecco le ultime dal mondo, che come sempre non si è annoiato.'
        : 'Signore, ecco cosa si dice su $argomento.';
    dici('$su ${trovate.first.titolo}. '
        '${trovate.length > 1 ? 'Dica avanti per la prossima, se ha lo stomaco.' : ''}');
  }

  bool get _sveglio => DateTime.now().isBefore(_svegloFino);

  void _frase(String testo) {
    final grezze = testo.split(' ').where((p) => p.isNotEmpty).toList();
    final i = grezze.lastIndexOf('jarvis');
    final List<String> dopo;
    if (i >= 0) {
      dopo = grezze.sublist(i + 1);
    } else if (_sveglio && grezze.isNotEmpty) {
      // Dopo "Jarvis" da solo basta il comando. La sua stessa voce non viene
      // più scambiata per comandi: l'antieco del vivavoce la toglie.
      dopo = grezze;
    } else {
      // "avanti" senza "Jarvis": non succede niente.
      return;
    }
    // [unk] = parole fuori dai comandi (es. "notizie sulla Juventus").
    _sconosciute = dopo.contains('[unk]');
    final comando = dopo.where((p) => p != '[unk]').toList();
    // Dopo "Sì, signore?" il microfono resta aperto: rumori o la sua stessa
    // voce senza parole di comando non devono contare.
    if (i < 0 && comando.isEmpty) return;
    attivita.value++;
    Presenza.istanza.segnala();

    // "Jarvis stop / basta / zitto": smette di parlare (e se non parlava,
    // "stop" mette in pausa il video).
    if (comando.any(_zittiti.contains)) {
      _svegloFino = DateTime(2000);
      stato.value = StatoVoce.ascolto;
      _zitto(anchePausa: comando.contains('stop'));
      return;
    }
    // "Jarvis ..." mentre parla: si interrompe e ascolta la nuova richiesta.
    if (_staParlando) Sistema.zitto();

    if (comando.isEmpty) {
      _svegloFino = DateTime.now().add(_attesaComando);
      _sveglia(_attesaComando);
      // Non risponde subito: magari sta per continuare la frase.
      // Se il comando arriva entro un attimo, "mi dica" non serve.
      _programmaMiDica();
      return;
    }
    _rispostaAlNome?.cancel();
    _svegloFino = DateTime(2000);
    _riaddormenta?.cancel();
    stato.value = StatoVoce.ascolto;
    final r = _esegui(comando, conNome: i >= 0);
    if (r.isNotEmpty) dici(r);
  }

  Timer? _rispostaAlNome;

  /// "Signore, mi dica" solo dopo 2 secondi di silenzio dopo "Jarvis".
  void _programmaMiDica() {
    _rispostaAlNome?.cancel();
    _rispostaAlNome = Timer(const Duration(seconds: 2), () {
      if (_sveglio) {
        dici(_uno(['Signore, mi dica.', 'Signore, sono tutta orecchie.', 'Signore, al suo servizio.']));
        // L'attesa del comando riparte da qui (lei parla un paio di secondi).
        _svegloFino = DateTime.now().add(const Duration(seconds: 8));
        _sveglia(const Duration(seconds: 8));
      }
    });
  }


  static const _zittiti = {'stop', 'basta', 'zitto', 'zitta', 'silenzio'};

  Future<void> _zitto({required bool anchePausa}) async {
    final stavaParlando = await Sistema.zitto();
    if (stavaParlando || !anchePausa) return;
    for (final g in _gestori.reversed) {
      if (g(Azione.pausa) != null) return;
    }
  }

  /// "Jarvis volume sette", "Jarvis alza il volume", "Jarvis volume al massimo".
  Future<void> _volume(List<String> c) async {
    int? livello;
    int? variazione;
    for (var n = 0; n < _numeri.length; n++) {
      if (c.contains(_numeri[n])) livello = n;
    }
    if (c.contains('massimo')) livello = 10;
    if (c.contains('minimo')) livello = 1;
    if (c.contains('muto')) livello = 0;
    if (livello == null) {
      if (c.contains('alza')) variazione = 2;
      if (c.contains('abbassa')) variazione = -2;
    }
    if (livello == null && variazione == null) {
      dici('Signore, a quanto? Da zero a dieci, la scelta è sua.');
      return;
    }
    final nuovo = await Sistema.volume(livello: livello, variazione: variazione);
    if (nuovo == 0) return;
    dici(nuovo == 10
        ? 'Signore, volume al massimo. I vicini ringraziano.'
        : nuovo <= 2
            ? 'Signore, volume a $nuovo. Sussurrerò.'
            : 'Signore, volume a $nuovo.');
  }

  String _esegui(List<String> c, {required bool conNome}) {
    bool ha(List<String> parole) => parole.any(c.contains);
    final nav = navigatore.currentState;
    if (nav == null) return '';

    if (ha(['spegni'])) {
      // Spegnere è l'unico comando "pesante": solo con "Jarvis spegni" detto
      // chiaro (nome nella stessa frase, al massimo una parola in più),
      // mai da rumori o frasi lunghe capite a metà.
      if (!conNome || c.length > 2) return '';
      nav.popUntil((r) => r.isFirst);
      // Prima finisce di parlare, poi spegne.
      Future.delayed(const Duration(milliseconds: 2500), Presenza.istanza.spegniOra);
      return 'Signore, buonanotte. Cerchi di non sentire troppo la mia mancanza.';
    }

    if (ha(['volume', 'alza', 'abbassa', 'muto'])) {
      _volume(c);
      return '';
    }

    if (ha(['chiudi', 'esci', 'torna', 'specchio'])) {
      nav.popUntil((r) => r.isFirst);
      return _uno(['Signore, come desidera.', 'Signore, torno a fare lo specchio. Ruolo impegnativo.']);
    }
    if (ha(['sai', 'aiuto', 'comandi']) || (ha(['cosa']) && ha(['fare', 'puoi']))) {
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => const PaginaAiuto()));
      return 'Signore, modestamente, parecchie cose. Il meteo di Terni e Palermo, per oggi, '
          'per un giorno o per tutta la settimana. Le sue foto e i video. L\'ora esatta. '
          'Le notizie da internet, e il volume. Mi chiami per nome prima di ogni richiesta, '
          'e se divento prolissa mi dica stop. Non mi offenderò. Molto.';
    }
    if (ha(['cerca', 'cercare', 'internet']) ||
        (ha(['notizie', 'notizia', 'news', 'ultime']) && _sconosciute)) {
      _chiediArgomento();
      return 'Signore, cosa devo cercare?';
    }
    if (ha(['notizie', 'notizia', 'news', 'ultime'])) {
      _apriNotizie(null);
      return '';
    }
    if (ha(['meteo', 'previsioni', 'tempo'])) return _meteo(c, nav);
    if (ha(['foto', 'fotografie'])) {
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => const PaginaFoto()));
      return _uno(['Signore, ecco le sue foto.', 'Signore, le sue foto. Ricordi splendidi, immagino.']);
    }
    if (ha(['video'])) {
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => const PaginaVideo()));
      return 'Signore, si accomodi. Lo spettacolo comincia.';
    }
    final azione = ha(['avanti', 'prossima', 'prossimo', 'successiva'])
        ? Azione.avanti
        : ha(['indietro', 'precedente'])
            ? Azione.indietro
            : ha(['pausa', 'ferma', 'stop'])
                ? Azione.pausa
                : ha(['riprendi', 'play'])
                    ? Azione.riprendi
                    : null;
    if (azione != null) {
      for (final g in _gestori.reversed) {
        final r = g(azione);
        if (r != null) return r;
      }
      return 'Signore, temo che qui non sia possibile.';
    }
    if (ha(['ore'])) {
      final o = DateTime.now();
      return o.minute == 0
          ? 'Signore, sono le ${o.hour} in punto. Puntuale come un treno inglese.'
          : 'Signore, sono le ${o.hour} e ${o.minute}.';
    }
    if (ha(['grazie'])) return _uno(['Signore, è un piacere.', 'Signore, dovere. Lo aggiungo al conto.']);
    return _uno(['Signore, temo di non aver capito.', 'Signore, perdoni, può ripetere?']);
  }

  String _meteo(List<String> c, NavigatorState nav) {
    final scelta = citta.firstWhere((x) => c.contains(x.nome.toLowerCase()),
        orElse: () => citta.first);
    final p = meteo()[scelta.nome];
    if (p == null) return 'Signore, il meteo di ${scelta.nome} non è ancora arrivato. Pazienza britannica.';

    if (c.contains('settimana')) {
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(
        builder: (_) => PaginaPrevisioni(citta: scelta, previsioni: p),
      ));
      return riassuntoSettimana(scelta, p);
    }

    var giorno = 0;
    if (c.contains('domani')) giorno = 1;
    if (c.contains('dopodomani')) giorno = 2;
    for (var k = 0; k < _giorniSenzaAccento.length; k++) {
      if (c.contains(_giorniSenzaAccento[k])) {
        final idx = p.giorni.indexWhere((g) => g.data.weekday == k + 1);
        if (idx >= 0) giorno = idx;
      }
    }
    giorno = giorno.clamp(0, p.giorni.length - 1);

    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(
      builder: (_) => PaginaPrevisioni(citta: scelta, previsioni: p, giornoIniziale: giorno),
    ));
    return riassuntoMeteo(scelta, p, giorno);
  }

  /// Descrizione del cielo da leggere ad alta voce (senza abbreviazioni).
  static String _aVoce(int codice) =>
      descrizioneMeteo(codice).toLowerCase().replaceAll('parz.', 'parzialmente');

  /// "Jarvis meteo settimana": tutti i giorni, uno per frase.
  static String riassuntoSettimana(Citta c, Previsioni p) {
    final frasi = <String>['Signore, ecco la settimana a ${c.nome}.'];
    for (var k = 0; k < p.giorni.length; k++) {
      final g = p.giorni[k];
      final nome = giorniSettimana[g.data.weekday - 1];
      final quando = k == 0
          ? 'Oggi'
          : k == 1
              ? 'Domani'
              : '${nome[0].toUpperCase()}${nome.substring(1)}';
      final cielo = _aVoce(g.codice);
      // La pioggia si dice solo se il cielo non la dice già.
      final pioggia = g.codice < 51 && g.pioggia >= 50 ? ', possibile pioggia' : '';
      frasi.add('$quando $cielo, tra ${g.minima.round()} e ${g.massima.round()} gradi$pioggia.');
    }
    // Una chiusa ironica se la settimana è quasi tutta bagnata.
    final bagnati = p.giorni.where((g) => g.codice >= 51 || g.pioggia >= 60).length;
    if (bagnati >= 4) frasi.add('Signore, in sintesi: ombrello. Molto british.');
    return frasi.join(' ');
  }

  static String riassuntoMeteo(Citta c, Previsioni p, int giorno) {
    final g = p.giorni[giorno];
    final cielo = _aVoce(g.codice);
    if (giorno == 0) {
      return 'Signore, a ${c.nome} ora ci sono ${p.temperatura.round()} gradi, '
          '${_aVoce(p.codice)}. '
          'Oggi minima ${g.minima.round()}, massima ${g.massima.round()}.';
    }
    final quando = giorno == 1 ? 'domani' : nomeGiorno(g.data);
    final pioggia = g.pioggia >= 30 ? ', pioggia al ${g.pioggia} per cento' : '';
    return 'Signore, $quando a ${c.nome} $cielo, minima ${g.minima.round()}, '
        'massima ${g.massima.round()}$pioggia.';
  }

  /// Jarvis parla e basta: niente testo a schermo.
  void dici(String testo) => Sistema.parla(testo);

  static final _caso = Random();

  /// Una battuta a caso tra quelle date: così non risponde sempre uguale.
  static String _uno(List<String> battute) => battute[_caso.nextInt(battute.length)];

  bool _sconosciute = false;
  bool _staParlando = false;

  Timer? _riaddormenta;

  /// Microfono acceso (azzurro) per un po', poi torna in semplice ascolto.
  void _sveglia(Duration per) {
    stato.value = StatoVoce.sveglio;
    _riaddormenta?.cancel();
    _riaddormenta = Timer(per, () {
      if (stato.value == StatoVoce.sveglio) stato.value = StatoVoce.ascolto;
    });
  }
}

/// Sovrapposto a tutte le pagine: solo un piccolo microfono che dice se
/// Jarvis sta ascoltando (grigio) o ha sentito il suo nome (azzurro).
class SovrapposizioneJarvis extends StatelessWidget {
  const SovrapposizioneJarvis({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 22, bottom: 18),
          child: ValueListenableBuilder(
            valueListenable: Jarvis.istanza.stato,
            builder: (_, s, _) => _Microfono(stato: s),
          ),
        ),
      ),
    );
  }
}

class _Microfono extends StatelessWidget {
  final StatoVoce stato;
  const _Microfono({required this.stato});

  @override
  Widget build(BuildContext context) {
    const azzurro = Color(0xFF4FC3F7);
    final (icona, colore, testo) = switch (stato) {
      StatoVoce.spento => (Icons.mic_off_outlined, Colors.white12, null),
      StatoVoce.caricamento => (Icons.mic_none_outlined, Colors.white24, null),
      StatoVoce.ascolto => (Icons.mic_none_outlined, Colors.white24, null),
      StatoVoce.sveglio => (Icons.mic, azzurro, null),
      StatoVoce.libero => (Icons.mic, azzurro, null),
      StatoVoce.problema => (Icons.mic_off_outlined, const Color(0xFFFF6B5B), null),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (testo != null) ...[
          Text(testo, style: TextStyle(fontSize: 12, color: colore)),
          const SizedBox(width: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: stato == StatoVoce.sveglio || stato == StatoVoce.libero
                ? [BoxShadow(color: azzurro.withValues(alpha: 0.5), blurRadius: 14)]
                : null,
          ),
          child: Icon(icona, size: 22, color: colore),
        ),
      ],
    );
  }
}

/// "Jarvis, che sai fare?": l'elenco dei comandi.
class PaginaAiuto extends StatelessWidget {
  const PaginaAiuto({super.key});

  static const _comandi = [
    ('Jarvis meteo', 'previsioni di Terni, lette a voce'),
    ('Jarvis meteo Palermo', 'previsioni di Palermo'),
    ('Jarvis meteo domani', 'oggi, domani, dopodomani, lunedì…'),
    ('Jarvis meteo settimana', 'le leggo tutti i 7 giorni'),
    ('Jarvis spegni', 'spengo lo schermo'),
    ('Jarvis volume sette', 'da zero a dieci, o alza / abbassa'),
    ('Jarvis stop', 'smetto di parlare'),
    ('Jarvis foto', 'apre le sue foto'),
    ('Jarvis video', 'fa partire il video'),
    ('Jarvis avanti / indietro', 'foto, giorno, notizia o 10 s di video'),
    ('Jarvis pausa / riprendi', 'ferma o fa ripartire il video'),
    ('Jarvis notizie', 'le ultime notizie in Italia'),
    ('Jarvis cerca', 'poi dica l\'argomento: cerco le notizie'),
    ('Jarvis che ore sono', 'le dico l\'ora'),
    ('Jarvis chiudi', 'torna allo specchio'),
    ('Jarvis', 'da solo: poi ha 6 secondi per il comando'),
  ];

  @override
  Widget build(BuildContext context) {
    return PaginaACasaDaSola(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 12, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('Signore, ecco cosa so fare',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300)),
                    Spacer(),
                    BottoneChiudi(),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 24,
                    children: [
                      for (final (frase, cosa) in _comandi)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('«$frase»',
                                style: const TextStyle(fontSize: 17, color: Color(0xFF4FC3F7))),
                            Text(cosa, style: const TextStyle(fontSize: 14, color: Colors.white60)),
                          ],
                        ),
                    ],
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
