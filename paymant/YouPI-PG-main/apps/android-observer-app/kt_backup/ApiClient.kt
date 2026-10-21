package com.youpi.observer

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class ApiClient(private val context: Context) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
    private val prefs = EncryptedSharedPreferences.create(
        "youpi_observer_secure_prefs",
        masterKeyAlias,
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun isPaired(): Boolean {
        return prefs.getString("device_id", null) != null && prefs.getString("signing_key", null) != null
    }

    fun getBaseUrl(): String {
        return prefs.getString("base_url", "http://10.0.2.2:6100") ?: "http://10.0.2.2:6100"
    }

    fun pair(baseUrl: String, enrollmentToken: String, deviceName: String): Boolean {
        val cleanUrl = baseUrl.trimEnd('/')
        val url = "$cleanUrl/api/v1/pollers/android/pair"

        val bodyJson = JSONObject().apply {
            put("enrollmentToken", enrollmentToken)
            put("deviceName", deviceName)
            put("deviceModel", android.os.Build.MODEL)
        }

        val request = Request.Builder()
            .url(url)
            .post(bodyJson.toString().toRequestBody("application/json".toMediaType()))
            .build()

        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return false
                val respBody = response.body?.string() ?: return false
                val json = JSONObject(respBody)

                if (json.optBoolean("paired", false)) {
                    val deviceId = json.getString("deviceId")
                    val signingKey = json.getString("signingKey")

                    prefs.edit()
                        .putString("base_url", cleanUrl)
                        .putString("device_id", deviceId)
                        .putString("signing_key", signingKey)
                        .apply()

                    return true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    fun sendObservation(parsed: ParsedNotification): Boolean {
        if (!isPaired()) return false

        val deviceId = prefs.getString("device_id", null) ?: return false
        val signingKey = prefs.getString("signing_key", null) ?: return false
        val baseUrl = getBaseUrl()

        val timestamp = System.currentTimeMillis().toString()
        val url = "$baseUrl/api/v1/pollers/android/events"

        val rawNotification = JSONObject().apply {
            put("title", parsed.rawTitle)
            put("text", parsed.rawText)
            put("package", parsed.packageName)
        }

        val bodyJson = JSONObject().apply {
            put("deviceId", deviceId)
            put("amountPaise", parsed.amountPaise)
            put("amount", parsed.amountRupees)
            put("observedAt", parsed.timestamp)
            put("bankReferenceNumber", parsed.bankReferenceNumber)
            put("senderVpa", parsed.senderVpa)
            put("rawNotification", rawNotification)
        }

        val bodyString = bodyJson.toString()
        val sigPayload = "$bodyString:$timestamp"
        val signature = calculateHmac(sigPayload, signingKey)

        val request = Request.Builder()
            .url(url)
            .addHeader("X-Device-Id", deviceId)
            .addHeader("X-Timestamp", timestamp)
            .addHeader("X-Signature", signature)
            .post(bodyString.toRequestBody("application/json".toMediaType()))
            .build()

        var success = false
        try {
            client.newCall(request).execute().use { res ->
                success = res.isSuccessful
            }
        } catch (e: Exception) {
            success = false
        }

        if (!success) {
            // Network failure or server down: safely queue into offline outbox
            queueToOutbox(parsed)
            return false
        }

        // On successful delivery, trigger opportunistic background flush of any pending outbox items
        if (getOutboxCount() > 0) {
            flushOutbox()
        }
        return true
    }

    @Synchronized
    fun queueToOutbox(parsed: ParsedNotification) {
        try {
            val rawArrStr = prefs.getString("outbox_queue", "[]") ?: "[]"
            val arr = try { org.json.JSONArray(rawArrStr) } catch (e: Exception) { org.json.JSONArray() }
            if (arr.length() >= 50) {
                // Keep queue bounded: drop oldest if exceeding 50 entries
                val trimmed = org.json.JSONArray()
                for (i in 1 until arr.length()) trimmed.put(arr.get(i))
                prefs.edit().putString("outbox_queue", trimmed.toString()).apply()
            }
            val entry = JSONObject().apply {
                put("eventId", java.util.UUID.randomUUID().toString())
                put("amountPaise", parsed.amountPaise)
                put("amountRupees", parsed.amountRupees)
                put("bankReferenceNumber", parsed.bankReferenceNumber ?: JSONObject.NULL)
                put("senderVpa", parsed.senderVpa ?: JSONObject.NULL)
                put("observedAt", parsed.timestamp)
                put("packageName", parsed.packageName)
                put("retryCount", 0)
                put("createdAt", System.currentTimeMillis())
            }
            val updatedArr = org.json.JSONArray(prefs.getString("outbox_queue", "[]") ?: "[]")
            updatedArr.put(entry)
            prefs.edit().putString("outbox_queue", updatedArr.toString()).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun getOutboxCount(): Int {
        val rawArrStr = prefs.getString("outbox_queue", "[]") ?: "[]"
        return try { org.json.JSONArray(rawArrStr).length() } catch (e: Exception) { 0 }
    }

    @Synchronized
    fun flushOutbox(): Int {
        if (!isPaired()) return 0
        val rawArrStr = prefs.getString("outbox_queue", "[]") ?: "[]"
        val arr = try { org.json.JSONArray(rawArrStr) } catch (e: Exception) { org.json.JSONArray() }
        if (arr.length() == 0) return 0

        val remainingArr = org.json.JSONArray()
        var deliveredCount = 0

        val deviceId = prefs.getString("device_id", null) ?: return 0
        val signingKey = prefs.getString("signing_key", null) ?: return 0
        val baseUrl = getBaseUrl()

        for (i in 0 until arr.length()) {
            val item = arr.getJSONObject(i)
            val retryCount = item.optInt("retryCount", 0)
            if (retryCount >= 5) {
                // Bounded retries: Discard after 5 failed attempts
                continue
            }

            val timestamp = System.currentTimeMillis().toString()
            val url = "$baseUrl/api/v1/pollers/android/events"

            val bodyJson = JSONObject().apply {
                put("deviceId", deviceId)
                put("amountPaise", item.getLong("amountPaise"))
                put("amount", item.getString("amountRupees"))
                put("observedAt", item.getLong("observedAt"))
                if (!item.isNull("bankReferenceNumber")) put("bankReferenceNumber", item.getString("bankReferenceNumber"))
                if (!item.isNull("senderVpa")) put("senderVpa", item.getString("senderVpa"))
            }

            val bodyString = bodyJson.toString()
            val sigPayload = "$bodyString:$timestamp"
            val signature = calculateHmac(sigPayload, signingKey)

            val request = Request.Builder()
                .url(url)
                .addHeader("X-Device-Id", deviceId)
                .addHeader("X-Timestamp", timestamp)
                .addHeader("X-Signature", signature)
                .post(bodyString.toRequestBody("application/json".toMediaType()))
                .build()

            var success = false
            try {
                client.newCall(request).execute().use { res ->
                    if (res.isSuccessful) {
                        success = true
                        deliveredCount++
                    }
                }
            } catch (e: Exception) {
                success = false
            }

            if (!success) {
                item.put("retryCount", retryCount + 1)
                remainingArr.put(item)
            }
        }

        prefs.edit().putString("outbox_queue", remainingArr.toString()).apply()
        return deliveredCount
    }

    fun sendHeartbeat(): Boolean {
        if (!isPaired()) return false

        val deviceId = prefs.getString("device_id", null) ?: return false
        val baseUrl = getBaseUrl()
        val url = "$baseUrl/api/v1/pollers/android/heartbeat"

        val bodyJson = JSONObject().apply {
            put("deviceId", deviceId)
            put("timestamp", System.currentTimeMillis())
        }

        val request = Request.Builder()
            .url(url)
            .addHeader("X-Device-Id", deviceId)
            .post(bodyJson.toString().toRequestBody("application/json".toMediaType()))
            .build()

        try {
            client.newCall(request).execute().use { res ->
                return res.isSuccessful
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    fun sendSms(sender: String, body: String, timestamp: Long): Boolean {
        if (!isPaired()) return false

        val deviceId = prefs.getString("device_id", null) ?: return false
        val signingKey = prefs.getString("signing_key", null) ?: return false
        val baseUrl = getBaseUrl()

        val tsStr = timestamp.toString()
        val url = "$baseUrl/api/v1/observers/sms"

        val bodyJson = JSONObject().apply {
            put("deviceId", deviceId)
            put("sender", sender)
            put("body", body)
            put("timestamp", timestamp)
        }

        val bodyString = bodyJson.toString()
        val sigPayload = "$bodyString:$tsStr"
        val signature = calculateHmac(sigPayload, signingKey)

        val request = Request.Builder()
            .url(url)
            .addHeader("X-Device-Id", deviceId)
            .addHeader("X-Timestamp", tsStr)
            .addHeader("X-Signature", signature)
            .post(bodyString.toRequestBody("application/json".toMediaType()))
            .build()

        try {
            client.newCall(request).execute().use { res ->
                return res.isSuccessful
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun calculateHmac(data: String, keyHex: String): String {
        val secret = SecretKeySpec(keyHex.toByteArray(Charsets.UTF_8), "HmacSHA256")
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(secret)
        val hmacData = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return hmacData.joinToString("") { "%02x".format(it) }
    }
}
