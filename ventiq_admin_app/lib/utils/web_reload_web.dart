// Implementación Web: recarga real del navegador para destruir todo el
// estado en memoria (singletons, cachés) que Flutter Web mantiene vivo
// mientras la pestaña no se recarga.
import 'dart:html' as html;

/// Recarga la página actual conservando la ruta.
void reloadPage() {
  html.window.location.reload();
}

/// Navega a la raíz forzando una carga completa (no una navegación SPA).
/// Útil tras cerrar sesión: el splash detectará que no hay sesión y
/// redirigirá al login con todos los servicios recién instanciados.
void reloadToRoot() {
  html.window.location.assign('/');
}
