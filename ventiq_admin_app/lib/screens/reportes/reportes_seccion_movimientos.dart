/// Sección 3 de Reportes: movimientos por día, inversores y pendientes
/// (aging de reservas + compras con descuadre).
///
/// Los contadores de la franja de pendientes y las filas de las dos tarjetas
/// gemelas salen **de la misma lista**: no puede pasar que la franja diga 4 y
/// la tarjeta pinte 3. Con listas vacías se dice explícitamente que no hay
/// nada; nunca se pinta una tabla con cabecera y cero filas.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../compras/compras_widgets.dart' show chipEstadoCompra;
import 'reportes_calculos.dart';
import 'reportes_widgets.dart';

class SeccionMovimientos extends StatelessWidget {
  final BloqueReporte movimientos;
  final BloqueReporte inversores;
  final BloqueReporte aging;
  final VoidCallback onReintentar;

  const SeccionMovimientos({
    super.key,
    required this.movimientos,
    required this.inversores,
    required this.aging,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaMovimientos(),
        const SizedBox(height: 16),
        _tarjetaInversores(),
        const SizedBox(height: 16),
        _tarjetaPendientes(),
      ],
    );
  }

  // ==========================================================================
  // Movimientos por día y usuario
  // ==========================================================================

  Widget _tarjetaMovimientos() {
    if (movimientos.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Movimientos por usuario y día'),
          errorReporte(mensaje: movimientos.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!movimientos.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Movimientos por usuario y día'),
          panelCargandoReporte(texto: 'Cargando movimientos…'),
        ],
      );
    }

    final filas = listaDeMapas(movimientos.datos?['por_dia_usuario']);
    final totales = listaDeMapas(movimientos.datos?['totales_por_moneda']);
    final porDia = agruparMovimientosPorDia(filas);
    final nMovimientos = filas.fold<int>(
      0,
      (suma, fila) => suma + numero(fila['n']).round(),
    );

    return panelReporte(
      children: [
        cabeceraReporte(
          'Movimientos por usuario y día',
          subtitulo:
              '$nMovimientos ${nMovimientos == 1 ? 'movimiento' : 'movimientos'} '
              'en ${porDia.length} ${porDia.length == 1 ? 'día' : 'días'} · '
              'cada importe va en su moneda.',
          trailing: notaReporte('Neto = entradas − salidas.'),
        ),
        if (filas.isEmpty)
          mensajeVacioReporte(
            titulo: 'Sin movimientos en el periodo',
            detalle:
                'No se registraron entradas ni salidas del fondo dentro de la '
                'ventana. Prueba con otro rango de fechas.',
            icono: Icons.swap_vert,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Usuario', 20),
              ColumnaReporte('Moneda', 8),
              ColumnaReporte('Movs', 7, derecha: true),
              ColumnaReporte('Entradas', 12, derecha: true),
              ColumnaReporte('Salidas', 12, derecha: true),
              ColumnaReporte('Neto', 12, derecha: true),
            ],
            filas: _filasMovimientos(porDia, totales),
          ),
      ],
    );
  }

  List<FilaReporte> _filasMovimientos(
    Map<DateTime, List<Map<String, dynamic>>> porDia,
    List<Map<String, dynamic>> totales,
  ) {
    final resultado = <FilaReporte>[];
    for (final entrada in porDia.entries) {
      final filasDia = entrada.value;
      final subtotales = subtotalesMoneda(filasDia);
      final nDia = filasDia.fold<int>(
        0,
        (suma, fila) => suma + numero(fila['n']).round(),
      );
      resultado.add(
        FilaReporte.banda(_bandaDia(entrada.key, nDia, subtotales)),
      );
      for (final fila in filasDia) {
        resultado.add(_filaMovimiento(fila));
      }
    }
    for (final total in totales) {
      resultado.add(_filaTotalMovimiento(total));
    }
    return resultado;
  }

  Widget _bandaDia(
    DateTime dia,
    int n,
    Map<String, SubtotalMoneda> subtotales,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            etiquetaDia(dia),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '$n ${n == 1 ? 'movimiento' : 'movimientos'}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          for (final subtotal in subtotales.entries)
            Text(
              subtotal.key.trim().isEmpty
                  ? cifraConSigno(subtotal.value.neto)
                  : '${subtotal.key} ${cifraConSigno(subtotal.value.neto)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: subtotal.value.neto < 0 ? naranjaTexto : verdeTexto,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  FilaReporte _filaMovimiento(Map<String, dynamic> fila) {
    final neto = numero(fila['neto']);
    return FilaReporte([
      celdaTexto(textoOGuion(fila['usuario'])),
      celdaTexto(monedaDe(fila), negrita: true),
      celdaCifra(cifra(numero(fila['n']))),
      celdaCifra(cifra(numero(fila['entradas']))),
      celdaCifra(cifra(numero(fila['salidas']))),
      celdaCifra(
        cifraConSigno(neto),
        negrita: true,
        color: neto < 0 ? naranjaTexto : null,
      ),
    ]);
  }

  FilaReporte _filaTotalMovimiento(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    final neto = numero(total['neto']);
    return FilaReporte([
      celdaTexto('Total del rango', negrita: true),
      celdaTexto(moneda, negrita: true),
      celdaCifra(cifra(numero(total['n'])), negrita: true),
      celdaCifra(cifra(numero(total['entradas'])), negrita: true),
      celdaCifra(cifra(numero(total['salidas'])), negrita: true),
      celdaCifra(
        cifraConSigno(neto),
        negrita: true,
        color: neto < 0 ? naranjaTexto : null,
      ),
    ], resaltada: true);
  }

  // ==========================================================================
  // Inversores
  // ==========================================================================

  Widget _tarjetaInversores() {
    if (inversores.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Inversores'),
          errorReporte(mensaje: inversores.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!inversores.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Inversores'),
          panelCargandoReporte(texto: 'Cargando inversores…'),
        ],
      );
    }

    final filas = listaDeMapas(inversores.datos?['inversores']);
    final totales = listaDeMapas(inversores.datos?['totales_por_moneda']);

    return panelReporte(
      children: [
        cabeceraReporte(
          'Inversores',
          subtitulo:
              'Aportes vigentes, devueltos y utilidad repartida, pagada y '
              'pendiente · saldos a hoy.',
          trailing: notaReporte('Totales por moneda.'),
        ),
        if (filas.isEmpty)
          mensajeVacioReporte(
            titulo: 'Sin inversores registrados',
            detalle:
                'Cuando la tienda tenga inversores con aportes o repartos, '
                'aparecerán aquí con su moneda explícita.',
            icono: Icons.groups_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Inversor', 20),
              ColumnaReporte('Moneda', 8),
              ColumnaReporte('Aportes vigentes', 13, derecha: true),
              ColumnaReporte('Devueltos', 12, derecha: true),
              ColumnaReporte('Utilidad repartida', 13, derecha: true),
              ColumnaReporte('Utilidad pagada', 12, derecha: true),
              ColumnaReporte('Utilidad pendiente', 13, derecha: true),
            ],
            filas: [
              for (final fila in filas) ..._filasInversor(fila),
              for (final total in totales) _filaTotalInversor(total),
            ],
          ),
      ],
    );
  }

  /// Una fila por inversor y moneda. Un inversor sin movimientos devuelve
  /// `por_moneda` vacío: se pinta una fila con guiones, no se oculta.
  List<FilaReporte> _filasInversor(Map<String, dynamic> inversor) {
    final nombre = textoOGuion(inversor['nombre']);
    final porcentaje = numeroONulo(inversor['porcentaje']);
    final activo = booleano(inversor['activo']);
    final subtitulo = [
      if (porcentaje != null) '${cifraPorcentaje(porcentaje)} %',
      activo ? 'activo' : 'inactivo',
    ].join(' · ');
    final porMoneda = listaDeMapas(inversor['por_moneda']);

    if (porMoneda.isEmpty) {
      return [
        FilaReporte([
          celdaDoble(nombre, subtitulo),
          celdaTexto('—', color: AppColors.textLight),
          celdaCifra('—', color: AppColors.textLight),
          celdaCifra('—', color: AppColors.textLight),
          celdaCifra('—', color: AppColors.textLight),
          celdaCifra('—', color: AppColors.textLight),
          celdaCifra('—', color: AppColors.textLight),
        ]),
      ];
    }

    return [
      for (var i = 0; i < porMoneda.length; i++)
        FilaReporte([
          celdaDoble(nombre, i == 0 ? subtitulo : null),
          celdaTexto(monedaDe(porMoneda[i]), negrita: true),
          celdaCifra(cifra(numero(porMoneda[i]['aportes_vigentes']))),
          celdaCifra(cifra(numero(porMoneda[i]['aportes_devueltos']))),
          celdaCifra(cifra(numero(porMoneda[i]['utilidad_repartida']))),
          celdaCifra(cifra(numero(porMoneda[i]['utilidad_pagada']))),
          celdaCifra(
            cifra(numero(porMoneda[i]['utilidad_pendiente'])),
            negrita: true,
            color: numero(porMoneda[i]['utilidad_pendiente']) > 0
                ? rojoTexto
                : null,
          ),
        ]),
    ];
  }

  FilaReporte _filaTotalInversor(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    return FilaReporte([
      celdaTexto('Total $moneda', negrita: true),
      celdaTexto(moneda, negrita: true),
      celdaCifra(cifra(numero(total['aportes_vigentes'])), negrita: true),
      celdaCifra(cifra(numero(total['aportes_devueltos'])), negrita: true),
      celdaCifra(cifra(numero(total['utilidad_repartida'])), negrita: true),
      celdaCifra(cifra(numero(total['utilidad_pagada'])), negrita: true),
      celdaCifra(
        cifra(numero(total['utilidad_pendiente'])),
        negrita: true,
        color: numero(total['utilidad_pendiente']) > 0 ? rojoTexto : null,
      ),
    ], resaltada: true);
  }

  // ==========================================================================
  // Pendientes: aging + descuadres
  // ==========================================================================

  Widget _tarjetaPendientes() {
    if (aging.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Pendientes y descuadres'),
          errorReporte(mensaje: aging.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!aging.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Pendientes y descuadres'),
          panelCargandoReporte(texto: 'Cargando pendientes…'),
        ],
      );
    }

    final reservas = listaDeMapas(aging.datos?['reservas_activas']);
    final descuadres = listaDeMapas(aging.datos?['descuadres']);
    final viejas = reservas
        .where((fila) => numero(fila['dias_antiguedad']) > 7)
        .length;
    final alarma = descuadres.isNotEmpty || viejas > 0;

    return panelReporte(
      children: [
        cabeceraReporte(
          'Pendientes y descuadres',
          subtitulo:
              'Reservas activas por antigüedad y compras cuyo financiado no '
              'coincide con sus líneas, ajustes o pagos.',
          trailing: notaReporte(
            'Reservas y descuadres declarados en el servidor.',
          ),
        ),
        franjaResumen(
          icono: alarma ? Icons.error_outline : Icons.check_circle_outline,
          color: alarma ? rojoTexto : verdeTexto,
          fondo: alarma ? rojoFondo : verdeFondo,
          borde: alarma ? rojoBorde : verdeBorde,
          children: [
            if (alarma) ...[
              if (descuadres.isNotEmpty)
                Text(
                  '${descuadres.length} '
                  '${descuadres.length == 1 ? 'compra' : 'compras'} con '
                  'descuadre abierto',
                ),
              if (reservas.isNotEmpty)
                Text(
                  '${reservas.length} '
                  '${reservas.length == 1 ? 'reserva activa' : 'reservas activas'}'
                  '${viejas > 0 ? ' · $viejas con más de 7 días' : ''}',
                ),
            ] else
              const Text(
                'Sin pendientes abiertos: ninguna compra descuadrada ni '
                'reservas con más de 7 días.',
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final agingCard = _tarjetaAging(reservas);
            final descuadresCard = _tarjetaDescuadres(descuadres);
            if (constraints.maxWidth < 980) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  agingCard,
                  const SizedBox(height: 12),
                  descuadresCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: agingCard),
                const SizedBox(width: 12),
                Expanded(child: descuadresCard),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _tarjetaAging(List<Map<String, dynamic>> reservas) {
    return panelReporte(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        cabeceraReporte(
          'Aging de reservas',
          subtitulo: 'Días del dinero comprometido sin compra cerrada.',
        ),
        if (reservas.isEmpty)
          mensajeVacioReporte(
            titulo: 'No hay reservas activas',
            detalle:
                'Ningún dinero del fondo está comprometido esperando una '
                'compra cerrada.',
            icono: Icons.lock_clock_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Días', 8, derecha: true),
              ColumnaReporte('Compra', 20),
              ColumnaReporte('Monto', 16, derecha: true),
              ColumnaReporte('Estado', 18),
            ],
            filas: [for (final fila in reservas) _filaAging(fila)],
          ),
      ],
    );
  }

  FilaReporte _filaAging(Map<String, dynamic> fila) {
    final numeroCompra = textoONulo(fila['numero_compra']);
    final factura = textoONulo(fila['numero_factura']);
    final dias = numero(fila['dias_antiguedad']).round();
    final moneda = monedaDe(fila);
    return FilaReporte([
      celdaCifra('$dias', negrita: true),
      celdaDoble(
        numeroCompra == null ? '—' : '#$numeroCompra',
        factura == null ? null : 'Factura $factura',
      ),
      celdaCifra(
        moneda.trim().isEmpty
            ? cifra(numero(fila['monto']))
            : '${cifra(numero(fila['monto']))} $moneda',
      ),
      celdaChip(
        chipEstadoCompra(textoOGuion(fila['estado_compra']), denso: true),
      ),
    ]);
  }

  Widget _tarjetaDescuadres(List<Map<String, dynamic>> descuadres) {
    return panelReporte(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        cabeceraReporte(
          'Compras con descuadre',
          subtitulo: 'Diferencia entre lo financiado y los pagos.',
        ),
        if (descuadres.isEmpty)
          mensajeVacioReporte(
            titulo: 'Ninguna compra con descuadre',
            detalle:
                'El financiado de cada compra coincide con sus líneas, ajustes '
                'del fondo y pagos.',
            icono: Icons.verified_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Compra', 22),
              ColumnaReporte('Dif. financiado', 14, derecha: true),
              ColumnaReporte('Dif. pagos', 14, derecha: true),
              ColumnaReporte('Último motivo', 30),
            ],
            filas: [for (final fila in descuadres) _filaDescuadre(fila)],
          ),
      ],
    );
  }

  FilaReporte _filaDescuadre(Map<String, dynamic> fila) {
    final numeroCompra = textoONulo(fila['numero_compra']);
    final factura = textoONulo(fila['numero_factura']);
    final estado = textoONulo(fila['estado_compra']);
    final moneda = monedaDe(fila, guion: '');
    final difFinanciado = numero(fila['diferencia_financiado']);
    final difPagos = numero(fila['diferencia_pagos']);
    final motivo = textoONulo(fila['ultimo_motivo']);

    final piezas = <String>[
      if (factura != null) 'Factura $factura',
      if (estado != null) CompraEstado.etiquetaDe(estado),
    ];

    return FilaReporte([
      celdaDoble(
        numeroCompra == null ? '—' : '#$numeroCompra',
        piezas.isEmpty ? null : piezas.join(' · '),
      ),
      celdaCifra(
        _cifraConMoneda(difFinanciado, moneda),
        negrita: true,
        color: difFinanciado.abs() > umbralDescuadre ? rojoTexto : null,
      ),
      celdaCifra(
        _cifraConMoneda(difPagos, moneda),
        negrita: true,
        color: difPagos.abs() > umbralDescuadre ? rojoTexto : null,
      ),
      celdaTexto(
        motivo ?? '—',
        color: motivo == null ? AppColors.textLight : AppColors.textSecondary,
        maxLineas: 2,
      ),
    ]);
  }

  String _cifraConMoneda(double valor, String moneda) {
    final texto = cifraConSigno(valor);
    return moneda.trim().isEmpty ? texto : '$texto $moneda';
  }
}
