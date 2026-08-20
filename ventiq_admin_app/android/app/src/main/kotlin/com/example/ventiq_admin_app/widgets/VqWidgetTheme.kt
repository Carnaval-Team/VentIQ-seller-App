package com.example.ventiq_admin_app.widgets

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.example.ventiq_admin_app.MainActivity
import com.example.ventiq_admin_app.R
import es.antonborri.home_widget.actionStartActivity
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.abs

/**
 * Utilidades compartidas por los tres widgets de pantalla de inicio.
 *
 * Los colores se declaran como recursos en `res/values/vq_widget_colors.xml` y
 * `res/values-night/vq_widget_colors.xml`; `ColorProvider(resId)` los resuelve
 * en tiempo de dibujado, así que el tema claro/oscuro se adapta sin código
 * adicional. El fondo con degradado vive en `res/drawable/vq_widget_card_bg.xml`.
 */
object VqWidgetTheme {

    val textPrimary = ColorProvider(R.color.vq_widget_text_primary)
    val textSecondary = ColorProvider(R.color.vq_widget_text_secondary)
    val accentPrimary = ColorProvider(R.color.vq_widget_primary)
    val accentSuccess = ColorProvider(R.color.vq_widget_success)
    val accentError = ColorProvider(R.color.vq_widget_error)
    val accentWarning = ColorProvider(R.color.vq_widget_warning)
    val accentInfo = ColorProvider(R.color.vq_widget_info)

    val captionStyle = TextStyle(
        color = textSecondary,
        fontSize = 10.sp,
    )

    val labelStyle = TextStyle(
        color = textSecondary,
        fontSize = 11.sp,
        fontWeight = FontWeight.Medium,
    )

    fun valueStyle(color: ColorProvider = textPrimary, size: Int = 18) = TextStyle(
        color = color,
        fontSize = size.sp,
        fontWeight = FontWeight.Bold,
    )
}

/** Lectura tolerante de las preferencias que escribe `home_widget` desde Dart. */
class VqWidgetPrefs(
    private val preferences: SharedPreferences,
    private val prefix: String,
    private val appWidgetId: Int,
) {
    fun rawString(fullKey: String, fallback: String = ""): String =
        preferences.getString(fullKey, fallback) ?: fallback

    fun string(field: String, fallback: String = ""): String =
        rawString(WidgetKeys.key(prefix, appWidgetId, field), fallback)

    /** Los números se guardan como texto desde Dart (ver WidgetKeys). */
    fun double(field: String, fallback: Double = 0.0): Double =
        string(field).trim().toDoubleOrNull() ?: fallback

    fun int(field: String, fallback: Int = 0): Int =
        string(field).trim().toDoubleOrNull()?.toInt() ?: fallback

    fun bool(field: String): Boolean = string(field) == "1"

    /** Serie numérica separada por ';' (mini-gráfico). */
    fun series(field: String): List<Double> =
        string(field)
            .split(';')
            .mapNotNull { it.trim().takeIf(String::isNotEmpty)?.toDoubleOrNull() }

    fun labels(field: String): List<String> =
        string(field).split(';').map(String::trim).filter(String::isNotEmpty)

    val state: String get() = string(WidgetKeys.FIELD_STATE, WidgetKeys.STATE_UNCONFIGURED)
    val error: String get() = string(WidgetKeys.FIELD_ERROR)
    val updatedAt: String get() = string(WidgetKeys.FIELD_UPDATED_AT)
    val storeName: String get() = string(WidgetKeys.FIELD_STORE_NAME)

    /** Tasa USD→CUP global (no depende de la instancia). */
    val usdRate: Double
        get() = rawString(WidgetKeys.USD_RATE).trim().toDoubleOrNull() ?: 0.0

    val hasSession: Boolean get() = rawString(WidgetKeys.SESSION_OK) == "1"
}

/** Formateo compacto de dinero: 1.2K / 3.4M, pensado para celdas estrechas. */
object VqFormat {
    private val symbols = DecimalFormatSymbols(Locale.US)
    private val plain = DecimalFormat("#,##0.##", symbols)
    private val oneDecimal = DecimalFormat("#,##0.#", symbols)

    fun money(value: Double, withSymbol: Boolean = true): String {
        val prefix = if (withSymbol) "$" else ""
        val magnitude = abs(value)
        return when {
            magnitude >= 1_000_000_000 -> "$prefix${oneDecimal.format(value / 1_000_000_000)}B"
            magnitude >= 1_000_000 -> "$prefix${oneDecimal.format(value / 1_000_000)}M"
            magnitude >= 10_000 -> "$prefix${oneDecimal.format(value / 1_000)}K"
            else -> "$prefix${plain.format(value)}"
        }
    }

    fun number(value: Double): String = plain.format(value)

    fun percent(value: Double): String {
        val sign = if (value >= 0) "+" else ""
        return "$sign${oneDecimal.format(value)}%"
    }

    /** "2026-08-20T14:31:07.000" → "14:31" */
    fun clock(iso: String): String {
        val timePart = iso.substringAfter('T', "")
        return if (timePart.length >= 5) timePart.substring(0, 5) else ""
    }

    /** "2026-08-20" → "20/08" */
    fun shortDate(iso: String): String {
        val datePart = iso.substringBefore('T')
        val parts = datePart.split('-')
        return if (parts.size >= 3) "${parts[2]}/${parts[1]}" else datePart
    }
}

/**
 * Contenedor común: tarjeta con degradado, esquinas redondeadas y tap que abre
 * la app en la pantalla indicada. Cada widget aporta su contenido interno.
 */
@Composable
fun VqWidgetCard(
    context: Context,
    deepLink: String,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ImageProvider(R.drawable.vq_widget_card_bg))
            .cornerRadius(24.dp)
            .padding(14.dp)
            .clickable(
                onClick = actionStartActivity<MainActivity>(context, Uri.parse(deepLink))
            ),
        verticalAlignment = Alignment.Vertical.Top,
        horizontalAlignment = Alignment.Horizontal.Start,
    ) {
        content()
    }
}

/** Cabecera: título del widget + contexto (tienda / periodo / modo). */
@Composable
fun VqWidgetHeader(title: String, subtitle: String) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = title,
            style = TextStyle(
                color = VqWidgetTheme.accentPrimary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
        Spacer(modifier = GlanceModifier.defaultWeight())
        if (subtitle.isNotEmpty()) {
            Text(text = subtitle, style = VqWidgetTheme.captionStyle, maxLines = 1)
        }
    }
}

/** Mensaje de estado para unconfigured / loading / error / sin sesión. */
@Composable
fun VqWidgetMessage(title: String, message: String) {
    Spacer(modifier = GlanceModifier.height(6.dp))
    Text(
        text = title,
        style = TextStyle(
            color = VqWidgetTheme.textPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
        ),
        maxLines = 1,
    )
    Spacer(modifier = GlanceModifier.height(4.dp))
    Text(text = message, style = VqWidgetTheme.captionStyle, maxLines = 3)
}
