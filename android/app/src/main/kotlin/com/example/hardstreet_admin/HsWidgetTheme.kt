package com.example.hardstreet_admin

import android.content.Context
import android.widget.RemoteViews

/**
 * Pintado de los widgets de inicio «Notas» y «Avisos».
 *
 * USA LOS MISMOS recursos del widget «Próximos eventos» (fondos, pastilla,
 * colores): las tres tarjetas comparten la paleta EXACTA de AppTheme
 * (lib/theme.dart) y su modo lo empuja la APP —no el tema del sistema— en
 * cada `update` del canal (bandera `dark`). Véase EventWidgetTheme, que
 * explica el porqué (no hay recursos con calificador `-night`).
 *
 * Lo único propio de estos widgets son los IDS de sus vistas, que llegan por
 * parámetro; el listado de filas reutiliza DIRECTAMENTE el layout y las ids
 * de event_widget_row.xml (EventWidgetTheme.applyRow lo pinta igual).
 */
internal object HsWidgetTheme {

    /** Fondo, encabezado, contador, separador y texto vacío de la tarjeta. */
    fun applyCard(
        context: Context,
        views: RemoteViews,
        dark: Boolean,
        root: Int,
        header: Int,
        count: Int,
        divider: Int,
        empty: Int,
    ) {
        views.setInt(
            root,
            "setBackgroundResource",
            EventWidgetTheme.cardBackground(dark),
        )
        views.setTextColor(header, EventWidgetTheme.accent(context, dark))
        views.setInt(
            count,
            "setBackgroundResource",
            EventWidgetTheme.badgeBackground(dark),
        )
        views.setTextColor(count, EventWidgetTheme.accent(context, dark))
        views.setInt(
            divider,
            "setBackgroundColor",
            EventWidgetTheme.divider(context, dark),
        )
        views.setTextColor(empty, EventWidgetTheme.muted(context, dark))
    }
}
