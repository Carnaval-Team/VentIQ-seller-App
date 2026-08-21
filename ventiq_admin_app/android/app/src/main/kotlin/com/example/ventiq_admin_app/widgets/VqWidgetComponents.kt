package com.example.ventiq_admin_app.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.background
import androidx.glance.appwidget.cornerRadius
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
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

/**
 * Piezas visuales reutilizables: sparkline, celdas de métrica, badges de
 * tendencia, chips y filas de desglose.
 *
 * El sparkline se dibuja en un Bitmap con Canvas porque Glance no ofrece un
 * lienzo vectorial; el bitmap se escala con ContentScale.FillBounds, así que se
 * mantiene nítido en cualquier tamaño de widget.
 */

/** Ancho/alto en píxeles del bitmap del sparkline antes de escalarlo. */
private const val SPARK_W = 520
private const val SPARK_H = 150

@Composable
fun VqSparkline(
    values: List<Double>,
    modifier: GlanceModifier = GlanceModifier,
    positive: Boolean = true,
) {
    val context = LocalContext.current

    if (values.size < 2) {
        // Sin suficientes puntos: se deja una banda tenue en lugar de un hueco.
        Box(
            modifier = modifier
                .background(ColorProvider(R.color.vq_widget_chip_bg))
                .cornerRadius(12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = "Sin tendencia", style = VqWidgetTheme.captionStyle, maxLines = 1)
        }
        return
    }

    val bitmap = buildSparkBitmap(context, values, positive)
    Image(
        provider = ImageProvider(bitmap),
        contentDescription = "Tendencia de ventas",
        modifier = modifier,
        contentScale = ContentScale.FillBounds,
    )
}

/**
 * Construye el bitmap del sparkline. No se memoiza a propósito: Glance recompone
 * en un proceso distinto por cada actualización, y el coste de un bitmap de
 * 520x150 es despreciable frente a intentar mantener estado entre procesos.
 */
private fun buildSparkBitmap(
    context: Context,
    values: List<Double>,
    positive: Boolean,
): Bitmap {
    val bitmap = Bitmap.createBitmap(SPARK_W, SPARK_H, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)

    val lineColor = ContextCompat.getColor(
        context,
        if (positive) R.color.vq_widget_success else R.color.vq_widget_error,
    )
    val fillColor = ContextCompat.getColor(context, R.color.vq_widget_spark_fill)

    val min = values.min()
    val max = values.max()
    val span = (max - min).takeIf { it > 0.0 } ?: 1.0

    val padTop = 12f
    val padBottom = 12f
    val usableH = SPARK_H - padTop - padBottom
    val stepX = SPARK_W.toFloat() / (values.size - 1)

    fun xAt(index: Int) = index * stepX
    fun yAt(value: Double) =
        (padTop + usableH - ((value - min) / span * usableH)).toFloat()

    // Área bajo la curva con degradado vertical.
    val area = Path().apply {
        moveTo(0f, SPARK_H.toFloat())
        lineTo(xAt(0), yAt(values[0]))
        for (i in 1 until values.size) lineTo(xAt(i), yAt(values[i]))
        lineTo(xAt(values.size - 1), SPARK_H.toFloat())
        close()
    }
    val areaPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        shader = LinearGradient(
            0f, padTop, 0f, SPARK_H.toFloat(),
            fillColor, (fillColor and 0x00FFFFFF),
            Shader.TileMode.CLAMP,
        )
    }
    canvas.drawPath(area, areaPaint)

    // Línea de la tendencia.
    val line = Path().apply {
        moveTo(xAt(0), yAt(values[0]))
        for (i in 1 until values.size) lineTo(xAt(i), yAt(values[i]))
    }
    val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 7f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = lineColor
    }
    canvas.drawPath(line, linePaint)

    // Punto final destacado.
    val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = lineColor
    }
    canvas.drawCircle(
        xAt(values.size - 1).coerceAtMost(SPARK_W - 8f),
        yAt(values.last()),
        9f,
        dotPaint,
    )

    return bitmap
}

/** Celda compacta etiqueta + valor, usada en las filas de métricas. */
@Composable
fun VqMetricCell(
    label: String,
    value: String,
    color: ColorProvider,
    modifier: GlanceModifier = GlanceModifier,
) {
    Column(modifier = modifier.padding(end = 6.dp)) {
        Text(text = label, style = VqWidgetTheme.captionStyle, maxLines = 1)
        Text(
            text = value,
            style = TextStyle(color = color, fontSize = 14.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
    }
}

/** Indicador de tendencia: flecha + porcentaje respecto al periodo anterior. */
@Composable
fun VqTrendBadge(deltaPercent: Double) {
    val up = deltaPercent >= 0
    val color = if (up) VqWidgetTheme.accentSuccess else VqWidgetTheme.accentError
    Row(
        modifier = GlanceModifier
            .background(ColorProvider(R.color.vq_widget_chip_bg))
            .cornerRadius(12.dp)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = if (up) "▲" else "▼",
            style = TextStyle(color = color, fontSize = 10.sp),
            maxLines = 1,
        )
        Spacer(modifier = GlanceModifier.width(3.dp))
        Text(
            text = VqFormat.percent(deltaPercent),
            style = TextStyle(color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
    }
}

/** Píldora de estado, p. ej. "EN VIVO" o el rango de fechas del widget de ventas. */
@Composable
fun VqChip(text: String, color: ColorProvider) {
    Row(
        modifier = GlanceModifier
            .background(ColorProvider(R.color.vq_widget_chip_bg))
            .cornerRadius(12.dp)
            .padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = text,
            style = TextStyle(color = color, fontSize = 10.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
    }
}

/** Fila del desglose por TPV: nombre a la izquierda, importe a la derecha. */
@Composable
fun VqBreakdownRow(name: String, amount: String, detail: String) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 3.dp),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = name,
                style = TextStyle(
                    color = VqWidgetTheme.textPrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            if (detail.isNotEmpty()) {
                Text(text = detail, style = VqWidgetTheme.captionStyle, maxLines = 1)
            }
        }
        Text(
            text = amount,
            style = TextStyle(
                color = VqWidgetTheme.accentSuccess,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
    }
}

/** Separador fino coherente con el tema. */
@Composable
fun VqDivider() {
    Box(
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(1.dp)
            .background(ColorProvider(R.color.vq_widget_stroke))
    ) {}
}
