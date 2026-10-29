package com.example.hardstreet_admin

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Fuente de datos de la LISTA del widget «Notas».
 *
 * Igual que en «Próximos eventos»: RemoteViews normales no admiten listas
 * dinámicas; vía oficial RemoteViewsService + Factory. No consulta nada:
 * lee las notas que la app empujó ([NotesWidgetProvider.readNotes]) y las
 * pinta en ORDEN (fijadas primero, luego la más reciente arriba).
 *
 * REUTILIZA el layout event_widget_row.xml (título + fecha a la derecha +
 * vista previa debajo): el tema por fila lo pone EventWidgetTheme como en
 * el widget de eventos.
 */
class NotesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NoteRowsFactory(applicationContext)
}

private class NoteRowsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var rows: List<WidgetNote> = emptyList()
    private var dark = false

    override fun onCreate() = Unit

    // Los datos llegan en onDataSetChanged (lo dispara el provider).
    override fun onDataSetChanged() {
        rows = NotesWidgetProvider.readNotes(context)
        dark = NotesWidgetProvider.isDark(context)
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.event_widget_row)
        // Mismo tema de fila que el widget de eventos (misma paleta).
        EventWidgetTheme.applyRow(context, row, dark)
        val note = rows.getOrNull(position) ?: return row

        // El layout de fila viene con el rótulo de día para agendas: aquí no
        // se usa, se queda oculto tal y como está en el layout.
        row.setTextViewText(R.id.event_widget_row_title, note.title)
        row.setViewVisibility(R.id.event_widget_row_day, View.GONE)
        row.setTextViewText(R.id.event_widget_row_time, note.whenText)
        row.setViewVisibility(
            R.id.event_widget_row_sub,
            if (note.sub.isEmpty()) View.GONE else View.VISIBLE
        )
        row.setTextViewText(R.id.event_widget_row_sub, note.sub)

        // Tocar la fila abre ESA nota: el PendingIntent lo pone el provider y
        // este fill-in intent le añade el id (0 = solo abrir la app).
        val tap = Intent()
        if (note.id > 0) {
            tap.putExtra(
                EventWidgetProvider.EXTRA_ACTION,
                NotesWidgetProvider.ACTION_NOTE
            )
            tap.putExtra(EventWidgetProvider.EXTRA_ID, note.id)
        }
        row.setOnClickFillInIntent(R.id.event_widget_row_root, tap)
        return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
