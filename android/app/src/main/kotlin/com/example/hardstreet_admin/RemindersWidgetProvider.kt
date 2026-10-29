package com.example.hardstreet_admin

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * Widget de la pantalla de inicio: «Avisos».
 *
 * Igual que los demás widgets del inicio: NO consulta nada por su cuenta —
 * la app EMPUJA los avisos recientes por el canal `hardstreet/reminders_widget`
 * y él dibuja. Los avisos quedan en SharedPreferences, así que el widget
 * sigue mostrando lo último conocido aunque la app esté cerrada.
 *
 * El listado es una COLECCIÓN (ListView) llenada por RemindersWidgetService
 * (reutiliza el layout event_widget_row.xml). Los avisos SIN LEER llegan ya
 * marcados con «● » en el título: la app decide, el widget solo dibuja.
 *
 * Tocar una fila (o la tarjeta) TRAE LA APP AL FRENTE: los avisos pueden
 * venir de varias tablas (agenda, impresión, paquete) y el detalle se lee
 * en la campanita de la app, no todos son un evento abrible.
 */
class RemindersWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray
    ) {
        for (id in ids) {
            manager.updateAppWidget(id, buildViews(context))
            manager.notifyAppWidgetViewDataChanged(id, R.id.reminders_widget_list)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle
    ) {
        manager.updateAppWidget(id, buildViews(context))
    }

    companion object {
        const val PREFS = "reminders_widget"

        private val KEY_HEADER = "header"
        private val KEY_AVISOS = "avisos"
        private val KEY_DARK = "dark"

        // Ids de PendingIntent: ni siquiera comparten rango con otros
        // providers (eventos usa el 10-13 y notas el 20-22).
        private const val REQ_ROOT = 30

        const val ACTION_AVISO = "aviso"

        /** Guarda lo que empuja la app y repinta los widgets colocados. */
        fun save(
            context: Context,
            header: String,
            avisosJson: String,
            dark: Boolean
        ) {
            prefs(context).edit()
                .putString(KEY_HEADER, header)
                .putString(KEY_AVISOS, avisosJson)
                .putBoolean(KEY_DARK, dark)
                .apply()
            refreshAll(context)
        }

        /** Repinta todos los widgets de este provider. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, RemindersWidgetProvider::class.java)
            )
            val views = buildViews(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
                manager.notifyAppWidgetViewDataChanged(id, R.id.reminders_widget_list)
            }
        }

        /** ¿Hay widget colocado? */
        fun hasWidgets(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return manager.getAppWidgetIds(
                ComponentName(context, RemindersWidgetProvider::class.java)
            ).isNotEmpty()
        }

        internal fun isDark(context: Context): Boolean =
            prefs(context).getBoolean(KEY_DARK, false)

        /** Avisos guardados (los que la app empujó la última vez). */
        internal fun readAvisos(context: Context): List<WidgetAviso> {
            val raw = prefs(context).getString(KEY_AVISOS, null) ?: return emptyList()
            val arr = try {
                JSONArray(raw)
            } catch (_: Exception) {
                return emptyList()
            }
            val out = ArrayList<WidgetAviso>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                out.add(
                    WidgetAviso(
                        id = o.optInt("id", 0),
                        title = o.optString("title"),
                        sub = o.optString("sub"),
                        whenText = o.optString("when"),
                    )
                )
            }
            return out
        }

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** RemoteViews de la tarjeta con lo guardado. */
        fun buildViews(context: Context): RemoteViews {
            val p = prefs(context)
            val dark = isDark(context)
            val views = RemoteViews(context.packageName, R.layout.reminders_widget)
            HsWidgetTheme.applyCard(
                context, views, dark,
                root = R.id.reminders_widget_root,
                header = R.id.reminders_widget_header,
                count = R.id.reminders_widget_count,
                divider = R.id.reminders_widget_divider,
                empty = R.id.reminders_widget_empty,
            )

            views.setTextViewText(
                R.id.reminders_widget_header,
                p.getString(KEY_HEADER, null)
                    ?: context.getString(R.string.reminders_widget_header)
            )

            val avisos = readAvisos(context)
            val count = avisos.size
            if (count > 0) {
                views.setViewVisibility(R.id.reminders_widget_count, View.VISIBLE)
                views.setTextViewText(
                    R.id.reminders_widget_count,
                    context.resources.getQuantityString(
                        R.plurals.reminders_widget_count, count, count
                    )
                )
            } else {
                views.setViewVisibility(R.id.reminders_widget_count, View.GONE)
            }

            // Lista: la llena RemindersWidgetService leyendo lo guardado.
            val serviceIntent = Intent(context, RemindersWidgetService::class.java).apply {
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.reminders_widget_list, serviceIntent)
            views.setViewVisibility(
                R.id.reminders_widget_list,
                if (count > 0) View.VISIBLE else View.GONE
            )
            views.setViewVisibility(
                R.id.reminders_widget_empty,
                if (count > 0) View.GONE else View.VISIBLE
            )

            // Toque: filas y tarjeta abren la app (los avisos no son todos
            // un evento abrible; el detalle vive en la campanita).
            val immutable = PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
            views.setOnClickPendingIntent(
                R.id.reminders_widget_root,
                PendingIntent.getActivity(
                    context, REQ_ROOT, openApp(context), immutable
                )
            )
            views.setPendingIntentTemplate(
                R.id.reminders_widget_list,
                PendingIntent.getActivity(
                    context,
                    REQ_ROOT + 1,
                    openApp(context, ACTION_AVISO, 0),
                    immutable
                )
            )
            return views
        }

        /** Trae la app al frente llevando qué se tocó. */
        private fun openApp(
            context: Context,
            action: String? = null,
            id: Int = 0
        ): Intent =
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (action != null) {
                    putExtra(EventWidgetProvider.EXTRA_ACTION, action)
                    putExtra(EventWidgetProvider.EXTRA_ID, id)
                }
            }
    }
}

/** Un aviso tal como lo empuja la app (ya formateado, sin lógica aquí). */
internal data class WidgetAviso(
    val id: Int,
    val title: String,
    val sub: String,
    val whenText: String,
)
