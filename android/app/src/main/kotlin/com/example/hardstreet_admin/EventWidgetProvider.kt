package com.example.hardstreet_admin

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/** Un evento tal como lo empuja la app (ya formateado, sin lógica aquí). */
internal data class WidgetEvent(
    /** Id de la agenda: es lo que la app necesita al tocar la fila para abrir
     *  SU detalle (0 = desconocido; el widget no adivina). */
    val id: Int,
    val title: String,
    val subtitle: String,
    /** Fecha y hora en texto ("25 oct · 17:30"). `when` es palabra
     *  reservada de Kotlin, de ahí el nombre. */
    val whenText: String,
    val time: String,
    val day: String,
    val showDay: Boolean,
    val at: Long,
)

/**
 * Widget de la pantalla de inicio: "Próximos eventos".
 *
 * El widget NO consulta nada por su cuenta (no tiene sesión ni credenciales):
 * la app le EMPUJA los eventos por el MethodChannel `hardstreet/events_widget`
 * y él solo los dibuja. Los eventos quedan guardados en SharedPreferences, así
 * que el widget sigue mostrando lo último conocido aunque la app esté cerrada.
 *
 * SE ACTUALIZA SOLO, aunque la app esté cerrada: el rótulo del día ("HOY ·
 * 16 OCT") y el descarte de lo que ya pasó se calculan AQUÍ, con la hora del
 * teléfono ([EventWidgetClock]), cada vez que el widget se repinta; además se
 * repinta por su cuenta cada [REFRESH_MS] con una alarma propia. Así no se
 * queda diciendo "HOY" el día siguiente.
 *
 * El listado es una COLECCIÓN (ListView) que llena [EventWidgetService]: así se
 * ven TODOS los eventos próximos y el usuario puede desplazarse dentro del
 * widget. Los colores salen de [EventWidgetTheme] según el modo de la APP.
 *
 * Toques:
 *  - una fila abre el DETALLE de esa agenda en la app;
 *  - el botón "+" (solo si el rol tiene "Crear" en Agendas) abre el alta de
 *    evento. Ambos viajan como extras del Intent; MainActivity se los pasa a
 *    Dart, que es quien navega.
 */
class EventWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray
    ) {
        for (id in ids) {
            manager.updateAppWidget(id, buildViews(context))
            // La lista la sirve el servicio: que vuelva a leer lo guardado.
            manager.notifyAppWidgetViewDataChanged(id, R.id.event_widget_list)
        }
        // El widget ya está colocado: que se repinte solo (por si la app no
        // vuelve a abrirse en todo el día).
        scheduleRefresh(context)
    }

    /**
     * La alarma de refresco llega como un Intent a este mismo provider. Se
     * atiende aquí porque [AppWidgetProvider] ignora las acciones que no son
     * suyas (y así no hace falta declarar otro receptor en el manifiesto).
     */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            // Renuévalo TODO con la hora actual: rótulos de día y lo que ya
            // pasó. La alarma sigue repitiéndose sola (setInexactRepeating).
            refreshAll(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // Sin widgets colocados no hay nada que repintar.
        cancelRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle
    ) {
        // Al redimensionar, re-layout (el listado se adapta al alto nuevo).
        manager.updateAppWidget(id, buildViews(context))
    }

    companion object {
        const val PREFS = "event_widget"

        /** Refresco propio del widget (rótulos y eventos vencidos). */
        const val ACTION_REFRESH = "com.example.hardstreet_admin.WIDGET_REFRESH"

        /**
         * Cada cuánto se repinta solo. 15 minutos: suficiente para que el
         * rótulo cambie de día a los pocos minutos de la medianoche, y lo
         * bastante espaciado como para no gastar batería.
         */
        const val REFRESH_MS = 15L * 60L * 1000L

        private const val REQ_REFRESH = 13
        private const val KEY_HEADER = "header"
        private const val KEY_EVENTS = "events"
        private const val KEY_DARK = "dark"
        private const val KEY_CAN_ADD = "can_add"

        // Ids de PendingIntent (distintos para el fondo, las filas y el botón).
        private const val REQ_ROOT = 10
        private const val REQ_ROW = 11
        private const val REQ_ADD = 12

        // Extras del Intent que viajan hasta Dart (ver MainActivity).
        const val EXTRA_ACTION = "hardstreet.widget.action"
        const val EXTRA_ID = "hardstreet.widget.id"
        /** Tocar una fila: la app abre el detalle de esa agenda. */
        const val ACTION_AGENDA = "agenda"
        /** Tocar "+": la app abre el alta de evento. */
        const val ACTION_NEW = "new"

        /**
         * Guarda lo que manda la app y repinta los widgets ya colocados.
         * [canAdd] = el rol del usuario puede crear agendas (decide la app:
         * solo ella conoce los permisos).
         */
        fun save(
            context: Context,
            header: String,
            eventsJson: String,
            dark: Boolean,
            canAdd: Boolean
        ) {
            prefs(context).edit()
                .putString(KEY_HEADER, header)
                .putString(KEY_EVENTS, eventsJson)
                .putBoolean(KEY_DARK, dark)
                .putBoolean(KEY_CAN_ADD, canAdd)
                .apply()
            refreshAll(context)
        }

        /** Intent con el que la alarma vuelve a este mismo provider. */
        private fun refreshIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                REQ_REFRESH,
                Intent(context, EventWidgetProvider::class.java)
                    .setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        /**
         * Pide al sistema que despierte al widget cada [REFRESH_MS]. Inexacto a
         * propósito: el sistema lo agrupa con otras alarmas (menos batería) y
         * no hace falta precisión al minuto.
         */
        fun scheduleRefresh(context: Context) {
            if (!hasWidgets(context)) return
            try {
                val alarm = context.getSystemService(Context.ALARM_SERVICE)
                    as? AlarmManager ?: return
                alarm.setInexactRepeating(
                    AlarmManager.ELAPSED_REALTIME,
                    SystemClock.elapsedRealtime() + REFRESH_MS,
                    REFRESH_MS,
                    refreshIntent(context)
                )
            } catch (_: Exception) {
                // Sin alarma el widget sigue correcto: solo se repinta menos.
            }
        }

        /** Deja de repintar (ya no hay widgets colocados). */
        fun cancelRefresh(context: Context) {
            try {
                val alarm = context.getSystemService(Context.ALARM_SERVICE)
                    as? AlarmManager ?: return
                alarm.cancel(refreshIntent(context))
            } catch (_: Exception) {
                // Nada que cancelar.
            }
        }

        /** Repinta todos los widgets de este provider. */
        fun refreshAll(context: Context) {
            scheduleRefresh(context)
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, EventWidgetProvider::class.java)
            )
            val views = buildViews(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
                manager.notifyAppWidgetViewDataChanged(id, R.id.event_widget_list)
            }
        }

        /** ¿Hay algún widget colocado en el inicio? */
        fun hasWidgets(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return manager.getAppWidgetIds(
                ComponentName(context, EventWidgetProvider::class.java)
            ).isNotEmpty()
        }

        /**
         * ¿Modo OSCURO? Manda el de la APP (lo último que empujó). Solo si la
         * app todavía no ha dicho nada (widget recién colocado, antes del
         * primer `update`) se usa el del sistema como aproximación.
         */
        internal fun isDark(context: Context): Boolean {
            val p = prefs(context)
            if (p.contains(KEY_DARK)) return p.getBoolean(KEY_DARK, false)
            val mode = context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK
            return mode == Configuration.UI_MODE_NIGHT_YES
        }

        /** ¿Se muestra el botón "Agregar agenda"? (lo decide el rol en la app) */
        internal fun canAdd(context: Context): Boolean =
            prefs(context).getBoolean(KEY_CAN_ADD, false)

        /**
         * Los eventos guardados, ya LISTOS PARA MOSTRAR: sin los que ya
         * pasaron y con el rótulo del día recalculado con la hora actual
         * (ver [EventWidgetClock]).
         */
        internal fun shownEvents(context: Context): List<WidgetEvent> =
            EventWidgetClock.fresh(readEvents(context))

        /** Eventos guardados (los que la app empujó la última vez). */
        internal fun readEvents(context: Context): List<WidgetEvent> {
            val raw = prefs(context).getString(KEY_EVENTS, null) ?: return emptyList()
            val arr = try {
                JSONArray(raw)
            } catch (_: Exception) {
                return emptyList()
            }
            val out = ArrayList<WidgetEvent>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                out.add(
                    WidgetEvent(
                        id = o.optInt("id", 0),
                        title = o.optString("title"),
                        subtitle = o.optString("subtitle"),
                        whenText = o.optString("when"),
                        time = o.optString("time"),
                        day = o.optString("day"),
                        showDay = o.optBoolean("showDay", false),
                        at = o.optLong("at", 0L),
                    )
                )
            }
            return out
        }

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Construye el RemoteViews de la tarjeta con lo guardado. */
        fun buildViews(context: Context): RemoteViews {
            val p = prefs(context)
            val dark = isDark(context)
            val views = RemoteViews(context.packageName, R.layout.event_widget)
            EventWidgetTheme.applyCard(context, views, dark)

            views.setTextViewText(
                R.id.event_widget_header,
                p.getString(KEY_HEADER, null)
                    ?: context.getString(R.string.event_widget_header)
            )

            // Contador de eventos: sale del MISMO listado que se va a mostrar,
            // así el número nunca miente respecto a lo que hay abajo.
            val count = shownEvents(context).size
            if (count > 0) {
                views.setViewVisibility(R.id.event_widget_count, View.VISIBLE)
                views.setTextViewText(
                    R.id.event_widget_count,
                    context.resources.getQuantityString(
                        R.plurals.event_widget_count,
                        count,
                        count
                    )
                )
            } else {
                views.setViewVisibility(R.id.event_widget_count, View.GONE)
            }
            // "Sin eventos próximos" vs. la lista: se decide aquí, con el MISMO
            // dato que el contador. Se evita setEmptyView porque es una llamada
            // por reflexión a AdapterView: si fallara al aplicar el RemoteViews,
            // el lanzador mostraría "problema al cargar el widget".

            // Lista de eventos: la llena EventWidgetService leyendo lo guardado.
            val serviceIntent = Intent(context, EventWidgetService::class.java).apply {
                // data única: RemoteViews cachea los adaptadores por Intent.
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.event_widget_list, serviceIntent)
            views.setViewVisibility(
                R.id.event_widget_list,
                if (count > 0) View.VISIBLE else View.GONE
            )
            views.setViewVisibility(
                R.id.event_widget_empty,
                if (count > 0) View.GONE else View.VISIBLE
            )

            // Botón "Agregar agenda": solo con permiso de crear en Agendas.
            val canAdd = canAdd(context)
            views.setViewVisibility(
                R.id.event_widget_add,
                if (canAdd) View.VISIBLE else View.GONE
            )
            if (canAdd) {
                views.setOnClickPendingIntent(
                    R.id.event_widget_add,
                    PendingIntent.getActivity(
                        context,
                        REQ_ADD,
                        openApp(context, ACTION_NEW, 0),
                        PendingIntent.FLAG_UPDATE_CURRENT or
                            PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }

            // Tocar un evento (o el encabezado) trae la app al frente. El
            // template de la lista DEBE ser mutable: Android le aplica encima el
            // "fill-in intent" que pone cada fila (ahí viaja el id de la agenda).
            val rowFlags =
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            views.setPendingIntentTemplate(
                R.id.event_widget_list,
                PendingIntent.getActivity(
                    context,
                    REQ_ROW,
                    openApp(context, ACTION_AGENDA, 0),
                    rowFlags
                )
            )
            val rootFlags =
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            views.setOnClickPendingIntent(
                R.id.event_widget_root,
                PendingIntent.getActivity(context, REQ_ROOT, openApp(context), rootFlags)
            )
            return views
        }

        /** Intent que trae la app al frente llevando QUÉ se tocó en el widget. */
        private fun openApp(
            context: Context,
            action: String? = null,
            id: Int = 0
        ): Intent =
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (action != null) {
                    putExtra(EXTRA_ACTION, action)
                    putExtra(EXTRA_ID, id)
                }
            }
    }
}
