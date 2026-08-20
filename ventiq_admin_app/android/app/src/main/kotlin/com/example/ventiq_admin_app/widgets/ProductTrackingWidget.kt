package com.example.ventiq_admin_app.widgets

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/**
 * Seguimiento de un producto concreto: precio de venta, costo en CUP y USD,
 * total vendido e inventario actual.
 *
 * Datos: `fn_vista_precios_productos3` (precios y costos),
 * `fn_reporte_ventas_con_proveedor4` (ventas del periodo) y
 * `fn_listar_inventario_productos_paged2` (stock), los mismos RPCs que usa
 * ProductDetailScreen.
 */
class ProductTrackingWidget : GlanceAppWidget() {

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
        val prefs = VqWidgetPrefs(state.preferences, WidgetKeys.PREFIX_PRODUCT, appWidgetId)
        val productId = prefs.int(WidgetKeys.FIELD_PRODUCTO_ID)
        val nombre = prefs.string(WidgetKeys.FIELD_PRODUCTO_NOMBRE)

        VqWidgetCard(
            context = context,
            deepLink = VqDeepLinks.product(
                WidgetKeys.PREFIX_PRODUCT,
                appWidgetId,
                productId,
            ),
        ) {
            VqWidgetHeader(
                title = if (nombre.isEmpty()) "Producto" else nombre,
                subtitle = prefs.storeName,
            )

            when (prefs.state) {
                WidgetKeys.STATE_UNCONFIGURED -> VqWidgetMessage(
                    "Sin configurar",
                    "Toca para elegir tienda y producto a seguir.",
                )

                WidgetKeys.STATE_LOADING -> VqWidgetMessage(
                    "Actualizando…",
                    "Consultando precios e inventario.",
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
        val precioVenta = prefs.double(WidgetKeys.FIELD_PRECIO_VENTA)
        val costoCup = prefs.double(WidgetKeys.FIELD_COSTO_CUP)
        val costoUsd = prefs.double(WidgetKeys.FIELD_COSTO_USD)
        val vendido = prefs.double(WidgetKeys.FIELD_TOTAL_VENDIDO)
        val ingresos = prefs.double(WidgetKeys.FIELD_INGRESOS)
        val stock = prefs.double(WidgetKeys.FIELD_STOCK)

        // Margen sobre el costo en CUP: da contexto inmediato al precio.
        val margen = if (costoCup > 0) ((precioVenta - costoCup) / costoCup) * 100 else 0.0

        Spacer(modifier = GlanceModifier.height(8.dp))

        Row(
            modifier = GlanceModifier.fillMaxWidth(),
            verticalAlignment = Alignment.Vertical.Bottom,
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(text = "Precio de venta", style = VqWidgetTheme.labelStyle, maxLines = 1)
                Text(
                    text = VqFormat.money(precioVenta),
                    style = VqWidgetTheme.valueStyle(VqWidgetTheme.accentPrimary, 22),
                    maxLines = 1,
                )
            }
            if (costoCup > 0) {
                VqTrendBadge(margen)
            }
        }

        Spacer(modifier = GlanceModifier.height(8.dp))

        Row(modifier = GlanceModifier.fillMaxWidth()) {
            VqMetricCell(
                label = "Costo CUP",
                value = VqFormat.money(costoCup),
                color = VqWidgetTheme.accentWarning,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "Costo USD",
                value = VqFormat.money(costoUsd),
                color = VqWidgetTheme.accentInfo,
                modifier = GlanceModifier.defaultWeight(),
            )
        }

        Spacer(modifier = GlanceModifier.height(6.dp))

        Row(modifier = GlanceModifier.fillMaxWidth()) {
            VqMetricCell(
                label = "Vendido",
                value = "${VqFormat.number(vendido)} u",
                color = VqWidgetTheme.accentSuccess,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "Ingresos",
                value = VqFormat.money(ingresos),
                color = VqWidgetTheme.accentSuccess,
                modifier = GlanceModifier.defaultWeight(),
            )
            VqMetricCell(
                label = "Stock",
                value = VqFormat.number(stock),
                color = if (stock <= 0) {
                    VqWidgetTheme.accentError
                } else {
                    VqWidgetTheme.accentPrimary
                },
                modifier = GlanceModifier.defaultWeight(),
            )
        }

        if (stock <= 0) {
            Spacer(modifier = GlanceModifier.height(6.dp))
            VqChip("SIN STOCK", VqWidgetTheme.accentError)
        }

        val updated = VqFormat.clock(prefs.updatedAt)
        if (updated.isNotEmpty()) {
            Spacer(modifier = GlanceModifier.height(6.dp))
            Text(text = "Actualizado $updated", style = VqWidgetTheme.captionStyle, maxLines = 1)
        }
    }
}

class ProductTrackingWidgetReceiver : HomeWidgetGlanceWidgetReceiver<ProductTrackingWidget>() {
    override val glanceAppWidget = ProductTrackingWidget()
}
