package com.example.hardstreet_admin

import android.app.job.JobParameters
import android.app.job.JobService

/**
 * AVISOS CON LA APP CERRADA: la vía que el SISTEMA garantiza.
 *
 * `PackageNotificationsReceiver` despierta cada minuto con una alarma, pero los
 * teléfonos (y sobre todo las capas de fabricante: Xiaomi, Huawei, Samsung…)
 * aplazan o cancelan las alarmas de una app que el usuario sacó de recientes.
 * Resultado: con la app cerrada no llegaba ningún aviso hasta volver a abrirla.
 *
 * Este JobService es la red de seguridad: lo programa `JobScheduler`, que es del
 * SISTEMA (no de la app) y lo vuelve a lanzar aunque el proceso se haya muerto,
 * aunque el teléfono se haya reiniciado (`setPersisted`) y en las ventanas en
 * que el equipo sale de Doze. El trabajo es el MISMO que hace la alarma:
 * consultar los avisos y publicar los nuevos.
 *
 * Cada 15 minutos es el mínimo que acepta Android para un trabajo periódico;
 * mientras la app está viva, la alarma de un minuto sigue dando la respuesta
 * rápida.
 */
class PackageNotificationsJobService : JobService() {

    override fun onStartJob(params: JobParameters?): Boolean {
        // La consulta hace red: fuera del hilo principal. Se devuelve `true`
        // (el trabajo sigue vivo) y se avisa al sistema al terminar.
        Thread {
            try {
                PackageNotificationsReceiver.pollNow(this)
            } catch (_: Exception) {
                // Mejor esfuerzo: la próxima pasada reintenta.
            } finally {
                jobFinished(params, false)
            }
        }.start()
        return true
    }

    /**
     * El sistema necesita el hilo (por ejemplo, por falta de red). Se pide que
     * NO se reintente: es un trabajo periódico y ya habrá otra pasada.
     */
    override fun onStopJob(params: JobParameters?): Boolean = false
}
