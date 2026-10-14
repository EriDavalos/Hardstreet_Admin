package com.example.hardstreet_admin

import android.content.Context
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

/**
 * Paleta y pintado del widget "Próximos eventos".
 *
 * El widget NO sigue el tema del sistema: sigue el MODO DE LA APP, que le llega
 * en cada `update` del canal `hardstreet/events_widget` (bandera `dark`). Por
 * eso aquí no se usan recursos con calificador `-night` —esos seguirían al
 * sistema—: cada color tiene su nombre propio y se elige en tiempo de ejecución.
 *
 * Cada color de res/values/colors.xml es el MISMO que usa AppTheme del lado de
 * la app (tarjeta = cardColor, textos = onSurface/onSurfaceVariant, acento =
 * primary): el widget se ve igual que la app en claro y en oscuro.
 */
internal object EventWidgetTheme {

    private fun color(context: Context, resId: Int): Int =
        ContextCompat.getColor(context, resId)

    fun cardBackground(dark: Boolean): Int =
        if (dark) R.drawable.event_widget_bg_dark else R.drawable.event_widget_bg

    fun badgeBackground(dark: Boolean): Int =
        if (dark) R.drawable.event_widget_badge_dark else R.drawable.event_widget_badge

    /** Pastilla del botón "Agregar agenda". */
    fun addBackground(dark: Boolean): Int =
        if (dark) R.drawable.event_widget_add_bg_dark else R.drawable.event_widget_add_bg

    /** Azul de la marca (encabezado y rótulo de día). */
    fun accent(context: Context, dark: Boolean): Int = color(
        context,
        if (dark) R.color.event_widget_accent_dark else R.color.event_widget_accent,
    )

    /** Titular de cada evento. */
    fun title(context: Context, dark: Boolean): Int = color(
        context,
        if (dark) R.color.event_widget_title_dark else R.color.event_widget_title,
    )

    /** Cliente · servicio. */
    fun muted(context: Context, dark: Boolean): Int = color(
        context,
        if (dark) R.color.event_widget_muted_dark else R.color.event_widget_muted,
    )

    /** Hora del evento. */
    fun time(context: Context, dark: Boolean): Int = color(
        context,
        if (dark) R.color.event_widget_time_dark else R.color.event_widget_time,
    )

    fun divider(context: Context, dark: Boolean): Int = color(
        context,
        if (dark) R.color.event_widget_divider_dark else R.color.event_widget_divider,
    )

    /** Fondo, encabezado, contador y separador de la tarjeta. */
    fun applyCard(context: Context, views: RemoteViews, dark: Boolean) {
        views.setInt(
            R.id.event_widget_root,
            "setBackgroundResource",
            cardBackground(dark),
        )
        views.setTextColor(R.id.event_widget_header, accent(context, dark))
        views.setInt(
            R.id.event_widget_count,
            "setBackgroundResource",
            badgeBackground(dark),
        )
        views.setInt(
            R.id.event_widget_add,
            "setBackgroundResource",
            addBackground(dark),
        )
        views.setTextColor(R.id.event_widget_count, accent(context, dark))
        views.setInt(
            R.id.event_widget_divider,
            "setBackgroundColor",
            divider(context, dark),
        )
        views.setTextColor(R.id.event_widget_empty, muted(context, dark))
    }

    /** Colores de una fila del listado. */
    fun applyRow(context: Context, row: RemoteViews, dark: Boolean) {
        row.setTextColor(R.id.event_widget_row_day, accent(context, dark))
        row.setTextColor(R.id.event_widget_row_title, title(context, dark))
        row.setTextColor(R.id.event_widget_row_time, time(context, dark))
        row.setTextColor(R.id.event_widget_row_sub, muted(context, dark))
    }
}
