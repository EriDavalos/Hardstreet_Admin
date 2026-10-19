package com.example.hardstreet_admin

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * AVISOS DEL PAQUETE CON LA APP CERRADA (Android).
 *
 * La app en primer plano consulta `GET /api/my/notifications` cada minuto (ver
 * `package_notifications_service.dart`). Con la app cerrada no queda nadie
 * preguntando, así que el cliente no se enteraba de «ya puedes elegir tus
 * fotos» hasta abrir «Mi paquete».
 *
 * Este receptor hace ese trabajo sin la app: una alarma lo despierta y consulta
 * el mismo endpoint con el token guardado. Por cada aviso SIN LEER que no se
 * haya mostrado antes publica UNA notificación en el canal `paquete`.
 *
 * Tres detalles que hacen que esto funcione de verdad:
 *
 *   * La alarma es de UNA sola vez con `setAndAllowWhileIdle` y se vuelve a
 *     programar al final de cada consulta. Las alarmas repetitivas
 *     (`setInexactRepeating`) se aplazan en Doze y podían tardar horas.
 *   * La primera consulta va a los [FIRST_DELAY_MS] de abrir la app: si el
 *     estudio avisa al cliente justo cuando deja el teléfono, se entera ya.
 *   * Los ids ya mostrados se guardan en la MISMA preferencia que la app
 *     ([KEY_SHOWN_IDS]), no en una copia aparte: la app y este worker nunca
 *     avisan dos veces del mismo aviso.
 *
 * Sin token (sesión cerrada) no hace nada y olvida lo mostrado.
 */
class PackageNotificationsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        when (action) {
            // El teléfono se reinició o la app se actualizó: las alarmas se
            // pierden, hay que volver a pedirla.
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> schedule(context)

            ACTION_POLL -> {
                // Re-agendar SIEMPRE antes de consultar: si la red falla o el
                // hilo muere, el ciclo no se queda sin próxima alarma.
                schedule(context, POLL_MS)
                if (running) return
                // goAsync: la conexión va en otro hilo y el sistema no mata al
                // receptor mientras termina.
                val pending = goAsync()
                Thread {
                    try {
                        poll(context)
                    } catch (_: Exception) {
                        // Mejor esfuerzo: el aviso también vive en «Mi paquete».
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }

    companion object {
        /** Alarma propia (intent explícito al receptor: ver el manifiesto). */
        const val ACTION_POLL = "com.example.hardstreet_admin.PACKAGE_NOTIFICATIONS_POLL"

        /** Cada cuánto se vuelve a consultar. En Doze el sistema lo espacia. */
        const val POLL_MS = 10L * 60L * 1000L

        /** Primera consulta tras abrir (o dejar) la app: casi inmediata. */
        private const val FIRST_DELAY_MS = 45L * 1000L

        private const val REQ_POLL = 31

        private const val CHANNEL_ID = "paquete"
        private const val CHANNEL_NAME = "Avisos de mi paquete"
        private const val CHANNEL_DESC =
            "Fotos disponibles, servicios terminados y avisos del estudio"

        /** Desplazan los ids para no chocar con los de los eventos (500000 + id). */
        private const val NOTIFICATION_ID_OFFSET = 500000

        /** Preferencias de Flutter (shared_preferences): todo con `flutter.`. */
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_TOKEN = "flutter.app.notify.token"
        private const val KEY_BASE = "flutter.app.notify.base"

        /**
         * LA MISMA clave que usa `PackageNotificationsService` para recordar los
         * avisos ya mostrados (lista de ids separada por comas). Compartirla es
         * lo que evita los avisos duplicados entre la app y este worker.
         */
        private const val KEY_SHOWN_IDS = "flutter.app.notified.package"

        private const val DEFAULT_BASE = "https://apihardstreet.vercel.app"

        /** Cuántos ids recordar (los avisos ya mostrados son pocos). */
        private const val MAX_SHOWN_IDS = 200

        private const val FETCH_TIMEOUT_MS = 12_000

        /** Una consulta a la vez: dos alarmas seguidas no se pisan. */
        @Volatile
        private var running = false

        /**
         * Pide al sistema que nos despierte en [delayMs]. Se usa `set`/`setAndAllowWhileIdle`
         * (UNA vez) y se re-agenda tras cada consulta: es lo que sí corre en Doze.
         */
        fun schedule(context: Context, delayMs: Long = FIRST_DELAY_MS) {
            try {
                val alarm = context.getSystemService(Context.ALARM_SERVICE)
                    as? AlarmManager ?: return
                val at = SystemClock.elapsedRealtime() + delayMs.coerceAtLeast(5_000L)
                val pi = pollIntent(context)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarm.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        at,
                        pi
                    )
                } else {
                    alarm.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                }
            } catch (_: Exception) {
                // Sin alarma, la app en primer plano sigue avisando igual.
            }
        }

        private fun pollIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                REQ_POLL,
                Intent(context, PackageNotificationsReceiver::class.java)
                    .setAction(ACTION_POLL),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        /** Consulta los avisos y notifica los nuevos. Nunca lanza. */
        private fun poll(context: Context) {
            if (running) return
            running = true
            try {
                val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                val token = prefs.getString(KEY_TOKEN, null)?.trim().orEmpty()
                if (token.isEmpty()) {
                    // Sesión cerrada: no hay a quién avisar y se olvida lo
                    // mostrado (otro usuario en el mismo teléfono debe recibir
                    // SUS avisos).
                    prefs.edit().remove(KEY_SHOWN_IDS).apply()
                    return
                }
                // Sin permiso de notificaciones (Android 13+) no vale la pena
                // gastar red y batería.
                if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

                val base = prefs.getString(KEY_BASE, null)?.trim()
                    ?.takeIf { it.isNotEmpty() } ?: DEFAULT_BASE
                val items = fetch("$base/api/my/notifications", token) ?: return
                if (items.length() == 0) return

                val shown = readShown(prefs)
                var changed = false
                for (i in 0 until items.length()) {
                    val n = items.optJSONObject(i) ?: continue
                    if (n.optBoolean("isRead", false)) continue
                    val id = n.optInt("id", 0)
                    if (id <= 0 || shown.contains("$id")) continue
                    show(context, id, n.optString("title"), n.optString("body"))
                    shown.add("$id")
                    changed = true
                }
                if (changed) writeShown(prefs, shown)
            } finally {
                running = false
            }
        }

        /** Ids ya mostrados, leídos de la preferencia compartida con la app. */
        private fun readShown(prefs: android.content.SharedPreferences): MutableSet<String> {
            val raw = prefs.getString(KEY_SHOWN_IDS, null).orEmpty()
            return raw.split(',')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .toMutableSet()
        }

        /** Guarda los ids (los últimos [MAX_SHOWN_IDS]), en el mismo formato que Dart. */
        private fun writeShown(
            prefs: android.content.SharedPreferences,
            shown: MutableSet<String>
        ) {
            val ids = shown
                .mapNotNull { it.toIntOrNull() }
                .distinct()
                .sorted()
                .takeLast(MAX_SHOWN_IDS)
            prefs.edit().putString(KEY_SHOWN_IDS, ids.joinToString(",")).apply()
        }

        /** GET al endpoint de avisos. Devuelve el array `notifications`. */
        private fun fetch(url: String, token: String): JSONArray? {
            var conn: HttpURLConnection? = null
            return try {
                conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = FETCH_TIMEOUT_MS
                    readTimeout = FETCH_TIMEOUT_MS + 3_000
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                }
                if (conn.responseCode !in 200..299) return null
                val text = conn.inputStream.bufferedReader().use { it.readText() }
                JSONObject(text).optJSONArray("notifications") ?: JSONArray()
            } catch (_: Exception) {
                null
            } finally {
                try {
                    conn?.disconnect()
                } catch (_: Exception) {
                    // nada
                }
            }
        }

        /** Publica UNA notificación, en el canal `paquete` de la app. */
        private fun show(context: Context, id: Int, title: String, body: String) {
            ensureChannel(context)
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val tap = PendingIntent.getActivity(
                context,
                id,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title.ifEmpty { "Aviso de tu paquete" })
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(tap)
                .build()
            try {
                NotificationManagerCompat.from(context)
                    .notify(NOTIFICATION_ID_OFFSET + id, notification)
            } catch (_: SecurityException) {
                // Android 13+ sin permiso de notificaciones: se omite.
            }
        }

        /** Crea el canal si la app todavía no lo hizo (primer aviso sin abrirla). */
        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = CHANNEL_DESC }
            )
        }
    }
}
