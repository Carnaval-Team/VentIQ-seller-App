package com.example.ventiq_admin_app.widgets

/**
 * Contrato de claves compartido entre Dart (`lib/widgets_home/widget_keys.dart`)
 * y los widgets nativos de Glance.
 *
 * REGLA IMPORTANTE: todos los valores numéricos se guardan como String desde Dart.
 * `home_widget` serializa los `double` como los bits crudos de un Long más una
 * clave auxiliar `home_widget.double.<key>`, lo que obliga a decodificar a mano y
 * es una fuente constante de errores. Guardando texto y parseando con
 * `toDoubleOrNull()` el contrato queda explícito y a prueba de cambios del plugin.
 *
 * Cada instancia de widget tiene su propia configuración, por eso las claves
 * llevan el appWidgetId incrustado: `<prefijo>_<appWidgetId>_<campo>`.
 */
object WidgetKeys {

    /** SharedPreferences que usa el plugin home_widget. */
    const val PREFERENCES = "HomeWidgetPreferences"

    // ── Claves globales (compartidas por todas las instancias) ────────────────
    /** Tasa USD→CUP vigente, como String. */
    const val USD_RATE = "vq_usd_rate"

    /** Marca de tiempo ISO-8601 del último refresco global. */
    const val LAST_SYNC = "vq_last_sync"

    /** "1" si hay una sesión de Supabase utilizable en background. */
    const val SESSION_OK = "vq_session_ok"

    // ── Prefijos por tipo de widget ──────────────────────────────────────────
    const val PREFIX_MINI_DASHBOARD = "vq_md"
    const val PREFIX_SALES = "vq_sv"
    const val PREFIX_PRODUCT = "vq_pt"

    // ── Campos comunes a las tres instancias ─────────────────────────────────
    /** unconfigured | loading | ok | error */
    const val FIELD_STATE = "state"
    const val FIELD_ERROR = "error"
    const val FIELD_UPDATED_AT = "updated_at"
    const val FIELD_STORE_ID = "tienda_id"
    const val FIELD_STORE_NAME = "tienda_nombre"

    // ── Mini Dashboard ───────────────────────────────────────────────────────
    /** Periodo del Dashboard: '3 años' | '1 año' | '6 meses' | '3 meses' | '1 mes' | 'Semana' | 'Día'. */
    const val FIELD_PERIODO = "periodo"
    const val FIELD_VENTAS = "ventas"
    const val FIELD_GASTOS = "gastos"
    const val FIELD_GANANCIA_NETA = "ganancia_neta"
    const val FIELD_ORDENES = "ordenes"
    const val FIELD_DELTA_PCT = "delta_pct"

    /** Serie del mini-gráfico: valores separados por ';' (mismos datos que tendencias_de_venta). */
    const val FIELD_TREND = "trend"

    /** Etiquetas del eje X separadas por ';'. */
    const val FIELD_TREND_LABELS = "trend_labels"

    // ── Sales / TPV ──────────────────────────────────────────────────────────
    /** realtime | range */
    const val FIELD_MODO = "modo"
    const val MODO_REALTIME = "realtime"
    const val MODO_RANGE = "range"

    const val FIELD_DESDE = "desde"
    const val FIELD_HASTA = "hasta"
    const val FIELD_TOTAL = "total"
    const val FIELD_EFECTIVO = "efectivo"
    const val FIELD_TRANSFERENCIA = "transferencia"
    const val FIELD_EGRESOS = "egresos"

    /**
     * Desglose por TPV/vendedor. JSON array de objetos:
     * `[{"nombre":"...","total":0.0,"efectivo":0.0,"transferencia":0.0,"egresos":0.0,"ventas":0}]`
     */
    const val FIELD_TPVS = "tpvs"

    /** "1" cuando la tarjeta está desplegada mostrando el desglose por TPV. */
    const val FIELD_EXPANDED = "expanded"

    // ── Product Tracking ─────────────────────────────────────────────────────
    const val FIELD_PRODUCTO_ID = "producto_id"
    const val FIELD_PRODUCTO_NOMBRE = "producto_nombre"
    const val FIELD_PRECIO_VENTA = "precio_venta"
    const val FIELD_COSTO_CUP = "costo_cup"
    const val FIELD_COSTO_USD = "costo_usd"
    const val FIELD_TOTAL_VENDIDO = "total_vendido"
    const val FIELD_INGRESOS = "ingresos"
    const val FIELD_STOCK = "stock"

    // ── Estados ──────────────────────────────────────────────────────────────
    const val STATE_UNCONFIGURED = "unconfigured"
    const val STATE_LOADING = "loading"
    const val STATE_OK = "ok"
    const val STATE_ERROR = "error"

    /** Construye `<prefijo>_<appWidgetId>_<campo>`. */
    fun key(prefix: String, appWidgetId: Int, field: String): String =
        "${prefix}_${appWidgetId}_$field"

    // ── URIs de las acciones que despiertan código Dart en background ─────────
    const val URI_SCHEME = "ventiqwidget"
    const val HOST_REFRESH = "refresh"
    const val HOST_TOGGLE = "toggle"

    /** ventiqwidget://refresh?type=vq_md&id=123 */
    fun refreshUri(prefix: String, appWidgetId: Int): String =
        "$URI_SCHEME://$HOST_REFRESH?type=$prefix&id=$appWidgetId"

    /** ventiqwidget://toggle?type=vq_sv&id=123 */
    fun toggleUri(prefix: String, appWidgetId: Int): String =
        "$URI_SCHEME://$HOST_TOGGLE?type=$prefix&id=$appWidgetId"
}
