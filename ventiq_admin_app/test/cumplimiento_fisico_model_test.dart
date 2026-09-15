import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/cumplimiento_fisico.dart';

void main() {
  test('interpreta el plan exitoso completo', () {
    final plan = PlanCumplimiento.fromJson({
      'status': 'success',
      'mensaje_usuario': 'Cubierto',
      'id_producto': 10,
      'id_ubicacion': 349,
      'id_presentacion_solicitada': 33,
      'cantidad_solicitada': '16',
      'equivalente_solicitado': 16,
      'equivalente_cumplido': '16',
      'equivalente_disponible': '55',
      'maximo_servible': 55,
      'estrategia': 'mixto_con_apertura',
      'lineas_fisicas': [
        {
          'id_presentacion': 31,
          'nombre': 'Bulto',
          'cantidad': 1,
          'factor_entero': 5,
          'equivalente': 5,
          'origen': 'empaque_cerrado',
        },
        {
          'id_presentacion': 33,
          'nombre': 'Unidad',
          'cantidad': 10,
          'factor_entero': 1,
          'equivalente': 10,
          'origen': 'propio',
        },
        {
          'id_presentacion': 33,
          'nombre': 'Unidad',
          'cantidad': 1,
          'factor_entero': 1,
          'equivalente': 1,
          'origen': 'apertura',
        },
      ],
      'conversiones': [
        {
          'tipo': 'apertura',
          'id_presentacion_origen': 31,
          'cantidad_origen': 1,
          'patas': [
            {
              'tipo': 'salida',
              'id_presentacion': 31,
              'cantidad': 1,
              'factor_entero': 5,
              'equivalente': 5,
            },
          ],
        },
      ],
      'saldos_proyectados': [
        {
          'id_presentacion': 33,
          'nombre': 'Unidad',
          'cantidad': 4,
          'factor_entero': 1,
          'equivalente': 4,
        },
      ],
    });

    expect(plan.esExitoso, isTrue);
    expect(plan.requiereConversion, isTrue);
    expect(plan.maximoServible, 55);
    expect(plan.lineasFisicas, hasLength(3));
    expect(plan.lineasFisicas.last.origen, 'apertura');
    expect(plan.conversiones.single.patas.single.idPresentacion, 31);
    expect(plan.saldosProyectados.single.cantidad, 4);
  });

  test('interpreta errores y tolera listas ausentes', () {
    final plan = PlanCumplimiento.fromJson({
      'status': 'error',
      'error_code': 'INSUFFICIENT_STOCK',
      'message': 'Stock insuficiente',
      'maximo_servible': '5',
    });

    expect(plan.esExitoso, isFalse);
    expect(plan.requiereConversion, isFalse);
    expect(plan.errorCode, 'INSUFFICIENT_STOCK');
    expect(plan.mensaje, 'Stock insuficiente');
    expect(plan.maximoServible, 5);
    expect(plan.lineasFisicas, isEmpty);
  });
}
