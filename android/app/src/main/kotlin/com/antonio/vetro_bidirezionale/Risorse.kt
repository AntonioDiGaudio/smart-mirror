package com.antonio.vetro_bidirezionale

import android.app.ActivityManager
import android.content.Context
import android.os.Environment
import android.os.StatFs
import android.util.Log
import java.io.File

/** Uso di CPU e RAM e spazio libero su disco, per l'angolo in basso a destra. */
object Risorse {
    private var precedente: LongArray? = null
    private var fonteCpuAnnunciata = false

    fun leggi(contesto: Context): Map<String, Any?> {
        val am = contesto.getSystemService(ActivityManager::class.java)
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val disco = StatFs(Environment.getDataDirectory().path)
        return mapOf(
            "cpu" to cpu(),
            "ram" to (mem.totalMem - mem.availMem) * 100.0 / mem.totalMem,
            "discoLiberoGb" to disco.availableBytes / 1_073_741_824.0,
            "discoLiberoPerc" to disco.availableBytes * 100.0 / disco.totalBytes,
        )
    }

    /**
     * Uso della CPU in percentuale. Da /proc/stat se Android lo lascia leggere;
     * altrimenti (Android 8+ spesso lo vieta) dalla frequenza media dei core
     * rispetto al massimo, che sale e scende con il carico.
     */
    private fun cpu(): Double? {
        try {
            val v = File("/proc/stat").bufferedReader().use { it.readLine() }
                .trim().split(Regex("\\s+")).drop(1).map { it.toLong() }
            val inattivo = v[3] + v.getOrElse(4) { 0 }
            val totale = v.sum()
            val prima = precedente
            precedente = longArrayOf(totale, inattivo)
            annuncia("/proc/stat")
            if (prima == null) return null
            val dt = totale - prima[0]
            val di = inattivo - prima[1]
            return if (dt > 0) (dt - di) * 100.0 / dt else null
        } catch (_: Exception) {
        }
        var somma = 0.0
        var core = 0
        File("/sys/devices/system/cpu").listFiles { f -> f.name.matches(Regex("cpu\\d+")) }?.forEach { c ->
            try {
                val ora = File(c, "cpufreq/scaling_cur_freq").readText().trim().toDouble()
                val max = File(c, "cpufreq/cpuinfo_max_freq").readText().trim().toDouble()
                somma += ora / max
                core++
            } catch (_: Exception) {
                // core spento: conta come inattivo
                core++
            }
        }
        annuncia("frequenze dei core")
        return if (core > 0) somma / core * 100 else null
    }

    private fun annuncia(fonte: String) {
        if (fonteCpuAnnunciata) return
        fonteCpuAnnunciata = true
        Log.i("Jarvis", "CPU letta da: $fonte")
    }
}
