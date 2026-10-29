package com.example.hardstreet_admin

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Fuente de datos de la LISTA del widget «Avisos».
 *
 * Igual que en «Próximos eventos»: vía oficial RemoteViewsService + Factory.
 * No consulta nada: lee los avisos que la app empujó
 * ([RemindersWidgetProvider.readAvisos]) y los pinta en ORDEN (el más
 * reciente arriba; los SIN LEER ya llegan con «● » en el título: eso lo pinta
 * la app al formatear).
 *
 * REUTILIZA el layout event_widget_row.xml: el tema por fila lo pone
 * EventWidgetTheme como en el widget de eventos.
 */
class RemindersWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        AvisoRowsFactory(applicationContext)
}

private class AvisoRowsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var rows: List<WidgetAviso> = emptyList()
    private var dark = false

    override fun onCreate() = Unit

    // Los datos llegan en onDataSetChanged (lo dispara el provider).
    override fun onDataSetChanged() {
        rows = RemindersWidgetProvider.readAvisos(context)
        dark = RemindersWidgetProvider.isDark(context)
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.event_widget_row)
        // Mismo tema de fila que el widget de eventos (misma paleta).
        EventWidgetTheme.applyRow(context, row, dark)
        val aviso = rows.getOrNull(position) ?: return row

        // El layout de fila viene con rótulo de día para agendas: aquí no se
        // usa, se queda oculto tal y como está en el layout.
        row.setViewVisibility(R.id.event_widget_row_day, View.GONE)
        row.setTextViewText(R.id.event_widget_row_title, aviso.title)
        row.setTextViewText(R.id.event_widget_row_time, aviso.whenText)
        row.setViewVisibility(
            R.id.event_widget_row_sub,
            if (aviso.sub.isEmpty()) View.GONE else View.VISIBLE
        )
        row.setTextViewText(R.id.event_widget_row_sub, aviso.sub)

        // Tocar un aviso trae la app al frente (sin id: el detalle vive en la
        // campanita, no todos los avisos son un evento abrible).
        row.setOnClickFillInIntent(R.id.event_widget_row_root, Intent())
        return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
