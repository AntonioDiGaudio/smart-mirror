package com.antonio.vetro_bidirezionale

import android.app.admin.DeviceAdminReceiver

/**
 * Permesso "amministratore dispositivo" usato solo per spegnere lo schermo
 * (lockNow) quando non c'è nessuno. Per disinstallare l'app va prima tolto da
 * Impostazioni > Schermata di blocco e sicurezza > Altre impostazioni > App amministrazione dispositivo.
 */
class Amministratore : DeviceAdminReceiver()
