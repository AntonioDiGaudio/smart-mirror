import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'comuni.dart';
import 'jarvis.dart';
import 'sistema.dart';

const estensioniFoto = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
const estensioniVideo = {'.mp4', '.m4v', '.webm', '.mkv', '.3gp', '.mov'};

/// I media stanno sul telefono in Android/data/com.antonio.vetro_bidirezionale/files/media
/// (foto/ e video/). Si copiano dal PC con carica-media.ps1.
Future<List<File>> fileMedia(String sottocartella, Set<String> estensioni) async {
  final base = await Sistema.cartellaMedia();
  if (base == null) return [];
  final cartella = Directory('$base/$sottocartella');
  if (!await cartella.exists()) return [];
  final file = <File>[];
  await for (final e in cartella.list()) {
    final nome = e.path.toLowerCase();
    if (e is File && estensioni.any(nome.endsWith)) file.add(e);
  }
  file.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return file;
}

String nomeFile(File f) {
  final n = f.uri.pathSegments.last;
  final punto = n.lastIndexOf('.');
  return punto > 0 ? n.substring(0, punto) : n;
}

class _Vuoto extends StatelessWidget {
  final String testo;
  const _Vuoto(this.testo);

  @override
  Widget build(BuildContext context) => Center(
        child: Text(testo,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.white54)),
      );
}

// ---------------------------------------------------------------- Foto

class PaginaFoto extends StatefulWidget {
  const PaginaFoto({super.key});

  @override
  State<PaginaFoto> createState() => _PaginaFotoState();
}

class _PaginaFotoState extends State<PaginaFoto> {
  final _pagine = PageController();
  List<File>? _foto;
  int _attuale = 0;

  // "Jarvis avanti / indietro": foto successiva o precedente.
  String? _comando(Azione a) {
    final n = _foto?.length ?? 0;
    if (a != Azione.avanti && a != Azione.indietro) return null;
    if (n == 0) return 'Signore, non ci sono foto. Un album sorprendentemente minimalista.';
    if (a == Azione.avanti) {
      if (_attuale >= n - 1) return 'Signore, era l\'ultima foto.';
      _vai(1);
    } else {
      if (_attuale <= 0) return 'Signore, questa è la prima foto.';
      _vai(-1);
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    Jarvis.istanza.registra(_comando);
    fileMedia('foto', estensioniFoto).then((f) {
      if (!mounted) return;
      setState(() => _foto = f);
      if (f.isEmpty) Jarvis.istanza.dici('Signore, non ci sono foto. Un album sorprendentemente minimalista.');
    });
  }

  @override
  void dispose() {
    Jarvis.istanza.rimuovi(_comando);
    _pagine.dispose();
    super.dispose();
  }

  void _vai(int delta) => _pagine.animateToPage(_attuale + delta,
      duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final foto = _foto;
    final schermo = MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return PaginaACasaDaSola(
      child: Scaffold(
        body: Stack(
          children: [
            if (foto == null)
              const SizedBox.shrink()
            else if (foto.isEmpty)
              const _Vuoto('Nessuna foto.\nMettile in media/foto sul PC e lancia carica-media.ps1')
            else
              PageView.builder(
                controller: _pagine,
                itemCount: foto.length,
                onPageChanged: (i) => setState(() => _attuale = i),
                itemBuilder: (_, i) => Image(
                  // Ridotta alla risoluzione dello schermo per non finire la memoria.
                  image: ResizeImage(FileImage(foto[i]),
                      width: schermo.width.round(),
                      height: schermo.height.round(),
                      policy: ResizeImagePolicy.fit),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, _, _) => const _Vuoto('Foto non leggibile'),
                ),
              ),
            if (foto != null && foto.length > 1) ...[
              if (_attuale > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                      onPressed: () => _vai(-1),
                      icon: const Icon(Icons.chevron_left, size: 44, color: Colors.white54)),
                ),
              if (_attuale < foto.length - 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                      onPressed: () => _vai(1),
                      icon: const Icon(Icons.chevron_right, size: 44, color: Colors.white54)),
                ),
              Positioned(
                left: 24,
                bottom: 14,
                child: Text('${_attuale + 1} / ${foto.length}',
                    style: const TextStyle(fontSize: 15, color: Colors.white54)),
              ),
            ],
            const Positioned(top: 8, right: 8, child: BottoneChiudi()),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Video

/// Con un solo video parte subito, con più video mostra prima l'elenco.
class PaginaVideo extends StatefulWidget {
  const PaginaVideo({super.key});

  @override
  State<PaginaVideo> createState() => _PaginaVideoState();
}

class _PaginaVideoState extends State<PaginaVideo> {
  List<File>? _video;

  @override
  void initState() {
    super.initState();
    fileMedia('video', estensioniVideo).then((v) {
      if (mounted) setState(() => _video = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    if (video != null && video.length == 1) return LettoreVideo(file: video.first);
    return PaginaACasaDaSola(
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              if (video != null && video.isEmpty)
                const _Vuoto('Nessun video.\nMettili in media/video sul PC e lancia carica-media.ps1')
              else if (video != null)
                ListView(
                  padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                  children: [
                    for (final v in video)
                      ListTile(
                        leading: const Icon(Icons.play_circle_outline, size: 34, color: Colors.white),
                        title: Text(nomeFile(v), style: const TextStyle(fontSize: 18)),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => LettoreVideo(file: v))),
                      ),
                  ],
                ),
              const Positioned(top: 0, right: 8, child: BottoneChiudi()),
            ],
          ),
        ),
      ),
    );
  }
}

class LettoreVideo extends StatefulWidget {
  final File file;
  const LettoreVideo({super.key, required this.file});

  @override
  State<LettoreVideo> createState() => _LettoreVideoState();
}

class _LettoreVideoState extends State<LettoreVideo> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  bool _comandi = true;
  bool _inRiproduzione = false;
  bool _finito = false;
  String? _errore;
  Timer? _nascondi;

  // "Jarvis pausa / riprendi / avanti / indietro" (avanti e indietro: 10 secondi).
  String? _comando(Azione a) {
    if (!_c.value.isInitialized) return null;
    switch (a) {
      case Azione.pausa:
        _c.pause();
        _mostraComandi();
        return 'Signore, in pausa.';
      case Azione.riprendi:
        _c.play();
        return '';
      case Azione.avanti:
        _c.seekTo(_c.value.position + const Duration(seconds: 10));
        return '';
      case Azione.indietro:
        final p = _c.value.position - const Duration(seconds: 10);
        _c.seekTo(p.isNegative ? Duration.zero : p);
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    Jarvis.istanza.registra(_comando);
    _c.addListener(_cambiato);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
      _mostraComandi();
    }).catchError((Object e) {
      if (mounted) setState(() => _errore = 'Video non riproducibile');
    });
  }

  void _cambiato() {
    final v = _c.value;
    if (v.isPlaying != _inRiproduzione) {
      _inRiproduzione = v.isPlaying;
      // Mentre il video va lo schermo non si spegne.
      Presenza.istanza.videoInCorso = v.isPlaying;
    }
    if (v.isInitialized && v.isCompleted) {
      // Finito il video si torna allo specchio.
      if (!_finito && mounted) {
        _finito = true;
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      return;
    }
    if (mounted) setState(() {});
  }

  void _mostraComandi() {
    setState(() => _comandi = true);
    _nascondi?.cancel();
    _nascondi = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _comandi = false);
    });
  }

  @override
  void dispose() {
    Jarvis.istanza.rimuovi(_comando);
    _nascondi?.cancel();
    _c.removeListener(_cambiato);
    _c.dispose();
    Presenza.istanza.videoInCorso = false;
    super.dispose();
  }

  String _durata(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _mostraComandi,
        child: Stack(
          children: [
            Center(
              child: _errore != null
                  ? _Vuoto(_errore!)
                  : v.isInitialized
                      ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c))
                      : const SizedBox.shrink(),
            ),
            AnimatedOpacity(
              opacity: _comandi ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(
                ignoring: !_comandi,
                child: Stack(
                  children: [
                    const Positioned(top: 8, right: 8, child: BottoneChiudi()),
                    Positioned(
                      top: 18,
                      left: 24,
                      right: 80,
                      child: Text(nomeFile(widget.file),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, color: Colors.white70)),
                    ),
                    if (v.isInitialized)
                      Center(
                        child: IconButton(
                          iconSize: 72,
                          onPressed: () {
                            v.isPlaying ? _c.pause() : _c.play();
                            _mostraComandi();
                          },
                          icon: Icon(
                              v.isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                              color: Colors.white),
                        ),
                      ),
                    if (v.isInitialized)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 16,
                        child: Row(
                          children: [
                            Text(_durata(v.position),
                                style: const TextStyle(fontSize: 13, color: Colors.white70)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: VideoProgressIndicator(
                                _c,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                colors: const VideoProgressColors(
                                  playedColor: Colors.white,
                                  bufferedColor: Colors.white24,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(_durata(v.duration),
                                style: const TextStyle(fontSize: 13, color: Colors.white70)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
