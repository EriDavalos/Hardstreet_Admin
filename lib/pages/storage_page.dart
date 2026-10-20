import 'package:flutter/material.dart';

import '../drive_scope.dart';
import '../hs_format.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/common.dart';

// ==================================================================
// MÓDULO ALMACENAMIENTO: cuánto espacio ocupa la carpeta donde se
// guardan las FOTOS y cuánto queda.
//
// Los números los da el servidor del Drive (`GET /api/space`, permiso de
// Archivos), que recorre la carpeta, suma el tamaño de los archivos y
// consulta el sistema de archivos para el TOTAL y el LIBRE reales:
//
//   usedBytes       lo que ocupan las fotos
//   limitBytes      la CUOTA de esa carpeta (hoy 180 GB; se cambia en el
//                   servidor con DRIVE_LIMIT_GB, sin tocar la app)
//   totalBytes      tamaño del disco donde vive la carpeta
//   freeBytes       lo que queda libre en ese disco
//   files / folders conteos
//
// Es de SOLO LECTURA: aquí no se borra ni se sube nada (eso es Archivos).
// Si el Drive es local (o el servidor no responde) el módulo lo dice en vez
// de inventar cifras.
// ==================================================================

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _info;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final drive = DriveScope.maybeOf(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    if (drive == null) {
      setState(() {
        _loading = false;
        _info = null;
      });
      return;
    }
    try {
      final info = await drive.storageInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo consultar el espacio: $e';
        _loading = false;
      });
    }
  }

  static double _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _info;
    final used = _num(info?['usedBytes']);
    // Si el servidor del Drive todavía no manda la cuota, se usa el MISMO
    // valor por defecto que él (180 GB): así nunca se muestra una cuota en
    // cero ni se parte de un divisor inválido.
    final rawLimit = _num(info?['limitBytes']);
    // 180 GB en bytes, como DOUBLE: el ternario no puede mezclar `double` con
    // `int` (devolvía `num` y rompía el tipo de la variable).
    const fallbackLimit = 180 * 1024 * 1024 * 1024.0;
    final limit = rawLimit > 0 ? rawLimit : fallbackLimit;
    final usedPct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

    return PageContainer(
      module: 'storage',
      title: 'Almacenamiento',
      description:
          'El espacio de la carpeta donde se guardan las fotos: lo usado, la '
          'cuota y lo que queda libre.',
      icon: Icons.sd_storage_outlined,
      expand: false,
      onRefresh: _load,
      // El botón de ACTUALIZAR ya no vive en el encabezado: va como botón de
      // imagen en la esquina de la tarjeta de presentación (igual que en el
      // Drive), que es donde se busca.
      actions: const [],
      stats: [
        if (info != null) ...[
          StatPill(
            icon: Icons.data_usage_rounded,
            label: 'Usado ${hsBytes(used)}',
          ),
          StatPill(
            icon: Icons.pie_chart_outline,
            label: '${(usedPct * 100).round()} % de la cuota',
          ),
          StatPill(
            icon: Icons.photo_library_outlined,
            label: '${info['files'] ?? 0} archivos',
          ),
        ],
      ],
      child: _body(scheme, info, used, limit, usedPct),
    );
  }

  Widget _body(
    ColorScheme scheme,
    Map<String, dynamic>? info,
    double used,
    double limit,
    double usedPct,
  ) {
    if (_loading) return const ListSkeleton(lines: 3, cardHeight: 110);
    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: scheme.error),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (info == null) {
      return const EmptyState(
        icon: Icons.sd_storage_outlined,
        title: 'Sin datos de espacio',
        message:
            'El servidor del Drive no reporta el espacio de la carpeta de '
            'fotos. Revisa la conexión del servidor (módulo Conexión).',
      );
    }

    final totalBytes = info['totalBytes'];
    final freeBytes = info['freeBytes'];
    final limitFree = _num(info['limitFreeBytes']);
    final files = (info['files'] as num?)?.toInt() ?? 0;
    final folders = (info['folders'] as num?)?.toInt() ?? 0;
    // La cuota en GB que se rotula (180 GB por defecto, igual que el servidor).
    final limitGb = (info['limitGb'] as num?)?.toInt() ?? 180;
    final root = (info['root'] ?? '').toString();

    final diskFree = totalBytes == null || freeBytes == null
        ? null
        : _num(freeBytes);
    final diskTotal = totalBytes == null ? null : _num(totalBytes);
    // Avisos: la cuota casi llena o el disco con menos espacio que la cuota.
    final cuotaBaja = usedPct >= .85;
    final discoCorto = diskFree != null && diskFree < limitFree;

    final barColor = cuotaBaja
        ? AppColors.danger
        : usedPct >= .7
        ? AppColors.warn
        : AppColors.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(
          child: _usageCard(
            scheme,
            used,
            limit,
            usedPct,
            barColor,
            limitFree,
            limitGb,
            diskTotal,
            diskFree,
          ),
        ),
        const SizedBox(height: 14),
        // Gráficas del espacio: la barra de la cuota partida en usada/libre
        // y el resto de los porcentajes, para ver de un vistazo cómo va.
        PopIn(
          delayMs: 70,
          child: _chartsCard(
            scheme,
            used,
            limit,
            usedPct,
            diskTotal,
            diskFree,
            limitFree,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) {
            final boxes = <Widget>[
              _DataBox(
                icon: Icons.folder_open_outlined,
                label: 'Carpeta de fotos',
                value: root.isEmpty ? 'Documentos/HardStreetDrive' : root,
                tint: AppColors.brand,
                mono: true,
              ),
              _DataBox(
                icon: Icons.photo_library_outlined,
                label: 'Archivos',
                value: '$files',
                tint: AppColors.dataFiles,
              ),
              _DataBox(
                icon: Icons.folder_copy_outlined,
                label: 'Carpetas',
                value: '$folders',
                tint: AppColors.dataFolders,
              ),
              _DataBox(
                icon: Icons.save_outlined,
                label: 'Cuota',
                value: hsBytes(limit),
                tint: AppColors.dataQuota,
              ),
              if (diskTotal != null)
                _DataBox(
                  icon: Icons.storage_rounded,
                  label: 'Disco (total)',
                  value: hsBytes(diskTotal),
                  tint: scheme.onSurfaceVariant,
                ),
              if (diskFree != null)
                _DataBox(
                  icon: Icons.sd_card_outlined,
                  label: 'Libre en el disco',
                  value: hsBytes(diskFree),
                  tint: diskFree < limitFree
                      ? AppColors.dataDisk
                      : AppColors.dataFree,
                ),
            ];
            // En teléfono 2 por fila; en escritorio 3.
            final perRow = box.maxWidth >= 900 ? 3 : 2;
            final w = (box.maxWidth - 12 * (perRow - 1)) / perRow;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < boxes.length; i++)
                  SizedBox(
                    width: w,
                    child: PopIn(delayMs: 60 + i * 50, child: boxes[i]),
                  ),
              ],
            );
          },
        ),
        if (cuotaBaja || discoCorto) ...[
          const SizedBox(height: 14),
          _alert(scheme, cuotaBaja: cuotaBaja, discoCorto: discoCorto),
        ],
        const SizedBox(height: 14),
        Text(
          'La cuota es SOLO una referencia de esta carpeta: hoy son '
          '$limitGb GB y se puede cambiar en el servidor del Drive '
          'con la variable DRIVE_LIMIT_GB, sin tocar la app. "Libre en el '
          'disco" es el espacio real del disco donde vive la carpeta.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _usageCard(
    ColorScheme scheme,
    double used,
    double limit,
    double usedPct,
    Color barColor,
    double limitFree,
    int? limitGb,
    double? diskTotal,
    double? diskFree,
  ) {
    final phone = MediaQuery.sizeOf(context).width < 620;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(phone ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: phone ? 38 : 44,
                  height: phone ? 38 : 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.brand, AppColors.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.sd_storage,
                    color: Colors.white,
                    size: phone ? 19 : 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Carpeta de fotos',
                        style: TextStyle(
                          fontSize: phone ? 13.5 : 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${hsBytes(used)} de ${hsBytes(limit)} ocupados',
                        style: TextStyle(
                          fontSize: phone ? 11.5 : 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: phone ? 10 : 14),
            // El nÚmero grande es el % DE LA CUOTA (180 GB), que es el limite
            // que maneja el estudio; el disco va aparte y en letra chica.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(usedPct * 100).round()} %',
                  style: TextStyle(
                    fontSize: phone ? 26 : 32,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: barColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'de la cuota de ${hsBytes(limit)}',
                    style: TextStyle(
                      fontSize: phone ? 11.5 : 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _UsageBar(used: used, limit: limit, color: barColor),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniTag(
                  icon: Icons.data_usage_rounded,
                  label: 'Usado ${hsBytes(used)}',
                  tint: barColor,
                ),
                _MiniTag(
                  icon: Icons.pie_chart_outline,
                  label: 'Libre de la cuota ${hsBytes(limitFree)}',
                  tint: AppColors.dataFree,
                ),
                if (limitGb != null)
                  _MiniTag(
                    icon: Icons.straighten_rounded,
                    label: 'Cuota $limitGb GB',
                    tint: AppColors.dataQuota,
                  ),
                if (diskFree != null)
                  _MiniTag(
                    icon: Icons.sd_card_outlined,
                    label: 'Libre en el disco ${hsBytes(diskFree)}',
                    tint: diskFree < limitFree
                        ? AppColors.dataDisk
                        : AppColors.dataFree,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta de GRÁFICAS: barras de porcentaje de la cuota y del disco, más
  /// la barra partida usado | libre. Todo calculado con lo que reporta el
  /// servidor (nunca con números inventados).
  Widget _chartsCard(
    ColorScheme scheme,
    double used,
    double limit,
    double usedPct,
    double? diskTotal,
    double? diskFree,
    double limitFree,
  ) {
    final diskUsedPct = (diskTotal != null && diskTotal > 0 && diskFree != null)
        ? ((diskTotal - diskFree) / diskTotal).clamp(0.0, 1.0)
        : null;
    final freePct = (1 - usedPct).clamp(0.0, 1.0);
    final rows = <Widget>[
      _PercentBar(
        icon: Icons.pie_chart_outline,
        label: 'Cuota usada',
        detail: '${hsBytes(used)} de ${hsBytes(limit)}',
        value: usedPct,
        color: usedPct >= .85
            ? AppColors.danger
            : usedPct >= .7
            ? AppColors.warn
            : AppColors.brand,
      ),
      _PercentBar(
        icon: Icons.donut_large_outlined,
        label: 'Cuota libre',
        detail: 'Quedan ${hsBytes(limitFree)} de ${hsBytes(limit)}',
        value: freePct,
        color: AppColors.dataFree,
      ),
      if (diskUsedPct != null)
        _PercentBar(
          icon: Icons.storage_rounded,
          label: 'Disco usado',
          detail: '${hsBytes(diskTotal! - diskFree!)} de ${hsBytes(diskTotal)}',
          value: diskUsedPct,
          color: AppColors.dataDisk,
        ),
      if (diskFree != null && diskTotal != null && diskTotal > 0)
        _PercentBar(
          icon: Icons.sd_card_outlined,
          label: 'Disco libre',
          detail: 'Quedan ${hsBytes(diskFree)} en el disco',
          value: (diskFree / diskTotal).clamp(0.0, 1.0),
          color: AppColors.dataFiles,
        ),
    ];
    final phone = MediaQuery.sizeOf(context).width < 620;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(phone ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Porcentajes del espacio',
                    style: TextStyle(
                      fontSize: phone ? 12.5 : 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Barra PARTIDA: lo usado contra lo libre de la cuota.
            _SplitBar(scheme, used, limit),
            const SizedBox(height: 14),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              PopIn(delayMs: 60 + i * 50, child: rows[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alert(
    ColorScheme scheme, {
    required bool cuotaBaja,
    required bool discoCorto,
  }) {
    final color = discoCorto ? AppColors.danger : AppColors.warn;
    final text = discoCorto
        ? 'El disco donde vive la carpeta tiene MENOS espacio libre que la '
              'cuota configurada: aunque la cuota diga que hay espacio, el disco '
              'se puede llenar antes. Libera espacio o mueve la carpeta.'
        : 'La carpeta de fotos ya usa el 85 % o más de su cuota. Considera '
              'ampliarla (DRIVE_LIMIT_GB en el servidor del Drive) o depurar '
              'fotos viejas.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            discoCorto ? Icons.error_outline : Icons.warning_amber_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de uso: lo USADO contra el resto de la cuota. Si el uso es 0 se ve
/// un carril vacío (nunca una barra "llena" por accidente).
class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.used,
    required this.limit,
    required this.color,
  });

  final double used;
  final double limit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Se redondea a enteros de "flex" (la barra no necesita precisión de
    // bytes) y se garantiza que, si hay algo usado, se VEA al menos un 1 %.
    final total = limit <= 0 ? 1 : limit;
    var pct = ((used / total) * 100).round();
    if (used > 0 && pct == 0) pct = 1;
    pct = pct.clamp(0, 100);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            if (pct > 0)
              Expanded(
                flex: pct,
                child: ColoredBox(color: color),
              ),
            if (pct < 100)
              Expanded(
                flex: 100 - pct,
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra PARTIDA de la cuota: la parte usada a la izquierda y la libre a la
/// derecha, con sus porcentajes escritos encima.
class _SplitBar extends StatelessWidget {
  const _SplitBar(this.scheme, this.used, this.limit);

  final ColorScheme scheme;
  final double used;
  final double limit;

  @override
  Widget build(BuildContext context) {
    final total = limit <= 0 ? 1.0 : limit;
    var pct = ((used / total) * 100).round();
    if (used > 0 && pct == 0) pct = 1;
    pct = pct.clamp(0, 100);
    final usedColor = pct >= 85
        ? AppColors.danger
        : pct >= 70
        ? AppColors.warn
        : AppColors.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 22,
            child: Row(
              children: [
                if (pct > 0)
                  Expanded(
                    flex: pct,
                    child: ColoredBox(
                      color: usedColor,
                      child: Center(
                        child: Text(
                          '$pct %',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (pct < 100)
                  Expanded(
                    flex: 100 - pct,
                    child: ColoredBox(
                      color: AppColors.dataFree.withValues(alpha: .18),
                      child: Center(
                        child: Text(
                          '${100 - pct} % libre',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dataFree,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                'Usado',
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              'Libre',
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fila de una gráfica de porcentaje: icono + etiqueta + barra + % grande.
class _PercentBar extends StatelessWidget {
  const _PercentBar({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String detail;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${(pct * 100).round()} %',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: .14),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Caja de un dato del almacenamiento (icono + etiqueta + valor).
class _DataBox extends StatelessWidget {
  const _DataBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Móvil: la letra de la tarjeta baja un punto (y el rótulo medio) sin
    // llegar a ilegible.
    final phone = MediaQuery.sizeOf(context).width < 620;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(phone ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: tint.withValues(alpha: .26)),
                  ),
                  child: Icon(icon, size: 15, color: tint),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: phone ? 10.5 : 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: phone ? 8 : 10),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: mono ? (phone ? 11 : 12) : (phone ? 15 : 17),
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Píldora pequeña con icono + texto.
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.icon, required this.label, required this.tint});

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}
