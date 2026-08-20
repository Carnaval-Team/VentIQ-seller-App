package com.example.ventiq_admin_app.widgets

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.example.ventiq_admin_app.R
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import org.json.JSONArray

/**
 * Widget de Ventas / TPV.
 *
 * Modo Tiempo Real (chip "EN VIVO" verde) o Rango de fechas (chip azul con las
 * fechas). Muestra dinero total, efectivo, transferencia y egresos, y se puede
 * desplegar para ver el desglose por TPV/vendedor.
 *
 * Datos: RPC `fn_reporte_ventas_por_vendedor_sch` + `fn_listar_entregas_por_fechas_usuario`
 * para los egresos, exactamente como la pestaña TPVs de SalesScreen.
 */
class SalesTpvWidget : GlanceAppWidget() {

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appWidgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        provideContent { Content(context, appWidgetId, currentState()) }
    }

    @Composable
    private fun Content(
        context: Context,
        appWidgetId: Int,
        state: HomeWidgetGlanceState,
    ) {
        val prefs = VqWidgetPrefs(state.preferences, WidgetKeys.PREFIX_SALES, appWidgetId)
        val isRealtime = prefs.string(WidgetKeys.FIELD_MODO) != WidgetKeys.MODO_RANGE

        VqWidgetCard(
            context = context,
            deepLink = VqDeepLinks.sales(WidgetKeys.PREFIX_SALES, appWidgetId),
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                Text(
                    text = "Ventas",
                    style = TextStyle(
                        color = VqWidgetTheme.accentPrimary,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    maxLines = 1,
                )
                Spacer(modifier = GlanceModifier.width(6.dp))
                if (isRealtime) {
                    VqChip("● EN VIVO", VqWidgetTheme.accentSuccess)
                } else {
                    val desde = VqFormat.shortDate(prefs.string(WidgetKeys.FIELD_DESDE))
                    val hasta = VqFormat.shortDate(prefs.string(WidgetKeys.FIELD_HASTA))
                    VqChip("$desde → $hasta", VqWidgetTheme.accentInfo)
                }
                Spacer(modifier = GlanceModifier.defaultWeight())
                Text(
                    text = prefs.storeName,
                    style = VqWidgetTheme.captionStyle,
                    maxLines = 1,
                )
            }

            when (prefs.state) {
                WidgetKeys.STATE_UNCONFIGURED -> VqWidgetMessage(
                    "Sin configurar",
                    "Toca para elegir tienda y modo (tiempo real o rango).",
                )

                WidgetKeys.STATE_LOADING -> VqWidgetMessage(
                    "Actualizando…",
                    "Consultando las ventas por TPV.",
                )

                WidgetKeys.STATE_ERROR -> VqWidgetMessage(
                    "No se pudo actualizar",
                    prefs.error.ifEmpty { "Abre la app para reintentar." },
                )

                else -> Metrics(prefs, appWidgetId)
            }
        }
    }

    @Composable
    private fun Metrics(prefs: VqWidgetPrefs, appWidgetId: Int) {
        val total = prefs.double(WidgetKeys.FIELD_TOTAL)
        val efectivo = prefs.double(WidgetKeys.FIELD_EFECTIVO)
        val transferencia = prefs.double(WidgetKeys.FIELD_TRANSFERENCIA)
        val egresos = prefs.double(WidgetKeys.FIELD_EGRESOS)
        val expanded = prefs.bool(WidgetKeys.FIELD_EXPANDED)

        Spacer(modifier = GlanceModifier.height(8.dp))

        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.Vertical.Bottom,
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(text = "Dinero total", style = VqWidgetTheme.labelStyle, maxLines = 1)
                Text(
                    text = VqFormat.money(total),
                    style = VqWidgetTheme.valueStyle(VqWidgetTheme.accentSuccess, 22),
                    maxLines = 1,
                )
            }
            // Botón desplegar/plegar: dispara código Dart, que reescribe la
            // preferencia `expanded` y vuelve a pedir el redibujado.
            ExpandToggle(appWidgetId, expanded)
        }

        Spacer(modifier = GlanceModifier.height(8.dp))

        Row(modifier = GlanceModifier.fillMaxWidth()) {
            VqMetricCell(
                label = "Efectivo",
                value = VqFormat.money(efectivo),
                color = VqWidgetTheme.accentInfo,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "Transferencia",
                value = VqFormat.money(transferencia),
                color = VqWidgetTheme.accentPrimary,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "Egresos",
                value = VqFormat.money(egresos),
                color = VqWidgetTheme.accentError,
                modifier = GlanceModifier.defaultWeight(),
            )
        }

        if (expanded) {
            Spacer(modifier = GlanceModifier.height(8.dp))
            VqDivider()
            Spacer(modifier = GlanceModifier.height(6.dp))
            Text(text = "Por TPV", style = VqWidgetTheme.labelStyle, maxLines = 1)
            TpvBreakdown(prefs.string(WidgetKeys.FIELD_TPVS))
        }

        val updated = VqFormat.clock(prefs.updatedAt)
        if (updated.isNotEmpty()) {
            Spacer(modifier = GlanceModifier.height(6.dp))
            Text(text = "Actualizado $updated", style = VqWidgetTheme.captionStyle, maxLines = 1)
        }
    }

    @Composable
    private fun ExpandToggle(appWidgetId: Int, expanded: Boolean) {
        Row(
            modifier = GlanceModifier
                .background(ColorProvider(R.color.vq_widget_chip_bg))
                .cornerRadius(12.dp)
                .padding(horizontal = 10.dp, vertical = 5.dp)
                .clickable(
                    onClick = actionRunCallback<ToggleSalesBreakdownAction>(
                        actionParametersOf(appWidgetId)
                    )
                ),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            Text(
                text = if (expanded) "Ocultar ▲" else "Ver TPVs ▼",
                style = TextStyle(
                    color = VqWidgetTheme.accentPrimary,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
    }

    /**
     * Pinta el desglose por TPV. El JSON lo genera Dart agrupando el resultado
     * de `fn_reporte_ventas_por_vendedor_sch`.
     */
    @Composable
    private fun TpvBreakdown(json: String) {
        val rows = parseTpvRows(json)
        if (rows.isEmpty()) {
            Text(
                text = "Sin ventas registradas en el periodo.",
                style = VqWidgetTheme.captionStyle,
                maxLines = 2,
            )
            return
        }
        Column(modifier = GlanceModifier.fillMaxWidth()) {
            // Se limita a 5 filas: los AppWidget tienen un techo de vistas por
            // RemoteViews y el desglose completo está en la app.
            rows.take(5).forEach { row ->
                VqBreakdownRow(
                    name = row.nombre,
                    amount = VqFormat.money(row.total),
                    detail = "Efec ${VqFormat.money(row.efectivo)} · Transf ${VqFormat.money(row.transferencia)}",
                )
            }
            if (rows.size > 5) {
                Text(
                    text = "+${rows.size - 5} más en la app",
                    style = VqWidgetTheme.captionStyle,
                    maxLines = 1,
                )
            }
        }
    }
}

/** Fila del desglose por TPV/vendedor. */
private data class TpvRow(
    val nombre: String,
    val total: Double,
    val efectivo: Double,
    val transferencia: Double,
    val egresos: Double,
    val ventas: Int,
)

private fun parseTpvRows(json: String): List<TpvRow> {
    if (json.isBlank()) return emptyList()
    return try {
        val array = JSONArray(json)
        (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            TpvRow(
                nombre = item.optString("nombre", "TPV"),
                total = item.optDouble("total", 0.0),
                efectivo = item.optDouble("efectivo", 0.0),
                transferencia = item.optDouble("transferencia", 0.0),
                egresos = item.optDouble("egresos", 0.0),
                ventas = item.optInt("ventas", 0),
            )
        }
    } catch (_: Exception) {
        emptyList()
    }
}

/** Parámetro para pasar el appWidgetId a la acción de despliegue. */
private val APP_WIDGET_ID_PARAM = ActionParameters.Key<Int>("vq_app_widget_id")

/**
 * `Key.to(value)` es un método miembro de ActionParameters.Key, por lo que tiene
 * prioridad sobre el `to` de kotlin y produce un ActionParameters.Pair.
 */
private fun actionParametersOf(appWidgetId: Int): ActionParameters =
    androidx.glance.action.actionParametersOf(APP_WIDGET_ID_PARAM to appWidgetId)

/**
 * Despliega/pliega el desglose por TPV. Delega en Dart mediante el receiver de
 * background de home_widget: allí se invierte el flag y, si hace falta, se
 * recargan los datos antes de redibujar.
 */
class ToggleSalesBreakdownAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val appWidgetId = parameters[APP_WIDGET_ID_PARAM]
            ?: GlanceAppWidgetManager(context).getAppWidgetId(glanceId)

        HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse(WidgetKeys.toggleUri(WidgetKeys.PREFIX_SALES, appWidgetId)),
        ).send()
    }
}

class SalesTpvWidgetReceiver : HomeWidgetGlanceWidgetReceiver<SalesTpvWidget>() {
    override val glanceAppWidget = SalesTpvWidget()
}
