package com.example.ventiq_admin_app.widgets

/**
 * Deep links que abren la app desde un widget.
 *
 * Los consume Dart en `HomeWidgetLauncher` (`lib/widgets_home/`), que decide a
 * qué pantalla navegar. El host identifica el destino y los parámetros llevan el
 * tipo de widget y su appWidgetId para poder reconfigurar esa instancia concreta.
 */
object VqDeepLinks {

    private const val SCHEME = "ventiqwidget"

    const val HOST_DASHBOARD = "dashboard"
    const val HOST_SALES = "sales"
    const val HOST_PRODUCT = "product"
    const val HOST_CONFIGURE = "configure"

    private fun build(host: String, prefix: String, appWidgetId: Int): String =
        "$SCHEME://$host?type=$prefix&id=$appWidgetId"

    fun dashboard(prefix: String, appWidgetId: Int): String =
        build(HOST_DASHBOARD, prefix, appWidgetId)

    fun sales(prefix: String, appWidgetId: Int): String =
        build(HOST_SALES, prefix, appWidgetId)

    fun product(prefix: String, appWidgetId: Int, productId: Int): String =
        "${build(HOST_PRODUCT, prefix, appWidgetId)}&producto=$productId"

    /** Abre la pantalla de configuración de esa instancia dentro de la app. */
    fun configure(prefix: String, appWidgetId: Int): String =
        build(HOST_CONFIGURE, prefix, appWidgetId)
}
