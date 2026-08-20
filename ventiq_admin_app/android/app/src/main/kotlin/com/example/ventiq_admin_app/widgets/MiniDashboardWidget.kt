package com.example.ventiq_admin_app.widgets

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.text.Text
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/**
 * Mini Dashboard: gastos, ganancia neta, órdenes, tasa del dólar y sparkline de
 * la tendencia de ventas, para el periodo elegido en la configuración.
 *
 * Los datos los escribe Dart (`MiniDashboardWidgetData`) reutilizando el RPC
 * `fn_dashboard_analisis_tienda` que ya consume el DashboardScreen.
 */
class MiniDashboardWidget : GlanceAppWidget() {

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    /** Un solo layout adaptable: Glance reescala el contenido. */
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
        val prefs = VqWidgetPrefs(
            state.preferences,
            WidgetKeys.PREFIX_MINI_DASHBOARD,
            appWidgetId,
        )

        val periodo = prefs.string(WidgetKeys.FIELD_PERIODO)
        val tienda = prefs.storeName

        VqWidgetCard(
            context = context,
            deepLink = VqDeepLinks.dashboard(WidgetKeys.PREFIX_MINI_DASHBOARD, appWidgetId),
        ) {
            VqWidgetHeader(
                title = if (periodo.isEmpty()) "Resumen" else periodo,
                subtitle = tienda,
            )

            when (prefs.state) {
                WidgetKeys.STATE_UNCONFIGURED -> VqWidgetMessage(
                    "Sin configurar",
                    "Toca para elegir tienda y periodo.",
                )

                WidgetKeys.STATE_LOADING -> VqWidgetMessage(
                    "Actualizando…",
                    "Consultando el resumen de la tienda.",
                )

                WidgetKeys.STATE_ERROR -> VqWidgetMessage(
                    "No se pudo actualizar",
                    prefs.error.ifEmpty { "Abre la app para reintentar." },
                )

                else -> Metrics(prefs)
            }
        }
    }

    @Composable
    private fun Metrics(prefs: VqWidgetPrefs) {
        val gastos = prefs.double(WidgetKeys.FIELD_GASTOS)
        val ganancia = prefs.double(WidgetKeys.FIELD_GANANCIA_NETA)
        val ordenes = prefs.int(WidgetKeys.FIELD_ORDENES)
        val delta = prefs.double(WidgetKeys.FIELD_DELTA_PCT)
        val usd = prefs.usdRate
        val trend = prefs.series(WidgetKeys.FIELD_TREND)

        Spacer(modifier = GlanceModifier.height(8.dp))

        // Fila destacada: ganancia neta + variación respecto al periodo anterior.
        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.Vertical.Bottom,
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(text = "Ganancia neta", style = VqWidgetTheme.labelStyle, maxLines = 1)
                Text(
                    text = VqFormat.money(ganancia),
                    style = VqWidgetTheme.valueStyle(
                        color = if (ganancia >= 0) {
                            VqWidgetTheme.accentSuccess
                        } else {
                            VqWidgetTheme.accentError
                        },
                        size = 22,
                    ),
                    maxLines = 1,
                )
            }
            VqTrendBadge(delta)
        }

        Spacer(modifier = GlanceModifier.height(8.dp))

        // Sparkline de la tendencia de ventas (misma serie que el Dashboard).
        VqSparkline(
            values = trend,
            modifier = GlanceModifier.fillMaxWidth().height(34.dp),
            positive = ganancia >= 0,
        )

        Spacer(modifier = GlanceModifier.height(8.dp))

        Row(modifier = GlanceModifier.fillMaxWidth()) {
            VqMetricCell(
                label = "Gastos",
                value = VqFormat.money(gastos),
                color = VqWidgetTheme.accentError,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "Órdenes",
                value = ordenes.toString(),
                color = VqWidgetTheme.accentInfo,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "USD",
                value = if (usd > 0) VqFormat.number(usd) else "—",
                color = VqWidgetTheme.accentWarning,
                modifier = GlanceModifier.defaultWeight(),
            )
        }

        val updated = VqFormat.clock(prefs.updatedAt)
        if (updated.isNotEmpty()) {
            Spacer(modifier = GlanceModifier.height(6.dp))
            Text(text = "Actualizado $updated", style = VqWidgetTheme.captionStyle, maxLines = 1)
        }
    }
}

class MiniDashboardWidgetReceiver : HomeWidgetGlanceWidgetReceiver<MiniDashboardWidget>() {
    override val glanceAppWidget = MiniDashboardWidget()
}
