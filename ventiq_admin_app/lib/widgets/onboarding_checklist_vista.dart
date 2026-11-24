/// Vista (sin red) del checklist de activación de tienda.
///
/// Fase 3 del plan `docs/plans/alta-tienda-progresiva-go-live.md`.
///
/// Este archivo **no importa ningún servicio**: todo lo que necesita llega por
/// parámetro. Así se puede montar en una prueba de widget con una lista de
/// [TareaOnboarding] fabricada, sin Supabase y sin red. La pantalla con datos
/// (`ActivacionTiendaScreen`, en `screens/activacion_tienda_screen.dart`) es la
/// única que habla con `OnboardingService` y le pasa el resultado a este widget.
///
/// Reglas de diseño que se respetan aquí (GOV.UK / Stripe / Shopify, citadas por
/// el plan):
///
/// - El contador es **neutro**: «2 de 5 pasos completados». Nunca «te faltan 3»
///   ni un porcentaje de deuda.
/// - Pendiente es azul, bloqueado gris con el motivo visible, completado texto
///   normal con un check. Rojo **solo** para fallos reales (la carga fallida).
/// - Sin modales automáticos: nada aparece solo al cargar.
/// - Nunca se pintan ceros ni una lista vacía mientras se carga: spinner y ya.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/onboarding_tareas.dart';
import 'onboarding_tarea_tile.dart';

/// Ancho máximo del contenido en pantalla ancha. Por encima de
/// [activacionAnchoUnaColumna] el checklist se centra en vez de estirarse: una
/// lista de texto a 1400 px es incómoda de leer.
const double activacionAnchoMaximo = 760;

/// Corte a partir del cual la pantalla deja de ser móvil y se centra.
const double activacionAnchoUnaColumna = 900;

/// Título de la pantalla. Vive aquí para que la vista y la pantalla no puedan
/// discrepar.
const String activacionTitulo = 'Pon tu tienda en marcha';

/// Subtítulo: dice el **beneficio**, no la mecánica del checklist.
const String activacionSubtitulo =
    'Cuando esté lista podrás cobrar desde el primer día: tu catálogo en la '
    'caja, tu equipo con su usuario y tu stock bajo control.';

/// Etiqueta, explicación y icono de cada tipo de negocio.
///
/// La frase dice **qué implica** declarar ese tipo (qué tareas añade), no una
/// definición de diccionario.
const Map<String, ({String etiqueta, String implica, IconData icono})>
tiposNegocioUi = {
  'retail': (
    etiqueta: 'Tienda o bodega',
    implica:
        'Vendes productos de estante. Te pediremos almacén, caja y stock '
        'antes de abrir.',
    icono: Icons.storefront_outlined,
  ),
  'restaurante': (
    etiqueta: 'Restaurante o cafetería',
    implica:
        'Vendes platos y tomas pedidos en mesa. Añadimos cocina y modo '
        'restaurante al checklist.',
    icono: Icons.restaurant_outlined,
  ),
  'servicentro': (
    etiqueta: 'Servicentro',
    implica:
        'Vendes combustible por surtidor. Añadimos el modo servicentro de la '
        'caja.',
    icono: Icons.local_gas_station_outlined,
  ),
  'catalogo': (
    etiqueta: 'Solo catálogo',
    implica:
        'Muestras tu catálogo pero no cobras desde el admin: sin caja ni '
        'almacén, solo productos.',
    icono: Icons.menu_book_outlined,
  ),
};

/// Nombre visible del tipo de negocio (para el resumen «Tipo: ...»).
String etiquetaTipoNegocio(String? tipo) {
  if (tipo == null) return 'Sin definir';
  return tiposNegocioUi[tipo]?.etiqueta ?? tipo;
}

/// Texto del contador. Neutro por diseño: cuenta lo hecho, no lo que falta.
String textoProgreso(List<TareaOnboarding> tareas) {
  final avance = progreso(tareas);
  final pasos = avance.total == 1 ? 'paso completado' : 'pasos completados';
  return '${avance.completadas} de ${avance.total} $pasos';
}

/// Cuerpo visual de la pantalla de activación.
///
/// Todo lo que necesita llega por parámetro: [tareas], [tipoNegocio], el estado
/// de carga ([cargando]) o de error ([error]) y los callbacks. No crea servicios.
class OnboardingChecklistVista extends StatefulWidget {
  const OnboardingChecklistVista({
    super.key,
    required this.tareas,
    required this.tipoNegocio,
    this.cargando = false,
    this.error,
    this.onReintentar,
    this.onElegirTipoNegocio,
    this.onAbrirTarea,
    this.onDescartar,
    this.onRecuperar,
    this.descartado = false,
    this.accionFinal,
    this.titulo = activacionTitulo,
  });

  /// Tareas ya calculadas. Se ignoran mientras [cargando] o si hay [error].
  final List<TareaOnboarding> tareas;

  /// Tipo de negocio declarado, o `null` si todavía no lo eligió.
  final String? tipoNegocio;

  final bool cargando;

  /// Mensaje de error de la carga. Si no es nulo, la pantalla solo muestra el
  /// error con su botón de reintento: ni ceros ni lista vacía.
  final String? error;

  final VoidCallback? onReintentar;

  /// Elige (o cambia) el tipo de negocio.
  final ValueChanged<String>? onElegirTipoNegocio;

  /// Abre la tarea. Solo se llama para las accionables.
  final ValueChanged<TareaOnboarding>? onAbrirTarea;

  /// Descarta el checklist y vuelve al dashboard.
  final VoidCallback? onDescartar;

  /// Restaura un checklist descartado.
  final VoidCallback? onRecuperar;

  final bool descartado;

  /// Hueco para la acción de cierre que añade la fase 4 (Go Live). La fase 3 no
  /// inventa ese botón: solo deja el sitio.
  final Widget? accionFinal;

  final String titulo;

  @override
  State<OnboardingChecklistVista> createState() =>
      _OnboardingChecklistVistaState();
}

class _OnboardingChecklistVistaState extends State<OnboardingChecklistVista> {
  /// `true` mientras el usuario está cambiando un tipo ya elegido. Con el tipo
  /// sin elegir el selector siempre está visible.
  bool _cambiandoTipo = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('onboarding_descartar'),
            icon: const Icon(Icons.close),
            tooltip:
                'Descartar el checklist (puedes recuperarlo desde el menú)',
            onPressed: widget.onDescartar,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) {
            final ancho = restricciones.maxWidth;
            final anchoContenido = ancho > activacionAnchoUnaColumna
                ? activacionAnchoMaximo
                : ancho;
            final margen = ancho > activacionAnchoUnaColumna ? 24.0 : 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: margen,
                vertical: ancho > activacionAnchoUnaColumna ? 28 : 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: anchoContenido),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _contenido(ancho),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Estados
  // -------------------------------------------------------------------------

  List<Widget> _contenido(double ancho) {
    final compacto = ancho <= activacionAnchoUnaColumna;

    // Cargando: spinner y nada más. Ni ceros ni «0 de 0» mientras se espera.
    if (widget.cargando) {
      return [
        const SizedBox(height: 12),
        _cargando(),
      ];
    }

    // Error real: es el único sitio de la pantalla que usa rojo.
    final error = widget.error;
    if (error != null) {
      return [
        _cabecera(compacto: compacto),
        const SizedBox(height: 16),
        _bloqueError(error),
      ];
    }

    return [
      _cabecera(compacto: compacto),
      const SizedBox(height: 16),
      if (widget.descartado) ...[
        _bannerDescartado(),
        const SizedBox(height: 12),
      ],
      if (widget.tipoNegocio == null || _cambiandoTipo) ...[
        _selectorTipoNegocio(),
        const SizedBox(height: 16),
      ] else ...[
        _tipoElegido(),
        const SizedBox(height: 14),
      ],
      ..._listaTareas(),
      if (widget.accionFinal != null) ...[
        const SizedBox(height: 20),
        widget.accionFinal!,
      ],
      const SizedBox(height: 8),
    ];
  }

  Widget _cargando() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Cargando tu checklist...',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Cabecera con el beneficio (no la mecánica) y el contador neutro.
  Widget _cabecera({required bool compacto}) {
    final hayDatos = !widget.cargando && widget.error == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.titulo,
          style: TextStyle(
            fontSize: compacto ? 22 : 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          activacionSubtitulo,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        if (hayDatos) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    textoProgreso(widget.tareas),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _barraProgreso()),
            ],
          ),
        ],
      ],
    );
  }

  /// Barra fina y sin color de alarma: mide avance, no deuda.
  Widget _barraProgreso() {
    final avance = progreso(widget.tareas);
    final valor = avance.total == 0 ? 0.0 : avance.completadas / avance.total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: valor,
        minHeight: 3,
        backgroundColor: AppColors.border,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
      ),
    );
  }

  Widget _bannerDescartado() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Tienes este checklist descartado. Nada se ha borrado: puedes '
              'recuperarlo cuando quieras.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.onRecuperar,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Recuperar'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tipo de negocio
  // -------------------------------------------------------------------------

  Widget _selectorTipoNegocio() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Qué tipo de negocio tienes?',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Nos sirve para recomendarte solo los pasos que te tocan. No cambia '
            'la configuración de tu tienda.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final tipo in tiposNegocioConocidos) ...[
            _opcionTipo(tipo),
            if (tipo != tiposNegocioConocidos.last) const SizedBox(height: 8),
          ],
          if (_cambiandoTipo) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _cambiandoTipo = false),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _opcionTipo(String tipo) {
    final datos = tiposNegocioUi[tipo];
    if (datos == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey<String>('onboarding_tipo_$tipo'),
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onElegirTipoNegocio == null
            ? null
            : () {
                widget.onElegirTipoNegocio!(tipo);
                setState(() => _cambiandoTipo = false);
              },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
            color: AppColors.background,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(datos.icono, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        datos.etiqueta,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        datos.implica,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tipo ya declarado: se muestra como texto con opción de cambiarlo.
  Widget _tipoElegido() {
    return Row(
      children: [
        const Text(
          'Tipo de negocio:',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            etiquetaTipoNegocio(widget.tipoNegocio),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          key: const Key('onboarding_cambiar_tipo'),
          onPressed: widget.onElegirTipoNegocio == null
              ? null
              : () => setState(() => _cambiandoTipo = true),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            visualDensity: VisualDensity.compact,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Lista de tareas
  // -------------------------------------------------------------------------

  List<Widget> _listaTareas() {
    if (widget.tareas.isEmpty) {
      return [
        _tarjeta(
          child: const Text(
            'No hay nada que completar. Cuando termines, podrás activar tu '
            'tienda.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ];
    }

    return [
      const Text(
        'Lo que falta',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < widget.tareas.length; i++) ...[
        OnboardingTareaTile(
          key: OnboardingTareaTile.claveTarea(widget.tareas[i].clave),
          tarea: widget.tareas[i],
          onTap: widget.tareas[i].accionable && widget.onAbrirTarea != null
              ? () => widget.onAbrirTarea!(widget.tareas[i])
              : null,
        ),
        if (i != widget.tareas.length - 1) const SizedBox(height: 10),
      ],
    ];
  }

  // -------------------------------------------------------------------------
  // Piezas
  // -------------------------------------------------------------------------

  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Error real de carga de la consulta. Rojo aquí sí: sin los datos no se
  /// puede guiar al usuario con ninguna otra cosa.
  Widget _bloqueError(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                size: 18,
                color: AppColors.error,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'No se pudo cargar el checklist',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.onReintentar,
              icon: const Icon(Icons.refresh, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
                backgroundColor: AppColors.surface,
                visualDensity: VisualDensity.compact,
              ),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      ),
    );
  }
}
