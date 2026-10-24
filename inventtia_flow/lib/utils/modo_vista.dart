/// Qué conjunto de pantallas le toca al shell de Home.
///
/// Un mismo usuario puede ser varias cosas a la vez (dueño de una entidad y
/// cliente de otros locales, o incluso admin y vendedor), y antes el shell
/// elegía por él sin salida: si eras admin, **nunca** veías la app como la ve un
/// cliente. Ahora el admin puede pedir «ver como cliente» y volver.
enum VistaShell {
  /// Home del catálogo (Inicio, Servicios, Mis Listas, Reservas, Perfil).
  ///
  /// Es la vista de un cliente puro y también la de un admin que pidió verla
  /// como cliente.
  cliente,

  /// Gestión + Perfil.
  admin,

  /// Reservas + Perfil.
  vendedor,

  /// Reservas + Gestión + Perfil.
  vendedorAdmin,
}

/// Decide la vista del shell.
///
/// [comoCliente] es el interruptor que enciende el admin, y **solo cuenta si el
/// usuario es admin**: un vendedor que no administra nada no tiene ese
/// interruptor, y si por lo que sea llegara encendido se ignora (no se le puede
/// dejar sin sus pantallas de trabajo).
VistaShell vistaDelShell({
  required bool esAdmin,
  required bool esVendedor,
  required bool comoCliente,
}) {
  if (esAdmin && !comoCliente) {
    return esVendedor ? VistaShell.vendedorAdmin : VistaShell.admin;
  }
  if (esAdmin) return VistaShell.cliente;
  if (esVendedor) return VistaShell.vendedor;
  return VistaShell.cliente;
}

/// ¿Este usuario puede alternar entre la vista de administración y la de
/// cliente? Solo quien administra una entidad.
bool puedeVerComoCliente({required bool esAdmin}) => esAdmin;

/// ¿Esta vista es la del cliente (la que pinta la barra de 5 pestañas)?
bool esVistaCliente(VistaShell vista) => vista == VistaShell.cliente;
