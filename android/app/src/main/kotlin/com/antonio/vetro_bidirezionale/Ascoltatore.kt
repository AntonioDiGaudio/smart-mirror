package com.antonio.vetro_bidirezionale

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener

/**
 * Registra dal microfono e passa l'audio a Vosk (al posto di SpeechService).
 * Usa la sorgente "comunicazione vocale" con cancellazione dell'eco: toglie
 * dal microfono la voce di Jarvis che esce dall'altoparlante, così si può
 * interromperla mentre parla.
 */
class Ascoltatore(
    private val riconoscitore: Recognizer,
    private val ascolto: RecognitionListener,
) {
    private val frequenza = 16000
    private val principale = Handler(Looper.getMainLooper())

    @Volatile private var inPausa = false
    @Volatile private var fermo = false

    private var registratore: AudioRecord? = null
    private var antiEco: AcousticEchoCanceler? = null
    private var antiRumore: NoiseSuppressor? = null
    private var filo: Thread? = null

    fun avvia(): Boolean {
        val minimo = AudioRecord.getMinBufferSize(
            frequenza, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val campioni = frequenza / 10 // blocchi da 0,1 secondi
        val r = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            frequenza,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minimo, campioni * 2 * 4),
        )
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            return false
        }
        if (AcousticEchoCanceler.isAvailable()) {
            antiEco = AcousticEchoCanceler.create(r.audioSessionId)?.apply { enabled = true }
        }
        // Il filtro antirumore "da telefonata" toglie anche pezzi di voce utili
        // al riconoscimento: meglio spento (l'antieco invece resta).
        if (NoiseSuppressor.isAvailable()) {
            antiRumore = NoiseSuppressor.create(r.audioSessionId)?.apply { enabled = false }
        }
        Log.i("Jarvis", "microfono: antieco=${antiEco?.enabled} antirumore=${antiRumore?.enabled}")
        registratore = r
        r.startRecording()

        filo = Thread {
            val blocco = ShortArray(campioni)
            while (!fermo) {
                val letti = r.read(blocco, 0, blocco.size)
                if (letti <= 0) {
                    if (letti < 0) {
                        principale.post { ascolto.onError(Exception("Errore microfono $letti")) }
                        break
                    }
                    continue
                }
                if (inPausa) continue
                if (riconoscitore.acceptWaveForm(blocco, letti)) {
                    val risultato = riconoscitore.result
                    principale.post { if (!fermo) ascolto.onResult(risultato) }
                } else {
                    val parziale = riconoscitore.partialResult
                    principale.post { if (!fermo) ascolto.onPartialResult(parziale) }
                }
            }
        }.apply {
            name = "jarvis-microfono"
            start()
        }
        return true
    }

    fun setPause(pausa: Boolean) {
        inPausa = pausa
    }

    fun ferma() {
        fermo = true
        try {
            registratore?.stop()
        } catch (_: Exception) {
        }
        filo?.join(1000)
        registratore?.release()
        antiEco?.release()
        antiRumore?.release()
        riconoscitore.close()
        registratore = null
    }
}
