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
    final limit = _num(info?['limitBytes']);
    final usedPct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;

    return PageContainer(
      title: 'Almacenamiento',
      description:
          'El espacio de la carpeta donde se guardan las fotos: lo usado, la '
          'cuota y lo que queda libre.',
      icon: Icons.sd_storage_outlined,
      expand: false,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
        ),
      ],
      stats: [
        if (info != null) ...[
          StatPill(
              icon: Icons.data_usage_rounded,
              label: 'Usado ${hsBytes(used)}'),
          StatPill(
              icon: Icons.pie_chart_outline,
              label: '${(usedPct * 100).round()} % de la cuota'),
          StatPill(
              icon: Icons.photo_library_outlined,
              label: '${info['files'] ?? 0} archivos'),
        ],
      ],
      child: _body(scheme, info, used, limit, usedPct),
    );
  }

  Widget _body(ColorScheme scheme, Map<String, dynamic>? info, double used,
      double limit, double usedPct) {
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
    final limitGb = (info['limitGb'] as num?)?.toInt();
    final root = (info['root'] ?? '').toString();

    final diskFree = totalBytes == null || freeBytes == null
        ? null
        : _num(freeBytes);
    final diskTotal = totalBytes == null ? null : _num(totalBytes);
    // Avisos: la cuota casi llena o el disco con menos espacio que la cuota.
    final cuotaBaja = usedPct >= .85;
    final discoCorto = diskFree != null && diskFree < limitFree;

    final barColor = cuotaBaja
        ? const Color(0xFFEF4444)
        : usedPct >= .7
            ? const Color(0xFFF59E0B)
            : AppColors.brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(child: _usageCard(scheme, used, limit, usedPct, barColor,
            limitFree, limitGb)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, box) {
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
              tint: const Color(0xFF3B82F6),
            ),
            _DataBox(
              icon: Icons.folder_copy_outlined,
              label: 'Carpetas',
              value: '$folders',
              tint: const Color(0xFF8B5CF6),
            ),
            _DataBox(
              icon: Icons.save_outlined,
              label: 'Cuota',
              value: hsBytes(limit),
              tint: const Color(0xFF10B981),
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
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
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
                SizedBox(width: w, child: PopIn(delayMs: 60 + i * 50, child: boxes[i])),
            ],
          );
        }),
        if (cuotaBaja || discoCorto) ...[
          const SizedBox(height: 14),
          _alert(scheme, cuotaBaja: cuotaBaja, discoCorto: discoCorto),
        ],
        const SizedBox(height: 14),
        Text(
          'La cuota es SOLO una referencia de esta carpeta: hoy son '
          '${limitGb ?? 180} GB y se puede cambiar en el servidor del Drive '
          'con la variable DRIVE_LIMIT_GB, sin tocar la app. "Libre en el '
          'disco" es el espacio real del disco donde vive la carpeta.',
          style: TextStyle(
              fontSize: 11.5, height: 1.35, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _usageCard(ColorScheme scheme, double used, double limit,
      double usedPct, Color barColor, double limitFree, int? limitGb) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brand, AppColors.brandDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child:
                      const Icon(Icons.sd_storage, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Carpeta de fotos',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${hsBytes(used)} de ${hsBytes(limit)} ocupados',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(usedPct * 100).round()} %',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: barColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                  tint: const Color(0xFF10B981),
                ),
                if (limitGb != null)
                  _MiniTag(
                    icon: Icons.straighten_rounded,
                    label: 'Cuota $limitGb GB',
                    tint: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alert(ColorScheme scheme,
      {required bool cuotaBaja, required bool discoCorto}) {
    final color = discoCorto ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
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
          Icon(discoCorto ? Icons.error_outline : Icons.warning_amber_rounded,
              size: 20, color: color),
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
            if (pct > 0) Expanded(flex: pct, child: ColoredBox(color: color)),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: tint.withValues(alpha: .26)),
                  ),
                  child: Icon(icon, size: 16, color: tint),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: mono ? 12 : 17,
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
  const _MiniTag({
    required this.icon,
    required this.label,
    required this.tint,
  });

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
