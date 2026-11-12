package com.antonio.vetro_bidirezionale

import android.Manifest
import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        /** L'activity visibile in questo momento, usata dal servizio del sensore. */
        @Volatile
        var attiva: MainActivity? = null
    }

    private var canale: MethodChannel? = null
    private var jarvis: Jarvis? = null
    private var microfonoChiesto = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Si mostra sopra la schermata di blocco, la salta e accende lo schermo.
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        startForegroundService(Intent(this, PresenzaService::class.java))
        chiediEsenzioneRisparmioBatteria()
        chiediAmministratore()
    }

    /** A ogni avvio, finché non è attivo: permesso per spegnere lo schermo quando non c'è nessuno. */
    private fun chiediAmministratore() {
        val dpm = getSystemService(DevicePolicyManager::class.java) ?: return
        val admin = ComponentName(this, Amministratore::class.java)
        if (dpm.isAdminActive(admin)) return
        startActivity(
            Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                .putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Serve solo a spegnere lo schermo dello specchio quando non c'è nessuno davanti."
                )
        )
    }

    override fun onResume() {
        super.onResume()
        attiva = this
        getSystemService(KeyguardManager::class.java)?.let {
            if (it.isKeyguardLocked) it.requestDismissKeyguard(this, null)
        }
        presenza()
        // Il guardiano (schermo spento) libera il microfono: ora ascolta Jarvis.
        PresenzaService.fermaGuardiano()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            jarvis?.avvia()
            // "Jarvis meteo" detto a schermo spento: lo si esegue ora.
            PresenzaService.fraseInSospeso?.let { frase ->
                PresenzaService.fraseInSospeso = null
                window.decorView.postDelayed({ canale?.invokeMethod("voce", mapOf("tipo" to "frase", "testo" to frase)) }, 700)
            }
        } else if (!microfonoChiesto) {
            microfonoChiesto = true
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) jarvis?.avvia()
    }

    override fun onPause() {
        if (attiva === this) attiva = null
        jarvis?.ferma()
        super.onPause()
    }

    override fun onDestroy() {
        jarvis?.distruggi()
        super.onDestroy()
    }

    fun presenza() = runOnUiThread { canale?.invokeMethod("presenza", null) }

    /**
     * Senza esenzione, dopo un'ora circa a schermo spento Android (Doze) ferma
     * sensore e ascolto di "Jarvis". Finché non c'è, la chiede a ogni avvio:
     * compare un dialogo sul telefono.
     */
    private fun chiediEsenzioneRisparmioBatteria() {
        val pm = getSystemService(PowerManager::class.java) ?: return
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        canale = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "specchio/sistema").apply {
            jarvis = Jarvis(this@MainActivity) { tipo, testo ->
                runOnUiThread { invokeMethod("voce", mapOf("tipo" to tipo, "testo" to testo)) }
            }
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "voceConfigura" -> {
                        jarvis?.configura(call.arguments as String)
                        result.success(null)
                    }
                    "zitto" -> result.success(jarvis?.zitto() ?: false)
                    "volume" -> {
                        val livello = call.argument<Int>("livello")
                        val variazione = call.argument<Int>("variazione")
                        result.success(jarvis?.volume(livello, variazione) ?: 0)
                    }
                    "ascoltoLibero" -> {
                        jarvis?.ascoltoLibero(call.arguments == true)
                        result.success(null)
                    }
                    "parla" -> {
                        jarvis?.parla(call.arguments as String)
                        result.success(null)
                    }
                    "batteria" -> {
                        val stato = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        if (stato == null) {
                            result.error("NO_BATTERIA", "Stato batteria non disponibile", null)
                        } else {
                            val livello = stato.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                            val scala = stato.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                            val plugged = stato.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
                            result.success(mapOf("livello" to (livello * 100 / scala), "inCarica" to (plugged != 0)))
                        }
                    }
                    // true: lo schermo resta acceso. false: Android lo spegne col suo timeout.
                    "schermoAcceso" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "sensoreVicino" -> result.success(PresenzaService.vicino)
                    "risorse" -> result.success(Risorse.leggi(this@MainActivity))
                    // true: luminosità al minimo (schermo "spento" senza permesso di amministratore).
                    "luminositaMinima" -> {
                        window.attributes = window.attributes.apply {
                            screenBrightness = if (call.arguments == true) 0.0f
                            else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        }
                        result.success(null)
                    }
                    // Spegne davvero lo schermo; il sensore di prossimità lo riaccende.
                    "spegniSchermo" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        val dpm = getSystemService(DevicePolicyManager::class.java)
                        val admin = ComponentName(this@MainActivity, Amministratore::class.java)
                        if (dpm != null && dpm.isAdminActive(admin)) {
                            dpm.lockNow()
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "cartellaMedia" -> {
                        val media = File(getExternalFilesDir(null), "media")
                        File(media, "foto").mkdirs()
                        File(media, "video").mkdirs()
                        result.success(media.absolutePath)
                    }
                    "impostazioni" -> {
                        startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
