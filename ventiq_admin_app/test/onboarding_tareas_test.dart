import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/onboarding_tareas.dart';

/// Contrato del checklist de activación (fase 3 del plan
/// `docs/plans/alta-tienda-progresiva-go-live.md`).
///
/// Es un modelo puro: no hay widgets, ni Supabase, ni red. Lo que se prueba es
/// que las tareas salen de los hechos y que el gate del Go Live solo mira las
/// obligatorias.
void main() {
  /// Las obligatorias que el plan marca como bloqueantes.
  const clavesObligatorias = ['almacen', 'tpv', 'producto', 'cobro'];

  List<String> claves(List<TareaOnboarding> tareas) =>
      tareas.map((t) => t.clave).toList();

  TareaOnboarding tarea(List<TareaOnboarding> tareas, String clave) =>
      tareas.firstWhere((t) => t.clave == clave);

  group('retail', () {
    test('sin nada: 6+ tareas, las 4 obligatorias pendientes y no activa', () {
      final tareas = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(),
      );

      expect(tareas.length, greaterThanOrEqualTo(6));

      final obligatorias = tareas.where((t) => t.obligatoria).toList();
      expect(claves(obligatorias), containsAll(clavesObligatorias));
      expect(obligatorias.length, clavesObligatorias.length);
      for (final t in obligatorias) {
        expect(t.estado, EstadoTarea.pendiente, reason: t.clave);
      }

      expect(puedeActivar(tareas), isFalse);
      expect(progreso(tareas).completadas, 0);
      expect(progreso(tareas).total, tareas.length);
    });

    test(
      'con almacén, TPV, producto y vendedor en caja ya puede activar',
      () {
        final tareas = construirTareas(
          tipoNegocio: 'retail',
          hechos: const HechosTienda(
            tieneAlmacen: true,
            tieneTpv: true,
            tieneProducto: true,
            tieneVendedorAsignado: true,
          ),
        );

        // Zonas y personal no bloquean: la tienda puede salir igual.
        expect(tarea(tareas, 'zona').estado, EstadoTarea.pendiente);
        expect(tarea(tareas, 'personal').estado, EstadoTarea.pendiente);

        for (final clave in clavesObligatorias) {
          expect(tarea(tareas, clave).estado, EstadoTarea.completada);
        }

        expect(puedeActivar(tareas), isTrue);
      },
    );

    test('las tareas se derivan de hechos, no se marcan a mano', () {
      final tareas = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(tieneAlmacen: true),
      );

      expect(tarea(tareas, 'almacen').estado, EstadoTarea.completada);
      expect(tarea(tareas, 'tpv').estado, EstadoTarea.pendiente);
    });

    test('un estado guardado tiene la última palabra sobre el hecho', () {
      final tareas = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(tieneAlmacen: true),
        estadosGuardados: const {'almacen': EstadoTarea.pendiente},
      );

      expect(tarea(tareas, 'almacen').estado, EstadoTarea.pendiente);
      expect(puedeActivar(tareas), isFalse);
    });
  });

  group('restaurante', () {
    test('incluye cocina, mesas y modo restaurante; retail no', () {
      final restaurante = construirTareas(
        tipoNegocio: 'restaurante',
        hechos: const HechosTienda(),
      );
      final retail = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(),
      );

      expect(
        claves(restaurante),
        containsAll(['cocina', 'mesas_restaurante', 'modo_restaurante']),
      );
      expect(
        claves(retail),
        isNot(contains('cocina')),
        reason: 'la cocina solo se recomienda en restaurante',
      );
      expect(claves(retail), isNot(contains('mesas_restaurante')));
      expect(claves(retail), isNot(contains('modo_restaurante')));
    });

    test('mesas es informativa: sin ruta y sin bloquear', () {
      final tareas = construirTareas(
        tipoNegocio: 'restaurante',
        hechos: const HechosTienda(almacenesConvertiblesACocina: 1),
      );
      final mesas = tarea(tareas, 'mesas_restaurante');

      expect(mesas.ruta, isNull);
      expect(mesas.obligatoria, isFalse);
      expect(mesas.accionable, isFalse);
      // El beneficio tiene que decir dónde se crean de verdad.
      expect(mesas.beneficio.toLowerCase(), contains('ventiq_app'));
    });

    test('modo restaurante activo pero cocina inactiva: queda pendiente', () {
      final tareas = construirTareas(
        tipoNegocio: 'restaurante',
        hechos: const HechosTienda(
          modoRestaurante: true,
          cocinaActiva: false,
          almacenesConvertiblesACocina: 2,
        ),
      );

      expect(tarea(tareas, 'cocina').estado, EstadoTarea.pendiente);
      // El modo restaurante ya está encendido; la cocina todavía no.
      expect(tarea(tareas, 'modo_restaurante').estado, EstadoTarea.completada);
      expect(progreso(tareas).completadas, 1);
    });

    test('el caso crítico: 1 almacén + 1 TPV bloquea la cocina', () {
      final tareas = construirTareas(
        tipoNegocio: 'restaurante',
        hechos: const HechosTienda(
          tieneAlmacen: true,
          tieneTpv: true,
          modoRestaurante: true,
          cocinaActiva: false,
          // listarAlmacenesConvertibles descarta el único almacén.
          almacenesConvertiblesACocina: 0,
        ),
      );
      final cocina = tarea(tareas, 'cocina');

      expect(cocina.motivoBloqueo, isNotNull);
      expect(cocina.motivoBloqueo, contains('TPV'));
      expect(cocina.ruta, isNull, reason: 'no se ofrece un desplegable vacío');
      expect(cocina.bloqueada, isTrue);
      expect(cocina.accionable, isFalse);
      expect(cocina.obligatoria, isFalse);
    });

    test('con un almacén convertible la cocina sí es accionable', () {
      final tareas = construirTareas(
        tipoNegocio: 'restaurante',
        hechos: const HechosTienda(almacenesConvertiblesACocina: 1),
      );
      final cocina = tarea(tareas, 'cocina');

      expect(cocina.motivoBloqueo, isNull);
      expect(cocina.ruta, isNotNull);
      expect(cocina.accionable, isTrue);
    });
  });

  group('catalogo', () {
    test('no pide almacén, TPV ni cobro; sí producto', () {
      final tareas = construirTareas(
        tipoNegocio: 'catalogo',
        hechos: const HechosTienda(),
      );

      expect(claves(tareas), isNot(contains('almacen')));
      expect(claves(tareas), isNot(contains('tpv')));
      expect(claves(tareas), isNot(contains('cobro')));
      expect(claves(tareas), contains('producto'));
      expect(claves(tareas), contains('moneda'));
    });

    test('solo el producto bloquea para un catálogo', () {
      final sinNada = construirTareas(
        tipoNegocio: 'catalogo',
        hechos: const HechosTienda(),
      );
      expect(puedeActivar(sinNada), isFalse);
      expect(sinNada.where((t) => t.obligatoria).map((t) => t.clave), [
        'producto',
      ]);

      final conProducto = construirTareas(
        tipoNegocio: 'catalogo',
        hechos: const HechosTienda(tieneProducto: true),
      );
      expect(puedeActivar(conProducto), isTrue);
    });
  });

  group('servicentro', () {
    test('incluye servicentro_tpv y las esenciales de mostrador', () {
      final tareas = construirTareas(
        tipoNegocio: 'servicentro',
        hechos: const HechosTienda(),
      );

      expect(claves(tareas), contains('servicentro_tpv'));
      expect(claves(tareas), containsAll(clavesObligatorias));
      expect(claves(tareas), isNot(contains('cocina')));
      expect(
        tarea(tareas, 'servicentro_tpv').obligatoria,
        isFalse,
        reason: 'el modo por TPV es una advertencia, no un gate',
      );
    });
  });

  group('tipo de negocio sin declarar', () {
    test('null se comporta como retail', () {
      final sinTipo = construirTareas(
        tipoNegocio: null,
        hechos: const HechosTienda(),
      );
      final retail = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(),
      );

      expect(claves(sinTipo), claves(retail));
      expect(puedeActivar(sinTipo), isFalse);
      expect(
        sinTipo.where((t) => t.obligatoria).map((t) => t.clave).toList(),
        clavesObligatorias,
      );
    });

    test('vacío y desconocido también caen en retail', () {
      final retail = claves(
        construirTareas(tipoNegocio: 'retail', hechos: const HechosTienda()),
      );

      for (final tipo in ['', '   ', 'panaderia']) {
        expect(
          claves(
            construirTareas(tipoNegocio: tipo, hechos: const HechosTienda()),
          ),
          retail,
          reason: 'tipo "$tipo" debe tratarse como retail',
        );
      }
    });
  });

  group('gate y progreso', () {
    test('una obligatoria omitida impide activar', () {
      final tareas = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(
          tieneAlmacen: true,
          tieneTpv: true,
          tieneProducto: true,
          tieneVendedorAsignado: true,
        ),
      );
      expect(puedeActivar(tareas), isTrue);

      final conOmitida = [
        for (final t in tareas)
          if (t.clave == 'tpv')
            TareaOnboarding(
              clave: t.clave,
              titulo: t.titulo,
              beneficio: t.beneficio,
              obligatoria: t.obligatoria,
              estado: EstadoTarea.omitida,
              ruta: t.ruta,
            )
          else
            t,
      ];

      expect(puedeActivar(conOmitida), isFalse);
      expect(tareasBloqueantes(conOmitida).map((t) => t.clave), ['tpv']);
    });

    test('omitir una tarea que no aplica no cuenta en el total', () {
      final tareas = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(
          tieneAlmacen: true,
          tieneTpv: true,
          tieneProducto: true,
          tieneVendedorAsignado: true,
        ),
        estadosGuardados: const {'personal': EstadoTarea.omitida},
      );

      final p = progreso(tareas);
      expect(p.completadas, 4);
      // 8 tareas retail, una omitida: el total baja a 7.
      expect(p.total, tareas.length - 1);
    });

    test('sin obligatorias pendientes puedeActivar es true', () {
      expect(puedeActivar(const []), isTrue);
    });
  });
}
