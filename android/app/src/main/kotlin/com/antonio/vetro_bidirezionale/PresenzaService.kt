package com.antonio.vetro_bidirezionale

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.IBinder
import android.os.PowerManager

/**
 * Tiene d'occhio lo specchio anche a schermo spento:
 * - sensore di prossimità: una mano davanti riaccende lo schermo;
 * - guardiano vocale: "Jarvis ..." riaccende lo schermo ed esegue il comando.
 */
class PresenzaService : Service(), SensorEventListener {
    companion object {
        /**
         * Ascoltare "Jarvis" anche a schermo spento. Comodo ma consuma batteria:
         * il telefono non va mai in sonno profondo. false per disattivarlo.
         */
        const val ASCOLTO_A_SCHERMO_SPENTO = true

        /** true finché il sensore di prossimità vede qualcosa davanti. */
        @Volatile
        var vicino = false
            private set

        /** Frase detta a schermo spento, da eseguire appena l'app è aperta. */
        @Volatile
        var fraseInSospeso: String? = null

        @Volatile
        private var istanza: PresenzaService? = null

        /** Libera il microfono: lo chiama l'app prima di ascoltare lei. */
        fun fermaGuardiano() = istanza?.fermaGuardiano()
    }

    private lateinit var sensori: SensorManager
    private var guardiano: Guardiano? = null

    private val schermo = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_SCREEN_OFF -> avviaGuardiano()
                Intent.ACTION_SCREEN_ON -> fermaGuardiano()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        istanza = this
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel("presenza", "Sensore di presenza", NotificationManager.IMPORTANCE_MIN)
        )
        startForeground(
            1,
            Notification.Builder(this, "presenza")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Specchio attivo")
                .setContentText("Mano davanti o \"Jarvis\" per riaccendere")
                .build()
        )

        sensori = getSystemService(SensorManager::class.java)
        // Versione "wake-up": arriva anche col telefono in sospensione.
        val prossimita = sensori.getDefaultSensor(Sensor.TYPE_PROXIMITY, true)
            ?: sensori.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        prossimita?.let { sensori.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) }

        registerReceiver(schermo, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY

    override fun onDestroy() {
        sensori.unregisterListener(this)
        unregisterReceiver(schermo)
        fermaGuardiano()
        istanza = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(e: SensorEvent) {
        val ora = e.values[0] < e.sensor.maximumRange
        if (ora && !vicino) presenza()
        vicino = ora
    }

    // ------------------------------------------------------------ Guardiano vocale

    private fun avviaGuardiano() {
        if (!ASCOLTO_A_SCHERMO_SPENTO || guardiano != null) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return
        val grammatica = Jarvis.ultimaGrammatica ?: return
        ModelloVocale.carica(this) { modello ->
            val pm = getSystemService(PowerManager::class.java)
            // Nel frattempo lo schermo potrebbe essersi già riacceso.
            if (modello == null || guardiano != null || pm.isInteractive) return@carica
            val g = Guardiano(this, modello, grammatica) { frase ->
                fraseInSospeso = frase
                fermaGuardiano()
                presenza()
            }
            if (g.avvia()) guardiano = g
        }
    }

    private fun fermaGuardiano() {
        guardiano?.ferma()
        guardiano = null
    }

    private fun presenza() {
        val pm = getSystemService(PowerManager::class.java)
        if (!pm.isInteractive) {
            @Suppress("DEPRECATION")
            pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "specchio:presenza"
            ).acquire(5_000)
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
        MainActivity.attiva?.presenza()
    }
}
