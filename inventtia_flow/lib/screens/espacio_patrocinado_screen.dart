import 'package:flutter/material.dart';

import '../models/ficha_local.dart';
import '../services/campana_service.dart';
import 'ficha_local_screen.dart';

/// Envoltorio del espacio patrocinado: abre la ficha comercial del local
/// destacado por una campaña.
///
/// POR QUE EXISTE (y por qué es solo un envoltorio)
///   El cuerpo de esta vista (cabecera, datos del local, contacto y **todos** sus
///   servicios reservables) se mudó a [FichaLocalScreen], porque es exactamente
///   la misma vista que el usuario espera al tocar un establecimiento en el
///   listado. Si el cuerpo viviera aquí, el listado dependería de una campaña
///   para pintar un local que no tiene ninguna.
///
///   Este archivo se queda con la MISMA firma pública de siempre
///   (`EspacioPatrocinadoScreen({required campana})`) a propósito: el carrusel del
///   Home (`home_client_screen._abrirCampana`) construye esta clase tal cual, y no
///   se toca. Así el espacio patrocinado sigue pintándose igual —sello «ESPACIO
///   PATROCINADO», degradado de la campaña y bloque «DESTACADO DEL MOMENTO»—
///   porque `campana != null` activa ese modo en la pantalla compartida.
class EspacioPatrocinadoScreen extends StatelessWidget {
  const EspacioPatrocinadoScreen({super.key, required this.campana});

  final CampanaPatrocinada campana;

  @override
  Widget build(BuildContext context) {
    // La ficha se normaliza aquí (una sola vez) y la campaña se pasa además como
    // marca de modo: la pantalla no vuelve a leer el modelo de campaña.
    return FichaLocalScreen(
      ficha: FichaLocal.desdeCampana(campana),
      campana: campana,
    );
  }
}
