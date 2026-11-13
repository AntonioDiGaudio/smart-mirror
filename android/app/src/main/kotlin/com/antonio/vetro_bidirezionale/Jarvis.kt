package com.antonio.vetro_bidirezionale

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Log
import org.json.JSONObject
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import java.util.Locale

/**
 * Orecchie e voce di Jarvis.
 * - Ascolta col microfono solo mentre l'app è in primo piano (avvia/ferma).
 * - Riconosce offline con Vosk, limitato alle parole dei comandi (grammatica
 *   decisa dal lato Flutter), e manda le frasi a Flutter.
 * - Parla con la sintesi vocale di Android; mentre parla non ascolta.
 */
class Jarvis(
    private val activity: Activity,
    private val invia: (tipo: String, testo: String?) -> Unit,
) : RecognitionListener {

    companion object {
        /** Grammatica dei comandi, usata anche dal guardiano a schermo spento. */
        @Volatile
        var ultimaGrammatica: String? = null
            private set
    }

    private val principale = Handler(Looper.getMainLooper())
    private var servizio: Ascoltatore? = null
    private var grammatica: String? = null
    private var attivo = false

    private var tts: TextToSpeech? = null
    private var ttsPronto = false

    fun configura(grammaticaJson: String) {
        grammatica = grammaticaJson
        ultimaGrammatica = grammaticaJson
        if (attivo) {
            chiudiServizio()
            ascolta()
        }
    }

    fun avvia() {
        attivo = true
        preparaVoce()
        riprovaGoogleSeServe()
        if (ModelloVocale.modello != null) {
            ascolta()
            return
        }
        if (!ModelloVocale.presente(activity)) {
            invia("stato", "senza-modello")
            return
        }
        invia("stato", "caricamento")
        ModelloVocale.carica(activity) { caricato ->
            if (caricato == null) invia("stato", "errore") else ascolta()
        }
    }

    fun ferma() {
        attivo = false
        libero = false
        chiudiServizio()
        tts?.stop()
        modalitaVivavoce(false)
        invia("stato", "spento")
    }

    /**
     * Come una chiamata in vivavoce: attiva l'antieco hardware del telefono
     * sulla voce di Jarvis. Solo mentre l'app è aperta.
     */
    private fun modalitaVivavoce(attiva: Boolean) {
        val audio = activity.getSystemService(AudioManager::class.java) ?: return
        try {
            audio.mode = if (attiva) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
            audio.isSpeakerphoneOn = attiva
            if (attiva) allineaVolumeVoce(audio)
        } catch (e: Exception) {
            Log.w("Jarvis", "vivavoce non disponibile: $e")
        }
    }

    /** Il volume della voce (canale chiamata) segue quello di musica e video. */
    private fun allineaVolumeVoce(audio: AudioManager) {
        val musica = audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() /
            audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val maxVoce = audio.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
        audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL, Math.round(musica * maxVoce).coerceAtLeast(1), 0)
    }

    fun distruggi() {
        ferma()
        tts?.shutdown()
        tts = null
    }

    private fun ascolta() {
        val m = ModelloVocale.modello ?: return
        val g = grammatica ?: return
        if (!attivo || servizio != null) return
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            invia("stato", "senza-microfono")
            return
        }
        try {
            val riconoscitore = if (libero) Recognizer(m, 16000f) else Recognizer(m, 16000f, g)
            modalitaVivavoce(true)
            val nuovo = Ascoltatore(riconoscitore, this)
            if (!nuovo.avvia()) throw IllegalStateException("microfono non disponibile")
            if (parlando && libero) nuovo.setPause(true)
            servizio = nuovo
            invia("stato", if (libero) "libero" else "ascolto")
        } catch (e: Exception) {
            servizio = null
            invia("stato", "errore")
            // Il microfono può essere ancora occupato per un attimo: si riprova.
            principale.postDelayed({ ascolta() }, 1500)
        }
    }

    private fun chiudiServizio() {
        servizio?.ferma()
        servizio = null
    }

    // ------------------------------------------------------------ Voce

    private fun preparaVoce(provaGoogle: Boolean = true) {
        if (tts != null) return
        // La voce di Google è più naturale di quella Samsung: se c'è, usiamo quella.
        val google = "com.google.android.tts"
        val haGoogle = provaGoogle && try {
            activity.packageManager.getPackageInfo(google, 0); true
        } catch (_: Exception) {
            false
        }
        val inizializzato = TextToSpeech.OnInitListener { esito ->
            val t = tts ?: return@OnInitListener
            if (esito != TextToSpeech.SUCCESS || (!scegliVoceFemminile(t) && haGoogle)) {
                // Google senza voci italiane scaricate: si torna alla voce Samsung,
                // e più tardi si riprova con Google (vedi avvia()).
                t.shutdown()
                tts = null
                if (haGoogle) {
                    voceDiRiserva = true
                    preparaVoce(provaGoogle = false)
                }
                return@OnInitListener
            }
            if (haGoogle) voceDiRiserva = false
            // Un filo più veloce suona meno "scandito" e più naturale.
            t.setSpeechRate(1.08f)
            t.setPitch(1.0f)
            // Parla sul canale "chiamata": così l'antieco del telefono sa cosa
            // esce dall'altoparlante e lo toglie dal microfono.
            t.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) = riprendiAscolto()
                @Deprecated("Deprecated in Java")
                override fun onError(id: String?) = riprendiAscolto()
            })
            ttsPronto = true
            // Se nel frattempo doveva dire qualcosa, lo dice ora.
            daDire?.let { frase ->
                daDire = null
                principale.post { parla(frase) }
            }
        }
        tts = if (haGoogle) TextToSpeech(activity, inizializzato, google) else TextToSpeech(activity, inizializzato)
    }

    /** Voce Google via internet: più naturale e fluida. Si usa quando c'è rete. */
    private var voceRete: Voice? = null

    /** Voce installata sul telefono: si usa senza internet. */
    private var voceLocale: Voice? = null

    /**
     * Tra le voci italiane sceglie una voce femminile: quella via rete (più
     * naturale) e quella installata sul telefono (di riserva, senza internet).
     */
    private fun scegliVoceFemminile(t: TextToSpeech): Boolean {
        t.language = Locale.ITALIAN
        val italiane = try {
            t.voices.orEmpty().filter { it.locale.language == "it" }
        } catch (_: Exception) {
            emptyList()
        }
        italiane.forEach {
            Log.i("Jarvis", "voce ${it.name} qualita=${it.quality} rete=${it.isNetworkConnectionRequired} ${it.features}")
        }
        // Voci italiane di Google: "itb" e "kda" sono femminili, "itc" e "itd" maschili
        // (come le varianti "#male_N"). "itb" è la più naturale dei motori recenti.
        val femminili = italiane.filter {
            !it.features.orEmpty().contains("notInstalled") &&
                !it.name.contains("#male") && !it.name.contains("-itc-") && !it.name.contains("-itd-")
        }
        fun migliore(rete: Boolean) = femminili.filter { it.isNetworkConnectionRequired == rete }.let { v ->
            v.firstOrNull { it.name.contains("-itb-") }
                ?: v.firstOrNull { it.name.contains("-kda-") && !it.name.contains("#") }
                ?: v.firstOrNull { it.name.contains("#female") }
                ?: v.maxByOrNull { it.quality }
        }
        val scelta = migliore(rete = false)
        voceLocale = scelta
        voceRete = migliore(rete = true)
        if (scelta != null) t.voice = scelta
        Log.i("Jarvis", "voce locale: ${scelta?.name ?: "predefinita"}, via rete: ${voceRete?.name ?: "nessuna"}")
        return scelta != null
    }

    private fun online(): Boolean {
        @Suppress("DEPRECATION")
        return activity.getSystemService(ConnectivityManager::class.java)?.activeNetworkInfo?.isConnected == true
    }

    private var parlando = false
    private var ultimoParziale = ""

    /** Frase da dire appena la voce è pronta (dopo un ricollegamento). */
    private var daDire: String? = null

    /** true se sta usando la voce Samsung perché Google non aveva voci italiane. */
    private var voceDiRiserva = false
    private var ultimoTentativoGoogle = 0L

    /** Con la voce di riserva, ogni tanto riprova Google (es. dopo che ha riscaricato l'italiano). */
    private fun riprovaGoogleSeServe() {
        val ora = System.currentTimeMillis()
        if (!voceDiRiserva || parlando || ora - ultimoTentativoGoogle < 10 * 60_000) return
        ultimoTentativoGoogle = ora
        Log.i("Jarvis", "riprovo la voce di Google")
        ricollegaVoce(null)
    }

    fun parla(testo: String) {
        if (testo.isBlank()) return
        val t = tts
        if (t == null || !ttsPronto) {
            daDire = testo
            if (t == null) preparaVoce()
            return
        }
        // Con internet la voce più naturale, altrimenti quella sul telefono.
        val voce = if (online()) voceRete ?: voceLocale else voceLocale
        if (voce != null && t.voice?.name != voce.name) t.voice = voce
        Log.i("Jarvis", "dico: $testo")
        parlando = true
        invia("parlando", "si")
        // Mentre parla continua ad ascoltare, così "Jarvis stop" la interrompe
        // (lei non dice mai "Jarvis", quindi non si comanda da sola).
        // Solo quando aspetta l'argomento da cercare non deve sentire sé stessa.
        if (libero) servizio?.setPause(true)
        if (t.speak(testo, TextToSpeech.QUEUE_FLUSH, null, "jarvis") == TextToSpeech.ERROR) {
            // Il servizio vocale si è scollegato (es. Google l'ha aggiornato di
            // notte): si ricollega e ripete la frase appena è pronto.
            Log.w("Jarvis", "voce scollegata, la ricollego")
            parlando = false
            invia("parlando", "no")
            ricollegaVoce(testo)
        }
    }

    private fun ricollegaVoce(testo: String?) {
        daDire = testo
        ttsPronto = false
        try {
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        preparaVoce()
    }

    /** "Jarvis stop": smette di parlare. true se stava parlando. */
    fun zitto(): Boolean {
        val stavaParlando = tts?.isSpeaking == true
        tts?.stop()
        riprendiAscolto()
        return stavaParlando
    }

    /**
     * Volume di voce e video su una scala da 0 a 10.
     * [livello] assoluto, oppure [variazione] rispetto all'attuale. Restituisce il nuovo livello.
     */
    fun volume(livello: Int?, variazione: Int?): Int {
        val audio = activity.getSystemService(AudioManager::class.java) ?: return 0
        val massimo = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val attuale = Math.round(audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 10f / massimo)
        val nuovo = (livello ?: (attuale + (variazione ?: 0))).coerceIn(0, 10)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(nuovo * massimo / 10f), 0)
        if (nuovo > 0) allineaVolumeVoce(audio)
        return nuovo
    }

    private fun riprendiAscolto() {
        // Piccola attesa: l'eco della voce si spegne prima di riascoltare.
        principale.postDelayed({
            parlando = false
            invia("parlando", "no")
            servizio?.setPause(false)
        }, 300)
    }

    // ------------------------------------------------------------ Ascolto libero

    /**
     * Per una frase sola ascolta senza limiti di vocabolario (es. l'argomento
     * da cercare), poi torna ai soli comandi.
     */
    private var libero = false

    fun ascoltoLibero(attivo: Boolean) {
        if (libero == attivo) return
        libero = attivo
        if (this.attivo) {
            chiudiServizio()
            ascolta()
        }
    }

    // ------------------------------------------------------------ Vosk

    override fun onPartialResult(ipotesi: String?) {
        val testo = ipotesi?.let { JSONObject(it).optString("partial") } ?: return
        // "Sta ancora parlando": serve a non rispondere "mi dica" a metà frase.
        if (testo.isNotEmpty() && testo != ultimoParziale) invia("parziale", testo)
        ultimoParziale = testo
        if (!testo.contains("jarvis")) return
        // Appena sente il suo nome smette di parlare: così il resto del
        // comando arriva pulito, senza la sua voce sopra.
        if (parlando && tts?.isSpeaking == true) {
            Log.i("Jarvis", "interrotta da: $testo")
            tts?.stop()
            riprendiAscolto()
        }
        invia("sento", testo)
    }

    override fun onResult(ipotesi: String?) = frase(ipotesi)

    override fun onFinalResult(ipotesi: String?) = frase(ipotesi)

    private fun frase(ipotesi: String?) {
        val testo = ipotesi?.let { JSONObject(it).optString("text") }?.trim() ?: return
        if (testo.isEmpty()) return
        Log.i("Jarvis", "sentito${if (libero) " (libero)" else ""}: $testo")
        if (libero) {
            invia("frase-libera", testo)
            principale.post { ascoltoLibero(false) }
        } else {
            invia("frase", testo)
        }
    }

    override fun onError(e: Exception?) {
        invia("stato", "errore")
        chiudiServizio()
        principale.postDelayed({ ascolta() }, 2000)
    }

    override fun onTimeout() {}
}
