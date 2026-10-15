package com.example.hardstreet_admin

import java.util.Calendar
import kotlin.math.roundToLong

/**
 * FECHA DEL WIDGET calculada AQUÍ, no en la app.
 *
 * La app empuja cada evento con su instante (`at`, epoch en ms) y el rótulo del
 * día. El rótulo que viene de la app se calcula cuando ella está corriendo: si
 * el teléfono pasa la medianoche con la app cerrada, un evento que era "HOY"
 * seguiría diciendo "HOY" al día siguiente. Por eso el widget NO usa el rótulo
 * empujado: lo recalcula con la hora del teléfono cada vez que se repinta (y se
 * repinta solo cada [EventWidgetProvider.REFRESH_MS]).
 *
 * El formato es el MISMO de la app (lib/hs_format.dart, `hsDayLabel`):
 *
 *   HOY · 16 OCT   /   MAÑANA · 17 OCT   /   VIE 18 OCT
 *
 * Siempre lleva la fecha escrita, así el rótulo nunca miente aunque el widget
 * tarde en repintarse.
 */
internal object EventWidgetClock {

    /** Meses en español (los mismos de la app). */
    private val MONTHS = arrayOf(
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
    )

    /** Días en español, empezando en lunes (así los numera Dart: 1 = lunes). */
    private val WEEKDAYS = arrayOf(
        "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"
    )

    /** Margen para no borrar un evento que está EN CURSO (igual que la app). */
    const val GRACE_MS = 60L * 60L * 1000L

    /**
     * Eventos que el widget debe mostrar AHORA: se descarta lo que ya pasó y se
     * recalcula el rótulo de cada jornada (visible solo en su primer evento).
     *
     * Los eventos sin `at` (carga vieja, o avisos sin fecha) se dejan tal cual
     * llegaron: sin instante no hay forma de saber si siguen vigentes.
     */
    fun fresh(
        events: List<WidgetEvent>,
        now: Long = System.currentTimeMillis()
    ): List<WidgetEvent> {
        val limit = now - GRACE_MS
        val out = ArrayList<WidgetEvent>(events.size)
        var lastDay = ""
        for (e in events) {
            val hasDate = e.at > 0
            if (hasDate && e.at < limit) continue // ya pasó: fuera del widget
            val day = if (hasDate) dayLabel(e.at, now) else e.day
            val show = if (hasDate) day.isNotEmpty() && day != lastDay else e.showDay
            out.add(e.copy(day = day, showDay = show))
            if (day.isNotEmpty()) lastDay = day
        }
        return out
    }

    /**
     * Rótulo de una jornada: `HOY · 16 OCT`, `MAÑANA · 17 OCT` o `VIE 18 OCT`.
     * [now] se puede fijar para probarlo.
     */
    fun dayLabel(at: Long, now: Long = System.currentTimeMillis()): String {
        val at_c = Calendar.getInstance().apply { timeInMillis = at }
        val month = MONTHS[at_c.get(Calendar.MONTH)]
        val stamp = "${at_c.get(Calendar.DAY_OF_MONTH)} ${month.take(3).uppercase()}"
        return when (daysBetween(at, now)) {
            0L -> "HOY · $stamp"
            1L -> "MAÑANA · $stamp"
            else -> "${weekdayOf(at_c)} $stamp"
        }
    }

    /** Días COMPLETOS de [from] a [to] (0 = el mismo día, 1 = mañana). */
    private fun daysBetween(from: Long, to: Long): Long {
        val a = Calendar.getInstance().apply { timeInMillis = from }
        val b = Calendar.getInstance().apply { timeInMillis = to }
        a.set(Calendar.HOUR_OF_DAY, 0)
        a.set(Calendar.MINUTE, 0)
        a.set(Calendar.SECOND, 0)
        a.set(Calendar.MILLISECOND, 0)
        b.set(Calendar.HOUR_OF_DAY, 0)
        b.set(Calendar.MINUTE, 0)
        b.set(Calendar.SECOND, 0)
        b.set(Calendar.MILLISECOND, 0)
        // Redondeo: los cambios de horario (23/25 h) no deben correr el día.
        return ((a.timeInMillis - b.timeInMillis) / 86_400_000.0).roundToLong()
    }

    /** Abreviatura de 3 letras del día, en mayúsculas ("MIÉ", "SÁB"). */
    private fun weekdayOf(calendar: Calendar): String {
        // Calendar: DOMINGO = 1 … SÁBADO = 7 → índice 0 = lunes.
        val index = (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7
        return WEEKDAYS[index].take(3).uppercase()
    }
}
