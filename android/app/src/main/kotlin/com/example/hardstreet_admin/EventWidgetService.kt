package com.example.hardstreet_admin

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Fuente de datos de la LISTA del widget "Próximos eventos".
 *
 * RemoteViews normales no admiten listas dinámicas; esta es la vía oficial
 * (RemoteViewsService + RemoteViewsFactory) y es lo que permite mostrar TODA la
 * agenda próxima y desplazarse dentro del widget.
 *
 * No consulta nada: lee los eventos que la app empujó y los pinta agrupados por
 * día — el rótulo de fecha ("HOY · 16 OCT") aparece SOLO en el primer evento de
 * cada jornada.
 *
 * El rótulo NO se copia de lo que empujó la app: se recalcula aquí con la hora
 * del teléfono ([EventWidgetClock]) y se descarta lo que ya pasó, así el widget
 * sigue diciendo la verdad aunque la app lleve días cerrada.
 */
class EventWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        EventRowsFactory(applicationContext)
}

private class EventRowsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var rows: List<WidgetEvent> = emptyList()
    private var dark = false

    // Los datos llegan en onDataSetChanged (que es lo que dispara el provider).
    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        rows = EventWidgetProvider.shownEvents(context)
        dark = EventWidgetProvider.isDark(context)
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.event_widget_row)
        EventWidgetTheme.applyRow(context, row, dark)
        val event = rows.getOrNull(position) ?: return row

        // Rótulo del DÍA: solo en el primer evento de cada fecha.
        val showDay = event.showDay && event.day.isNotEmpty()
        row.setViewVisibility(
            R.id.event_widget_row_day,
            if (showDay) View.VISIBLE else View.GONE
        )
        row.setTextViewText(R.id.event_widget_row_day, event.day)
        row.setTextViewText(R.id.event_widget_row_title, event.title)

        row.setViewVisibility(
            R.id.event_widget_row_sub,
            if (event.subtitle.isEmpty()) View.GONE else View.VISIBLE
        )
        row.setTextViewText(R.id.event_widget_row_sub, event.subtitle)

        // Con rótulo de día la fila muestra SOLO la hora; sin él (carga vieja)
        // se queda con la fecha completa de siempre.
        row.setTextViewText(
            R.id.event_widget_row_time,
            if (showDay && event.time.isNotEmpty()) event.time else event.whenText
        )

        // Tocar el evento abre SU detalle en la app: el PendingIntent lo pone
        // el provider y este "fill-in intent" le añade qué agenda se tocó.
        // (Los avisos de respaldo no traen id: entonces solo se abre la app.)
        val tap = Intent()
        if (event.id > 0) {
            tap.putExtra(
                EventWidgetProvider.EXTRA_ACTION,
                EventWidgetProvider.ACTION_AGENDA
            )
            tap.putExtra(EventWidgetProvider.EXTRA_ID, event.id)
        }
        row.setOnClickFillInIntent(R.id.event_widget_row_root, tap)
        return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
