package com.example.ventiq_admin_app

import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.inventtia.admin/session_vault"
    private val preferencesName = "inventtia_session_vault"
    private val sessionKey = "supabase_session"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "write" -> {
                        val session = call.argument<String>("session")
                        if (session.isNullOrEmpty()) {
                            result.error("INVALID_SESSION", "La sesión es obligatoria", null)
                        } else {
                            encryptedPreferences().edit().putString(sessionKey, session).apply()
                            result.success(null)
                        }
                    }
                    "read" -> result.success(encryptedPreferences().getString(sessionKey, null))
                    "clear" -> {
                        encryptedPreferences().edit().remove(sessionKey).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun encryptedPreferences() = EncryptedSharedPreferences.create(
        this,
        preferencesName,
        MasterKey.Builder(this).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
}
