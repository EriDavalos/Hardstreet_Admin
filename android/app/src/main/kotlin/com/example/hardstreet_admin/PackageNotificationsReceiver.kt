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
 * AVISOS CON LA APP CERRADA (Android).
 *
 * La app en primer plano consulta sus avisos cada pocos segundos (ver
 * `reminders_service.dart` y `package_notifications_service.dart`). Con la app
 * cerrada no queda nadie preguntando, así que el cliente no se enteraba de un
 * aviso hasta abrir el panel.
 *
 * Este receptor hace ese trabajo sin la app: una alarma lo despierta y consulta
 * los DOS orígenes con el token guardado:
 *
 *   * `GET /api/my/notifications` -> avisos del PAQUETE («ya puedes elegir tus
 *     fotos», «servicio terminado»…), canal `paquete`.
 *   * `GET /api/reminders`        -> EVENTOS próximos (falta 1 semana / 1 día) y
 *     avisos de impresión, canal `reminders`.
 *
 * Por cada aviso SIN LEER que no se haya mostrado antes publica UNA
 * notificación. Los avisos de impresión viven en otra tabla y sus ids pueden
 * coincidir con los de la agenda: se desplazan (1000000 + id) tanto en la
 * bandeja como en la lista de «ya mostrados».
 *
 * Detalles que hacen que esto funcione de verdad:
 *
 *   * La alarma es de UNA sola vez con `setAndAllowWhileIdle` y se vuelve a
 *     programar al final de cada consulta. Las alarmas repetitivas
 *     (`setInexactRepeating`) se aplazan en Doze y podían tardar horas.
 *   * El intervalo es de un minuto: el aviso llega casi al instante cuando el
 *     teléfono está despierto; en Doze el sistema lo espacia (no gasta batería
 *     de más) y aun así vuelve a consultar en cuanto el equipo despierta.
 *   * La primera consulta va a los [FIRST_DELAY_MS] de abrir la app: si el
 *     estudio avisa al cliente justo cuando deja el teléfono, se entera ya.
 *   * Los ids ya mostrados se guardan en la MISMA preferencia que la app
 *     ([KEY_SHOWN_PACKAGE] y [KEY_SHOWN_REMINDERS]), no en copias aparte: la
 *     app y este worker nunca avisan dos veces del mismo aviso.
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
                        // Mejor esfuerzo: los avisos también viven en el panel.
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }

    /** Canal de Android con el que sale un aviso (id, nombre y descripción). */
    private data class Channel(val id: String, val name: String, val desc: String)

    companion object {
        /** Alarma propia (intent explícito al receptor: ver el manifiesto). */
        const val ACTION_POLL = "com.example.hardstreet_admin.PACKAGE_NOTIFICATIONS_POLL"

        /**
         * Cada cuánto se vuelve a consultar. Un minuto: un aviso llega casi al
         * instante aunque el cliente no tenga la app abierta. En Doze el
         * sistema lo espacia (no gasta batería de más); fuera de Doze se
         * respeta este intervalo.
         */
        const val POLL_MS = 60L * 1000L

        /** Primera consulta tras abrir (o dejar) la app: casi inmediata. */
        private const val FIRST_DELAY_MS = 45L * 1000L

        private const val REQ_POLL = 31

        private val PACKAGE_CHANNEL = Channel(
            "paquete",
            "Avisos de mi paquete",
            "Fotos disponibles, servicios terminados y avisos del estudio"
        )

        private val EVENT_CHANNEL = Channel(
            "reminders",
            "Avisos de eventos",
            "Recordatorios de eventos próximos (1 semana / 1 día)"
        )

        /** Los del paquete se desplazan para no chocar con los de eventos. */
        private const val PACKAGE_OFFSET = 500000

        /** Los de impresión ya vienen desplazados en [keyOf] (1000000 + id). */
        private const val EVENT_OFFSET = 0

        /** Preferencias de Flutter (shared_preferences): todo con `flutter.`. */
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_TOKEN = "flutter.app.notify.token"
        private const val KEY_BASE = "flutter.app.notify.base"

        /**
         * LAS MISMAS claves que usan `PackageNotificationsService` y
         * `RemindersService` para recordar los avisos ya mostrados (lista de
         * ids separada por comas). Compartirlas es lo que evita los avisos
         * duplicados entre la app y este worker.
         */
        private const val KEY_SHOWN_PACKAGE = "flutter.app.notified.package"
        private const val KEY_SHOWN_REMINDERS = "flutter.app.notified.reminders"

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

        /** Consulta los DOS orígenes de avisos y notifica los nuevos. */
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
                    prefs.edit()
                        .remove(KEY_SHOWN_PACKAGE)
                        .remove(KEY_SHOWN_REMINDERS)
                        .apply()
                    return
                }
                // Sin permiso de notificaciones (Android 13+) no vale la pena
                // gastar red y batería.
                if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

                val base = prefs.getString(KEY_BASE, null)?.trim()
                    ?.takeIf { it.isNotEmpty() } ?: DEFAULT_BASE

                // 1. Avisos del PAQUETE.
                notifyNew(
                    context = context,
                    prefs = prefs,
                    url = "$base/api/my/notifications",
                    arrayKey = "notifications",
                    token = token,
                    shownKey = KEY_SHOWN_PACKAGE,
                    offset = PACKAGE_OFFSET,
                    channel = PACKAGE_CHANNEL,
                    fallbackTitle = "Aviso de tu paquete"
                )

                // 2. Avisos de EVENTOS (recordatorios de agenda) e impresiones.
                notifyNew(
                    context = context,
                    prefs = prefs,
                    url = "$base/api/reminders",
                    arrayKey = "reminders",
                    token = token,
                    shownKey = KEY_SHOWN_REMINDERS,
                    offset = EVENT_OFFSET,
                    channel = EVENT_CHANNEL,
                    fallbackTitle = "Aviso de evento"
                )
            } finally {
                running = false
            }
        }

        /** Consulta UN origen y publica los avisos nuevos. Nunca lanza. */
        private fun notifyNew(
            context: Context,
            prefs: android.content.SharedPreferences,
            url: String,
            arrayKey: String,
            token: String,
            shownKey: String,
            offset: Int,
            channel: Channel,
            fallbackTitle: String
        ) {
            val items = fetch(url, arrayKey, token) ?: return
            if (items.length() == 0) return

            val shown = readShown(prefs, shownKey)
            var changed = false
            for (i in 0 until items.length()) {
                val n = items.optJSONObject(i) ?: continue
                if (isRead(n)) continue
                val id = n.optInt("id", 0)
                if (id <= 0) continue
                // Los avisos de impresión viven en otra tabla: su id puede
                // coincidir con el de una agenda y son avisos DISTINTOS.
                val key = keyOf(n, id)
                if (shown.contains("$key")) continue
                show(
                    context = context,
                    notificationId = offset + key,
                    requestCode = offset + key,
                    title = n.optString("title"),
                    body = n.optString("body"),
                    channel = channel,
                    fallbackTitle = fallbackTitle
                )
                shown.add("$key")
                changed = true
            }
            if (changed) writeShown(prefs, shownKey, shown)
        }

        /** Clave ÚNICA de un aviso de `/api/reminders` (impresión = 1000000+id). */
        private fun keyOf(n: JSONObject, id: Int): Int {
            val source = n.optString("source", "event")
            return if (source.equals("print", ignoreCase = true)) 1_000_000 + id else id
        }

        /**
         * `isRead` llega como booleano en los avisos del paquete y como 0/1 en
         * los de agenda: se aceptan las dos formas (también "1"/"true").
         */
        private fun isRead(n: JSONObject): Boolean =
            when (val v = n.opt("isRead")) {
                is Boolean -> v
                is Number -> v.toInt() != 0
                is String -> v == "1" || v.equals("true", ignoreCase = true)
                else -> false
            }

        /** Ids ya mostrados, leídos de la preferencia compartida con la app. */
        private fun readShown(
            prefs: android.content.SharedPreferences,
            key: String
        ): MutableSet<String> {
            val raw = prefs.getString(key, null).orEmpty()
            return raw.split(',')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .toMutableSet()
        }

        /** Guarda los ids (los últimos [MAX_SHOWN_IDS]), en el formato de Dart. */
        private fun writeShown(
            prefs: android.content.SharedPreferences,
            key: String,
            shown: MutableSet<String>
        ) {
            val ids = shown
                .mapNotNull { it.toIntOrNull() }
                .distinct()
                .sorted()
                .takeLast(MAX_SHOWN_IDS)
            prefs.edit().putString(key, ids.joinToString(",")).apply()
        }

        /** GET al endpoint de avisos. Devuelve el array [arrayKey]. */
        private fun fetch(url: String, arrayKey: String, token: String): JSONArray? {
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
                JSONObject(text).optJSONArray(arrayKey) ?: JSONArray()
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

        /** Publica UNA notificación en el canal indicado. */
        private fun show(
            context: Context,
            notificationId: Int,
            requestCode: Int,
            title: String,
            body: String,
            channel: Channel,
            fallbackTitle: String
        ) {
            ensureChannel(context, channel)
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val tap = PendingIntent.getActivity(
                context,
                requestCode,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(context, channel.id)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title.ifEmpty { fallbackTitle })
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(tap)
                .build()
            try {
                NotificationManagerCompat.from(context)
                    .notify(notificationId, notification)
            } catch (_: SecurityException) {
                // Android 13+ sin permiso de notificaciones: se omite.
            }
        }

        /** Crea el canal si la app todavía no lo hizo (primer aviso sin abrirla). */
        private fun ensureChannel(context: Context, channel: Channel) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager ?: return
            if (manager.getNotificationChannel(channel.id) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    channel.id,
                    channel.name,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = channel.desc }
            )
        }
    }
}
