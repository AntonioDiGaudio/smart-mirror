import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Minuti in cui lo schermo resta acceso dopo l'ultima presenza
/// (mano davanti al sensore, tocco, comando a Jarvis o accensione col tasto).
/// Passati questi, se il sensore di prossimità non vede nessuno, si spegne.
const minutiAcceso = 5;

/// Ponte verso il codice Android (MainActivity.kt).
class Sistema {
  static const _canale = MethodChannel('specchio/sistema');

  static Future<({int livello, bool inCarica})?> batteria() async {
    try {
      final s = await _canale.invokeMapMethod<String, dynamic>('batteria');
      if (s == null) return null;
      return (livello: s['livello'] as int, inCarica: s['inCarica'] as bool);
    } catch (_) {
      return null;
    }
  }

  /// CPU e RAM usate (%), disco libero (GB e %). CPU null se non leggibile.
  static Future<({double? cpu, double ram, double discoLiberoGb, double discoLiberoPerc})?> risorse() async {
    try {
      final r = await _canale.invokeMapMethod<String, dynamic>('risorse');
      if (r == null) return null;
      return (
        cpu: (r['cpu'] as num?)?.toDouble(),
        ram: (r['ram'] as num).toDouble(),
        discoLiberoGb: (r['discoLiberoGb'] as num).toDouble(),
        discoLiberoPerc: (r['discoLiberoPerc'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> cartellaMedia() => _canale.invokeMethod<String>('cartellaMedia');

  static Future<void> apriImpostazioni() => _canale.invokeMethod('impostazioni');

  static Future<void> _schermoSempreAcceso(bool acceso) =>
      _canale.invokeMethod('schermoAcceso', acceso);

  static Future<bool> _sensoreVicino() async =>
      await _canale.invokeMethod<bool>('sensoreVicino') ?? false;

  /// Spegne lo schermo. false se manca il permesso di amministratore
  /// (allora lo spegne Android col suo timeout).
  static Future<bool> spegniSchermo() async =>
      await _canale.invokeMethod<bool>('spegniSchermo') ?? false;

  static Future<void> _luminositaMinima(bool minima) =>
      _canale.invokeMethod('luminositaMinima', minima);

  static Future<void> configuraVoce(String grammaticaJson) =>
      _canale.invokeMethod('voceConfigura', grammaticaJson);

  static Future<void> parla(String testo) => _canale.invokeMethod('parla', testo);

  /// Smette di parlare. true se stava parlando.
  static Future<bool> zitto() async => await _canale.invokeMethod<bool>('zitto') ?? false;

  /// Volume da 0 a 10: assoluto o come variazione. Restituisce il nuovo livello.
  static Future<int> volume({int? livello, int? variazione}) async =>
      await _canale.invokeMethod<int>('volume', {'livello': livello, 'variazione': variazione}) ?? 0;

  /// true: la prossima frase viene capita per intero, non solo i comandi.
  static Future<void> ascoltoLibero(bool attivo) => _canale.invokeMethod('ascoltoLibero', attivo);

  static VoidCallback? _presenza;
  static void Function(String tipo, String? testo)? _voce;

  static void ascoltaPresenza(VoidCallback quandoPresente) {
    _presenza = quandoPresente;
    _installa();
  }

  static void ascoltaVoce(void Function(String tipo, String? testo) quandoParla) {
    _voce = quandoParla;
    _installa();
  }

  static void _installa() {
    _canale.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'presenza':
          _presenza?.call();
        case 'voce':
          final m = (call.arguments as Map).cast<String, dynamic>();
          _voce?.call(m['tipo'] as String, m['testo'] as String?);
      }
    });
  }
}

/// Decide quando lo schermo deve restare acceso.
/// Finché c'è presenza (o un video in riproduzione) lo schermo resta acceso.
/// Passati [minutiAcceso] senza presenza, se il sensore di prossimità non vede
/// nessuno, lo spegne; il servizio Android lo riaccende quando il sensore vede
/// qualcuno.
class Presenza {
  Presenza._();
  static final istanza = Presenza._();

  DateTime _fino = DateTime.now().add(const Duration(minutes: minutiAcceso));
  bool _videoInCorso = false;
  bool? _ultimoStato;
  bool _controllando = false;
  Timer? _controllo;

  /// Senza permesso di amministratore lo schermo non si può spegnere:
  /// allora diventa tutto nero alla luminosità minima, e dietro il vetro non
  /// si vede niente finché Android non lo spegne col suo timeout.
  final schermoNero = ValueNotifier(false);

  /// "Jarvis spegniti / chiudi": spegne subito. Glielo si chiede apposta,
  /// quindi non guarda il sensore di prossimità (che magari vede la mano).
  void spegniOra() {
    _fino = DateTime.now();
    _videoInCorso = false;
    _spegni();
  }

  void avvia() {
    Sistema.ascoltaPresenza(segnala);
    _controllo ??= Timer.periodic(const Duration(seconds: 5), (_) => _aggiorna());
    _aggiorna();
  }

  void segnala() {
    _fino = DateTime.now().add(const Duration(minutes: minutiAcceso));
    _aggiorna();
  }

  set videoInCorso(bool v) {
    _videoInCorso = v;
    segnala();
  }

  Future<void> _aggiorna() async {
    final acceso = _videoInCorso || DateTime.now().isBefore(_fino);
    if (acceso) {
      if (_ultimoStato != true) {
        _ultimoStato = true;
        Sistema._schermoSempreAcceso(true);
      }
      if (schermoNero.value) {
        schermoNero.value = false;
        Sistema._luminositaMinima(false);
      }
      return;
    }
    if (_ultimoStato == false || _controllando) return;
    _controllando = true;
    try {
      // Tempo scaduto: se il sensore vede ancora qualcuno, si resta accesi.
      if (await Sistema._sensoreVicino()) {
        _fino = DateTime.now().add(const Duration(minutes: 1));
        return;
      }
      await _spegni();
    } finally {
      _controllando = false;
    }
  }

  Future<void> _spegni() async {
    _ultimoStato = false;
    if (!await Sistema.spegniSchermo()) {
      schermoNero.value = true;
      Sistema._luminositaMinima(true);
    }
  }
}
