package com.antonio.vetro_bidirezionale

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.vosk.Model
import java.io.File

/**
 * Il modello vocale Vosk, condiviso tra Jarvis (app aperta) e il guardiano
 * (schermo spento). Caricato una volta sola: costa qualche secondo e ~80 MB.
 */
object ModelloVocale {
    @Volatile
    var modello: Model? = null
        private set

    private var caricando = false
    private val inAttesa = mutableListOf<(Model?) -> Unit>()
    private val principale = Handler(Looper.getMainLooper())

    fun cartella(contesto: Context) = File(contesto.getExternalFilesDir(null), "modello-vocale")

    fun presente(contesto: Context) = File(cartella(contesto), "am/final.mdl").exists()

    /** Chiama [pronto] sul thread principale, con il modello o null se manca. */
    fun carica(contesto: Context, pronto: (Model?) -> Unit) {
        modello?.let { pronto(it); return }
        if (!presente(contesto)) {
            pronto(null)
            return
        }
        inAttesa.add(pronto)
        if (caricando) return
        caricando = true
        val percorso = cartella(contesto).absolutePath
        Thread {
            val caricato = try {
                Model(percorso)
            } catch (_: Exception) {
                null
            }
            principale.post {
                caricando = false
                modello = caricato
                val chi = inAttesa.toList()
                inAttesa.clear()
                chi.forEach { it(caricato) }
            }
        }.start()
    }
}
