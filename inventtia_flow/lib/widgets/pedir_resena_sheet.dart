import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/resena_service.dart';
import 'net_image.dart';

/// Firma del publicador, inyectable para poder probar el cartel sin Supabase.
typedef PublicarResena =
    Future<void> Function({required int puntuacion, String? comentario});

/// Cartel que pide la reseña de una reserva **ya completada**.
///
/// QUE ES
///   Cuando al cliente le terminan de atender un servicio, la app le enseña este
///   cartel **dentro de la app** (no es una notificación ni un push): la foto del
///   servicio, el nombre y la fecha, cinco estrellas grandes y un campo de texto.
///   Al publicar, la reseña queda anclada a esa reserva (`publicar_resena` recibe
///   `id_agenda`), así que es una opinión **verificada**: solo puede escribirla
///   quien de verdad fue atendido.
///
/// CUANDO SALE
///   Lo decide `PreguntaResenaService` + `ResenaService.pendientes()`
///   (`cliente_resenas_pendientes`, migración 59): una sola vez por reserva
///   completada sin reseña, aunque el usuario cierre sin escribir. No se repite
///   por el mismo servicio.
///
/// POR QUE UN BOTTOM SHEET Y NO UN `AlertDialog`
///   El teclado tiene que poder subir sin tapar el campo de texto, y el gesto de
///   arrastrar para cerrar es el que el usuario ya espera aquí. Con un diálogo
///   centrado el teclado deja el formulario en una franja de 120 px.
///
/// DISEÑO
///   Se entra por la foto del servicio (contexto inmediato: "esto es lo que me
///   atendieron") y el recorrido es de arriba abajo, en el mismo orden en que se
///   rellena: estrellas → frase → texto → publicar. La frase que cambia bajo las
///   estrellas no es adorno: nombra lo que el usuario acaba de valorar, que es lo
///   que hace que se anime a escribir en vez de cerrar.
class PedirResenaSheet extends StatefulWidget {
  const PedirResenaSheet({
    super.key,
    required this.pendiente,
    required this.uuidUsuario,
    this.ahora,
    this.publicar,
  });

  /// La reserva completada que hay que reseñar.
  final ResenaPendiente pendiente;

  /// Usuario que publica. `publicar_resena` lo exige explícitamente.
  final String uuidUsuario;

  /// Inyectable: "hoy" / "ayer" dependen del reloj y así se puede probar.
  final DateTime? ahora;

  /// Inyectable para tests. `null` ⇒ se publica de verdad contra Supabase.
  final PublicarResena? publicar;

  /// Claves estables para los tests de widget (no se infieren por posición).
  static Key claveEstrella(int estrellas) => Key('pedir-resena-estrella-$estrellas');
  static const Key claveFrase = Key('pedir-resena-frase');
  static const Key claveComentario = Key('pedir-resena-comentario');
  static const Key clavePublicar = Key('pedir-resena-publicar');
  static const Key claveAhoraNo = Key('pedir-resena-ahora-no');
  static const Key claveError = Key('pedir-resena-error');
  static Key claveSugerencia(String texto) => Key('pedir-resena-sug-$texto');

  @override
  State<PedirResenaSheet> createState() => _PedirResenaSheetState();
}

class _PedirResenaSheetState extends State<PedirResenaSheet> {
  /// Frases de aliento por nota. La gracia está en que cambian el foco de la
  /// pregunta según lo que eligió: a quien puso 1 no se le pregunta "¿qué te
  /// encantó?" (sonaría a burla), se le pide que cuente qué falló.
  static const Map<int, String> _frases = <int, String>{
    1: 'Lo sentimos. Cuéntanos qué falló y lo revisamos.',
    2: 'Gracias por la sinceridad. ¿Qué podemos mejorar?',
    3: '¿Qué le faltó para ser perfecto?',
    4: '¡Qué bien! ¿Qué fue lo que más te gustó?',
    5: '¡Excelente! Cuéntanos por qué lo recomendarías.',
  };

  /// Ideas que se añaden al texto con un toque. Escribir en blanco es la razón
  /// por la que la mayoría cierra el cartel: media frase hecha resuelve eso.
  static const List<String> _sugerencias = <String>[
    'Me atendieron a la hora',
    'Trato muy amable',
    'Quedó tal cual lo pedí',
    'Lugar limpio y cómodo',
    'Buena relación precio/calidad',
  ];

  late final TextEditingController _comentario;
  int _puntuacion = 0;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _comentario = TextEditingController();
  }

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _publicar() async {
    if (_puntuacion < 1) {
      setState(() => _error = 'Elige de 1 a 5 estrellas para publicar.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final publicar = widget.publicar;
      if (publicar != null) {
        await publicar(
          puntuacion: _puntuacion,
          comentario: _comentario.text,
        );
      } else {
        await ResenaService.publicar(
          uuidUsuario: widget.uuidUsuario,
          idAgenda: widget.pendiente.idAgenda,
          puntuacion: _puntuacion,
          comentario: _comentario.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Añade una idea al texto sin pisar lo que ya escribió el usuario.
  void _anadirSugerencia(String texto) {
    final actual = _comentario.text.trim();
    if (actual.toLowerCase().contains(texto.toLowerCase())) return;
    final nuevo = actual.isEmpty ? texto : '$actual. $texto';
    _comentario.value = TextEditingValue(
      text: nuevo,
      selection: TextSelection.collapsed(offset: nuevo.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final pendiente = widget.pendiente;
    final fecha = pendiente.etiquetaFecha(ahora: widget.ahora);

    return Padding(
      // El teclado empuja el contenido: sin esto el campo de texto y el botón
      // quedan debajo de la barra del sistema en Android.
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cabecera(pendiente: pendiente, fecha: fecha),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¿Cómo te fue?',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      pendiente.localNombre.trim().isEmpty
                          ? 'Tu opinión ayuda a otros clientes a elegir mejor.'
                          : 'Cuéntale a quien vaya a ${pendiente.localNombre} '
                                'qué tal te atendieron. Tarda menos de un minuto.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Selector(
                      valor: _puntuacion,
                      habilitado: !_enviando,
                      onChanged: (v) => setState(() {
                        _puntuacion = v;
                        if (_error != null) _error = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    _Frase(puntuacion: _puntuacion),
                    const SizedBox(height: 16),
                    TextField(
                      key: PedirResenaSheet.claveComentario,
                      controller: _comentario,
                      enabled: !_enviando,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                      decoration: InputDecoration(
                        hintText: _puntuacion > 0
                            ? '¿Qué te gustó? ¿Qué se puede mejorar?'
                            : 'Elige las estrellas y cuéntanos…',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppTheme.surface,
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.all(14),
                        counterStyle: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    // Las ideas solo aparecen si el usuario aún no escribió nada
                    // ni tocó una: si ya hay texto, sobran y roban altura.
                    if (_comentario.text.trim().isEmpty) ...[
                      const SizedBox(height: 2),
                      _Sugerencias(
                        habilitado: !_enviando,
                        onElegir: _anadirSugerencia,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        key: PedirResenaSheet.claveError,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 15,
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _BotonPublicar(
                      habilitado: !_enviando,
                      conEstrellas: _puntuacion > 0,
                      enviando: _enviando,
                      onPressed: _publicar,
                    ),
                    Center(
                      child: TextButton(
                        key: PedirResenaSheet.claveAhoraNo,
                        onPressed: _enviando
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text(
                          'Ahora no',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabecera: foto del servicio (o degradado de marca) con el rótulo de reserva
/// verificada y, encima del degradado, de qué servicio y local fue.
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.pendiente, required this.fecha});

  final ResenaPendiente pendiente;
  final String fecha;

  @override
  Widget build(BuildContext context) {
    final foto = pendiente.servicioFoto;
    return SizedBox(
      height: 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (foto != null && foto.trim().isNotEmpty)
            NetImage(
              url: foto,
              fit: BoxFit.cover,
              placeholder: _respaldo,
              errorWidget: _respaldo,
            )
          else
            _respaldo(),
          // Degradado doble: uno desde abajo para que el texto blanco tenga
          // contraste real (la foto puede ser clara) y otro suave arriba para
          // que la fila del rótulo no se pierda.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x00000000), Color(0xCC000000)],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'RESERVA COMPLETADA',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pendiente.servicioNombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.15,
                    shadows: [
                      Shadow(color: Color(0x66000000), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (pendiente.localNombre.trim().isNotEmpty)
                      pendiente.localNombre.trim(),
                    if (fecha.isNotEmpty) fecha,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sin foto (o si falla) no se deja un hueco gris: se pinta el degradado de
  /// marca con el icono de la categoría, que sigue diciendo de qué va.
  Widget _respaldo() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.primaryLight, AppTheme.primaryDark],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.rate_review_outlined,
        size: 40,
        color: Color(0x33FFFFFF),
      ),
    ),
  );
}

/// Cinco estrellas grandes con animación de escala al elegir.
///
/// Se hace aquí y no con `SelectorEstrellas` (el del detalle del servicio)
/// porque este es el momento en el que hay que **convencer**: las estrellas son
/// el primer control que se toca y tienen que responder. El del detalle es un
/// formulario más, donde el tamaño pequeño es lo correcto.
class _Selector extends StatelessWidget {
  const _Selector({
    required this.valor,
    required this.onChanged,
    this.habilitado = true,
  });

  final int valor;
  final ValueChanged<int> onChanged;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            label: 'Valorar con $i ${i == 1 ? 'estrella' : 'estrellas'}',
            child: GestureDetector(
              key: PedirResenaSheet.claveEstrella(i),
              onTap: habilitado ? () => onChanged(i) : null,
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                // La elegida "late" un poco más: feedback inmediato de que el
                // toque se registró, sin mover el resto de la fila.
                scale: valor == i ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                  child: Icon(
                    i <= valor
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 40,
                    color: i <= valor
                        ? AppTheme.warning
                        : AppTheme.textSecondary.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Frase que cambia según la nota elegida.
class _Frase extends StatelessWidget {
  const _Frase({required this.puntuacion});

  final int puntuacion;

  @override
  Widget build(BuildContext context) {
    final texto = _PedirResenaSheetState._frases[puntuacion] ??
        'Toca las estrellas para valorar';

    return ConstrainedBox(
      key: PedirResenaSheet.claveFrase,
      // Alto MÍNIMO, no fijo: las frases no miden lo mismo y con el texto
      // ampliado (accesibilidad) una de dos líneas no cabría en un alto fijo y
      // desbordaría. El mínimo mantiene el hueco estable al cambiar de nota.
      constraints: const BoxConstraints(minHeight: 34),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            texto,
            key: ValueKey(texto),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: puntuacion > 0 ? FontWeight.w800 : FontWeight.w600,
              color: puntuacion > 0
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ideas para rellenar el comentario con un toque.
class _Sugerencias extends StatelessWidget {
  const _Sugerencias({required this.onElegir, this.habilitado = true});

  final ValueChanged<String> onElegir;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final texto in _PedirResenaSheetState._sugerencias)
          ActionChip(
            key: PedirResenaSheet.claveSugerencia(texto),
            onPressed: habilitado ? () => onElegir(texto) : null,
            label: Text(
              texto,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            backgroundColor: AppTheme.primary.withValues(alpha: 0.06),
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.18)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 2),
          ),
      ],
    );
  }
}

/// Botón de publicar. Se atenúa mientras no hay estrellas, pero **sigue activo**
/// a propósito: al tocarlo explica qué falta, en vez de quedarse mudo.
class _BotonPublicar extends StatelessWidget {
  const _BotonPublicar({
    required this.onPressed,
    required this.enviando,
    this.habilitado = true,
    this.conEstrellas = false,
  });

  final VoidCallback onPressed;
  final bool enviando;
  final bool habilitado;
  final bool conEstrellas;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: PedirResenaSheet.clavePublicar,
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: habilitado ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: conEstrellas
              ? AppTheme.primary
              : AppTheme.primary.withValues(alpha: 0.45),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        child: enviando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, size: 17),
                  SizedBox(width: 8),
                  // Flexible: en un móvil de 320 px o con el texto ampliado el
                  // rótulo no cabe entero. Se recorta con puntos en vez de
                  // desbordar la fila (que es lo que hacía con la fuente ancha).
                  Flexible(
                    child: Text(
                      'Publicar reseña',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Abre el cartel y devuelve `true` si el usuario publicó su reseña.
///
/// Nunca lanza: si algo falla, el error se pinta **dentro** del cartel (con el
/// texto sigue ahí, no se pierde lo escrito) y devuelve `false`.
Future<bool> mostrarPedirResena(
  BuildContext context, {
  required ResenaPendiente pendiente,
  required String uuidUsuario,
  DateTime? ahora,
  PublicarResena? publicar,
}) async {
  final publicado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Sin esto el fondo negro al 50 % tapa la foto del servicio, que es la que
    // da el contexto de "esto es lo que me atendieron".
    barrierColor: Colors.black.withValues(alpha: 0.42),
    backgroundColor: Colors.white,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => PedirResenaSheet(
      pendiente: pendiente,
      uuidUsuario: uuidUsuario,
      ahora: ahora,
      publicar: publicar,
    ),
  );
  return publicado == true;
}
