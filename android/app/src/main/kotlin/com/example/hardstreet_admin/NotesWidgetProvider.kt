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
 * Widget de la pantalla de inicio: «Notas».
 *
 * Igual que el de «Próximos eventos» ([EventWidgetProvider]): NO consulta
 * nada por su cuenta (sin sesión ni red) — la app EMPUJA las notas recientes
 * por el canal `hardstreet/notes_widget` y él dibuja. Lo guardado queda en
 * SharedPreferences, así que el widget sigue mostrando lo último conocido
 * aunque la app esté cerrada.
 *
 * El listado es una COLECCIÓN (ListView) llenada por
 * [NotesWidgetService]; se reutiliza el layout event_widget_row.xml, así que
 * el tema de fila también lo pone EventWidgetTheme.
 *
 * Toques: una fila abre ESA nota en la app y el botón «+» (solo si el rol
 * tiene «Crear» en Notas) abre el alta. Ambos viajan como extras del Intent;
 * MainActivity se los pasa a Dart, quien decide navegar (el toque se publica
 * por el canal como `note` / `note_new`).
 */
class NotesWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray
    ) {
        for (id in ids) {
            manager.updateAppWidget(id, buildViews(context))
            manager.notifyAppWidgetViewDataChanged(id, R.id.notes_widget_list)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle
    ) {
        // Al redimensionar: releer lo guardado y repetir el layout.
        manager.updateAppWidget(id, buildViews(context))
    }

    companion object {
        const val PREFS = "notes_widget"

        private val KEY_HEADER = "header"
        private val KEY_NOTES = "notes"
        private val KEY_DARK = "dark"
        private val KEY_CAN_CREATE = "can_create"

        // Ids de PendingIntent: filas y botón «+» (del provider de eventos ya
        // está ocupado el 10-13: rango nuevo para no chocar con ninguno).
        private const val REQ_ROW = 20
        private const val REQ_ADD = 21

        // Reutiliza los MISMOS extras del Intent que el widget de eventos:
        // MainActivity no necesita distinguir de dónde vino el toque.
        const val ACTION_NOTE = "note"
        const val ACTION_NOTE_NEW = "note_new"

        /** Guarda lo que empuja la app y repinta los widgets colocados. */
        fun save(
            context: Context,
            header: String,
            notesJson: String,
            dark: Boolean,
            canCreate: Boolean
        ) {
            prefs(context).edit()
                .putString(KEY_HEADER, header)
                .putString(KEY_NOTES, notesJson)
                .putBoolean(KEY_DARK, dark)
                .putBoolean(KEY_CAN_CREATE, canCreate)
                .apply()
            refreshAll(context)
        }

        /** Repinta todos los widgets de este provider. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, NotesWidgetProvider::class.java)
            )
            val views = buildViews(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
                manager.notifyAppWidgetViewDataChanged(id, R.id.notes_widget_list)
            }
        }

        /** ¿Hay widget colocado? (la app pregunta si hace falta empujar) */
        fun hasWidgets(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return manager.getAppWidgetIds(
                ComponentName(context, NotesWidgetProvider::class.java)
            ).isNotEmpty()
        }

        internal fun isDark(context: Context): Boolean =
            prefs(context).getBoolean(KEY_DARK, false)

        /** Notas guardadas (las que la app empujó la última vez). */
        internal fun readNotes(context: Context): List<WidgetNote> {
            val raw = prefs(context).getString(KEY_NOTES, null) ?: return emptyList()
            val arr = try {
                JSONArray(raw)
            } catch (_: Exception) {
                return emptyList()
            }
            val out = ArrayList<WidgetNote>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                out.add(
                    WidgetNote(
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
            val views = RemoteViews(context.packageName, R.layout.notes_widget)
            HsWidgetTheme.applyCard(
                context, views, dark,
                root = R.id.notes_widget_root,
                header = R.id.notes_widget_header,
                count = R.id.notes_widget_count,
                divider = R.id.notes_widget_divider,
                empty = R.id.notes_widget_empty,
            )

            views.setTextViewText(
                R.id.notes_widget_header,
                p.getString(KEY_HEADER, null)
                    ?: context.getString(R.string.notes_widget_header)
            )

            val notes = readNotes(context)
            val count = notes.size
            if (count > 0) {
                views.setViewVisibility(R.id.notes_widget_count, View.VISIBLE)
                views.setTextViewText(
                    R.id.notes_widget_count,
                    context.resources.getQuantityString(
                        R.plurals.notes_widget_count, count, count
                    )
                )
            } else {
                views.setViewVisibility(R.id.notes_widget_count, View.GONE)
            }

            // Lista: la llena NotesWidgetService leyendo lo guardado.
            val serviceIntent = Intent(context, NotesWidgetService::class.java).apply {
                // data única: RemoteViews cachea el adaptador por Intent.
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.notes_widget_list, serviceIntent)
            views.setViewVisibility(
                R.id.notes_widget_list,
                if (count > 0) View.VISIBLE else View.GONE
            )
            views.setViewVisibility(
                R.id.notes_widget_empty,
                if (count > 0) View.GONE else View.VISIBLE
            )

            // Botón «Nueva nota»: solo si el rol puede crear (decide la app).
            val canCreate = prefs(context).getBoolean(KEY_CAN_CREATE, false)
            views.setViewVisibility(
                R.id.notes_widget_add,
                if (canCreate) View.VISIBLE else View.GONE
            )
            if (canCreate) {
                views.setOnClickPendingIntent(
                    R.id.notes_widget_add,
                    PendingIntent.getActivity(
                        context,
                        REQ_ADD,
                        openApp(context, ACTION_NOTE_NEW, 0),
                        PendingIntent.FLAG_UPDATE_CURRENT or
                            PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }

            // Tocar una fila: el template DEBE ser mutable (el fill-in intent
            // de cada fila viaja el id de la nota).
            views.setPendingIntentTemplate(
                R.id.notes_widget_list,
                PendingIntent.getActivity(
                    context,
                    REQ_ROW,
                    openApp(context, ACTION_NOTE, 0),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
            )
            views.setOnClickPendingIntent(
                R.id.notes_widget_root,
                PendingIntent.getActivity(
                    context,
                    22,
                    openApp(context),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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

/** Una nota tal como la empuja la app (ya formateada, sin lógica aquí). */
internal data class WidgetNote(
    /** Id de la nota (0 = desconocido). */
    val id: Int,
    val title: String,
    val sub: String,
    val whenText: String,
)
