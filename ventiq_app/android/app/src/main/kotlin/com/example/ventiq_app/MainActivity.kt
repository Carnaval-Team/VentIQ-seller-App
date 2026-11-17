package com.example.ventiq_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.PluginRegistry

class MainActivity : FlutterActivity()

internal class TelephonyPermissionResultListener(
    private val delegate: PluginRegistry.RequestPermissionsResultListener,
) : PluginRegistry.RequestPermissionsResultListener by delegate
