package com.antonio.vetro_bidirezionale

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import kotlin.math.max
import kotlin.math.sqrt

/**
 * A schermo spento ascolta solo una cosa: "Jarvis ...".
 *
 * Per consumare poco, il riconoscimento (la parte pesante) lavora solo quando
 * c'è un suono: nel silenzio il microfono registra ma Vosk resta fermo.
 * Quando sente una frase con "Jarvis", la passa a [svegliati].
 */
class Guardiano(
    contesto: Context,
    modello: Model,
    grammatica: String,
    private val svegliati: (frase: String) -> Unit,
) {
    private val frequenza = 16000
    private val campioni = frequenza / 10 // blocchi da 0,1 s
    private val principale = Handler(Looper.getMainLooper())
    private val riconoscitore = Recognizer(modello, frequenza.toFloat(), grammatica)

    // Il telefono non deve addormentarsi del tutto, altrimenti il microfono si ferma.
    private val sveglia = (contesto.getSystemService(Context.POWER_SERVICE) as PowerManager)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "specchio:guardiano")

    @Volatile private var fermo = false
    private var registratore: AudioRecord? = null
    private var filo: Thread? = null

    fun avvia(): Boolean {
        val minimo = AudioRecord.getMinBufferSize(frequenza, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val r = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION, frequenza,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(minimo, campioni * 2 * 4),
        )
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            riconoscitore.close()
            return false
        }
        registratore = r
        sveglia.acquire()
        r.startRecording()
        filo = Thread({ ciclo(r) }, "jarvis-guardiano").apply { start() }
        Log.i("Jarvis", "guardiano acceso (schermo spento)")
        return true
    }

    private fun ciclo(r: AudioRecord) {
        // Ultimi 0,4 s tenuti da parte: così l'inizio di "Jarvis" non si perde.
        val prima = ArrayDeque<ShortArray>()
        var rumoreDiFondo = 200.0
        var inAscolto = false
        var ultimoSuono = 0L

        while (!fermo) {
            val blocco = ShortArray(campioni)
            val letti = r.read(blocco, 0, blocco.size)
            if (letti <= 0) {
                if (letti < 0) break
                continue
            }
            var somma = 0.0
            for (k in 0 until letti) somma += blocco[k].toDouble() * blocco[k]
            val volume = sqrt(somma / letti)
            val soglia = max(350.0, rumoreDiFondo * 2.5)
            val ora = System.currentTimeMillis()

            if (volume > soglia) {
                if (!inAscolto) {
                    inAscolto = true
                    for (b in prima) accetta(b, b.size)
                    prima.clear()
                }
                ultimoSuono = ora
            } else if (!inAscolto) {
                // Silenzio: si aggiorna solo il rumore di fondo, Vosk resta fermo.
                rumoreDiFondo = rumoreDiFondo * 0.95 + volume * 0.05
            }

            if (inAscolto) {
                accetta(blocco, letti)
                // Un secondo e mezzo di silenzio dopo la voce: fine della frase.
                if (ora - ultimoSuono > 1500) {
                    controlla(riconoscitore.finalResult)
                    inAscolto = false
                }
            } else {
                prima.addLast(blocco)
                if (prima.size > 4) prima.removeFirst()
            }
        }
    }

    private fun accetta(blocco: ShortArray, letti: Int) {
        if (riconoscitore.acceptWaveForm(blocco, letti)) controlla(riconoscitore.result)
    }

    private fun controlla(json: String) {
        val testo = JSONObject(json).optString("text").trim()
        if (testo.isEmpty()) return
        Log.i("Jarvis", "guardiano ha sentito: $testo")
        if (testo.split(" ").contains("jarvis")) {
            fermo = true
            principale.post { svegliati(testo) }
        }
    }

    fun ferma() {
        fermo = true
        try {
            registratore?.stop()
        } catch (_: Exception) {
        }
        filo?.join(1000)
        registratore?.release()
        registratore = null
        riconoscitore.close()
        if (sveglia.isHeld) sveglia.release()
        Log.i("Jarvis", "guardiano spento")
    }
}
