package com.example.ventiq_app

import android.content.pm.PackageManager
import com.shounakmulay.telephony.utils.Constants
import io.flutter.plugin.common.PluginRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelephonyPermissionResultListenerTest {
    @Test
    fun bluetoothPermissionDoesNotReplayCompletedSmsCall() {
        val listener = TelephonyPermissionResultListener(
            PluginRegistry.RequestPermissionsResultListener { _, _, _ ->
                throw IllegalStateException("Reply already submitted")
            },
        )

        for (status in listOf(PackageManager.PERMISSION_GRANTED, PackageManager.PERMISSION_DENIED)) {
            assertFalse(listener.onRequestPermissionsResult(
                24,
                arrayOf("android.permission.BLUETOOTH_CONNECT"),
                intArrayOf(status),
            ))
        }
        assertFalse(listener.onRequestPermissionsResult(24, emptyArray(), intArrayOf()))
    }

    @Test
    fun unrelatedRequestsRemainAvailableToOtherPlugins() {
        var calls = 0
        val listener = TelephonyPermissionResultListener(
            PluginRegistry.RequestPermissionsResultListener { _, _, _ ->
                calls++
                true
            },
        )

        assertFalse(listener.onRequestPermissionsResult(
            25,
            arrayOf("android.permission.CAMERA"),
            intArrayOf(PackageManager.PERMISSION_GRANTED),
        ))
        assertEquals(0, calls)
    }

    @Test
    fun smsAndPhoneRequestsRetainTheirPermissionResults() {
        val permissions = arrayOf("android.permission.READ_SMS")
        var receivedCode = -1
        var receivedResult = -2
        val listener = TelephonyPermissionResultListener(
            PluginRegistry.RequestPermissionsResultListener { code, actualPermissions, results ->
                receivedCode = code
                receivedResult = results.single()
                assertTrue(permissions === actualPermissions)
                results.single() == PackageManager.PERMISSION_GRANTED
            },
        )

        for (code in listOf(
            Constants.SMS_QUERY_REQUEST_CODE,
            Constants.SMS_SEND_REQUEST_CODE,
            Constants.SMS_BACKGROUND_REQUEST_CODE,
            Constants.GET_STATUS_REQUEST_CODE,
            Constants.PERMISSION_REQUEST_CODE,
            Constants.CALL_REQUEST_CODE,
        )) {
            for (status in listOf(PackageManager.PERMISSION_GRANTED, PackageManager.PERMISSION_DENIED)) {
                assertEquals(status == PackageManager.PERMISSION_GRANTED, listener.onRequestPermissionsResult(
                    code, permissions, intArrayOf(status),
                ))
                assertEquals(code, receivedCode)
                assertEquals(status, receivedResult)
            }
        }
    }
}
