package com.example.hardstreet_admin

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "hardstreet/installer"

    /** Widget de "próximos eventos" (la app empuja los datos). */
    private val widgetChannelName = "hardstreet/events_widget"

    /** Guardar descargas del Drive en la carpeta pública de Descargas. */
    private val downloadsChannelName = "hardstreet/downloads"

    private var widgetChannel: MethodChannel? = null

    /**
     * Acción pendiente que pidió el WIDGET (tocar un evento o "Agregar
     * agenda"). Se guarda cuando el widget lanza la app y Dart la consume por
     * el canal: así el toque llega aunque la app estuviera cerrada.
     */
    private var pendingWidgetTap: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Arranque en frío lanzado desde el widget: la acción queda pendiente
        // hasta que Dart pregunte (en ese momento el engine aún no existe).
        pendingWidgetTap = widgetTapFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // La app YA está corriendo (puede estar en segundo plano): se le
        // empuja la acción de inmediato.
        val tap = widgetTapFrom(intent) ?: return
        pendingWidgetTap = tap
        pushWidgetTap(tap)
    }

    /** Traduce los extras del Intent a la acción que entiende Dart. */
    private fun widgetTapFrom(intent: Intent?): Map<String, Any>? {
        val action = intent?.getStringExtra(EventWidgetProvider.EXTRA_ACTION) ?: return null
        val id = intent.getIntExtra(EventWidgetProvider.EXTRA_ID, 0)
        return mapOf("action" to action, "id" to id)
    }

    /** Manda la acción a Dart (que navega). Silencioso si aún no hay handler. */
    private fun pushWidgetTap(tap: Map<String, Any>) {
        val channel = widgetChannel ?: return
        channel.invokeMethod(
            "onWidgetTap",
            tap,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // Ya la tiene Dart: no debe volver a consumirse al arrancar.
                    if (pendingWidgetTap == tap) pendingWidgetTap = null
                }

                override fun error(code: String, message: String?, details: Any?) = Unit

                override fun notImplemented() = Unit
            }
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
        widgetChannel = channel
        channel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Guarda los eventos y repinta el widget del inicio.
                    // `dark` = modo de la APP: el widget se pinta como ella, no
                    // como el tema del sistema. `canAdd` = el rol puede crear
                    // agendas (decide la app), así el botón "+" solo aparece
                    // para quien de verdad puede usarlo.
                    "update" -> {
                        val header = call.argument<String>("header") ?: "Próximos eventos"
                        @Suppress("UNCHECKED_CAST")
                        val events = call.argument<List<Any?>>("events") ?: emptyList()
                        val dark = call.argument<Boolean>("dark") ?: false
                        val canAdd = call.argument<Boolean>("canAdd") ?: false
                        val arr = JSONArray()
                        for (item in events) {
                            if (item is Map<*, *>) arr.put(JSONObject(item))
                        }
                        EventWidgetProvider.save(this, header, arr.toString(), dark, canAdd)
                        result.success(true)
                    }
                    // Android 8+: pide al lanzador colocar el widget.
                    "requestPin" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val manager = AppWidgetManager.getInstance(this)
                            val provider = ComponentName(this, EventWidgetProvider::class.java)
                            if (manager.isRequestPinAppWidgetSupported) {
                                result.success(manager.requestPinAppWidget(provider, null, null))
                            } else {
                                // El lanzador no lo soporta: si ya está colocado
                                // basta con refrescarlo.
                                EventWidgetProvider.refreshAll(this)
                                result.success(EventWidgetProvider.hasWidgets(this))
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "isVisible" -> result.success(EventWidgetProvider.hasWidgets(this))
                    // ¿El widget lanzó la app con una acción? (arranque en frío)
                    "consumeTap" -> {
                        val tap = pendingWidgetTap
                        pendingWidgetTap = null
                        result.success(tap)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Abre el instalador del sistema con el .apk descargado.
                    // El usuario confirma "Instalar" ahí: Android no permite
                    // instalar sin esa confirmación explícita.
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("ARGS", "Falta la ruta del APK", null)
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("MISSING", "El APK no existe: $path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = contentUriFor(file)
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LAUNCH", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Descargas del Drive: Android no tiene diálogo "Guardar como" en
        // file_selector (getSavePath lanzaba UnimplementedError), así que el
        // archivo se deja en la carpeta pública de DESCARGAS del dispositivo.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name") ?: "hardstreet"
                        if (path.isNullOrEmpty()) {
                            result.error("ARGS", "Falta el archivo a guardar", null)
                            return@setMethodCallHandler
                        }
                        val source = File(path)
                        if (!source.exists()) {
                            result.error("MISSING", "El archivo ya no existe: $path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(source, name))
                        } catch (e: Exception) {
                            result.error("SAVE", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Copia [source] a la carpeta de DESCARGAS del dispositivo y devuelve una
     * etiqueta legible ("Descargas/archivo.zip"), o null si no se pudo.
     *
     * Android 10+ (API 29): MediaStore, sin permisos y sin dejar archivos
     * "pendientes". Android 9 y anteriores: escritura directa en la carpeta
     * pública (si el sistema la niega, se usa la carpeta de la app, que no
     * necesita permisos, para no perder la descarga).
     */
    private fun saveToDownloads(source: File, displayName: String): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                put(MediaStore.Downloads.MIME_TYPE, mimeOf(displayName))
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val uri = contentResolver.insert(collection, values) ?: return null
            try {
                val out = contentResolver.openOutputStream(uri)
                    ?: throw IllegalStateException("No se pudo abrir el destino")
                out.use { destination ->
                    source.inputStream().use { input -> input.copyTo(destination) }
                }
            } catch (e: Exception) {
                // Si falla a medias no se deja un archivo a medias en Descargas.
                contentResolver.delete(uri, null, null)
                throw e
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return "Descargas/$displayName"
        }

        // Android 9 y anteriores.
        val fallback = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        @Suppress("DEPRECATION")
        val public =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val targets = listOfNotNull(public, fallback)
        var lastError: Exception? = null
        for ((index, dir) in targets.withIndex()) {
            try {
                if (!dir.exists()) dir.mkdirs()
                val dest = uniqueFile(dir, displayName)
                source.inputStream().use { input ->
                    dest.outputStream().use { output -> input.copyTo(output) }
                }
                return if (index == 0) "Descargas/${dest.name}" else "Almacenamiento de la app/${dest.name}"
            } catch (e: Exception) {
                lastError = e
            }
        }
        throw lastError ?: IllegalStateException("No se pudo guardar el archivo")
    }

    /** Nombre libre dentro de [dir] ("foto.png", "foto (1).png", …). */
    private fun uniqueFile(dir: File, name: String): File {
        val base = File(dir, name)
        if (!base.exists()) return base
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (i < 500) {
            val candidate = File(dir, "$stem ($i)$ext")
            if (!candidate.exists()) return candidate
            i++
        }
        return base
    }

    /** Tipo MIME de la descarga (para que Descargas muestre el icono correcto). */
    private fun mimeOf(name: String): String =
        when (name.substringAfterLast('.', "").lowercase()) {
            "zip" -> "application/zip"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "bmp" -> "image/bmp"
            "jpg", "jpeg" -> "image/jpeg"
            else -> "application/octet-stream"
        }

    /**
     * content:// del APK para el instalador (Android 7+ prohíbe file://).
     *
     * `FileProvider.getUriForFile` SOLO acepta archivos que caigan dentro de
     * las raíces declaradas en res/xml/file_paths.xml. En Android,
     * `Directory.systemTemp` (Dart) apunta a `/data/data/<pkg>/code_cache`,
     * que NO es una de esas raíces, y antes eso reventaba con:
     *   "Failed to find configured root that contains .../code_cache/..."
     * Si pasa, se copia el .apk al caché normal de la app (que sí está
     * expuesto con <cache-path>) y se entrega esa copia.
     */
    private fun contentUriFor(file: File): Uri {
        val authority = "$packageName.fileprovider"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return Uri.fromFile(file)
        }
        return try {
            FileProvider.getUriForFile(this, authority, file)
        } catch (e: IllegalArgumentException) {
            val dir = File(cacheDir, "hardstreet_cache/updates")
            if (!dir.exists()) dir.mkdirs()
            val copy = File(dir, file.name)
            file.inputStream().use { input ->
                copy.outputStream().use { output -> input.copyTo(output) }
            }
            FileProvider.getUriForFile(this, authority, copy)
        }
    }
}
