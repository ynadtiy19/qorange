package com.example.qorange
import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.*
import android.util.Base64

class TokenManager(private val context: Context, private val contactName: String = "default") {

    companion object {
        private const val TAG = "TokenManager"
        private const val FIREBASE_API_KEY = "AIzaSyDtC7Uwb5pGAsdmrH2T4Gqdk5Mga07jYPM"
        private const val REFRESH_TOKEN_URL = "https://securetoken.googleapis.com/v1/token"
    }

    private val prefsName = "sesame_tokens_${contactName.lowercase()}"
    private val prefIdToken = "id_token_${contactName.lowercase()}"
    private val prefRefreshToken = "refresh_token_${contactName.lowercase()}"
    private val prefTokenExpiry = "token_expiry_${contactName.lowercase()}"

    private val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    suspend fun getValidIdToken(): String? = withContext(Dispatchers.IO) {
        try {
            val currentToken = prefs.getString(prefIdToken, null)
            val tokenExpiry = prefs.getLong(prefTokenExpiry, 0)
            val currentTime = System.currentTimeMillis()

            if (currentToken != null && currentTime < tokenExpiry - 60000) {
                return@withContext currentToken
            }

            val refreshToken = prefs.getString(prefRefreshToken, "")
            if (!refreshToken.isNullOrEmpty()) {
                val newToken = refreshIdToken(refreshToken)
                if (newToken != null) {
                    return@withContext newToken
                }
            }

            Log.w(TAG, "Token expired and no valid refresh token found.")
            return@withContext null

        } catch (e: Exception) {
            Log.e(TAG, "Error in getValidIdToken for $contactName", e)
            return@withContext null
        }
    }

    fun storeTokens(idToken: String, refreshToken: String) {
        try {
            val tokenExpiry = parseJwtExpiry(idToken)

            prefs.edit().apply {
                putString(prefIdToken, idToken)
                putString(prefRefreshToken, refreshToken)
                putLong(prefTokenExpiry, tokenExpiry)
                apply()
            }

            Log.i(TAG, "[$contactName] Tokens stored. Expires: ${Date(tokenExpiry)}")
        } catch (e: Exception) {
            Log.e(TAG, "Error storing tokens for $contactName", e)
        }
    }

    private suspend fun refreshIdToken(refreshToken: String): String? = withContext(Dispatchers.IO) {
        try {
            val url = URL("$REFRESH_TOKEN_URL?key=$FIREBASE_API_KEY")
            val connection = url.openConnection() as HttpURLConnection

            connection.apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                doOutput = true
                connectTimeout = 10000
                readTimeout = 10000
            }

            val requestBody = JSONObject().apply {
                put("grant_type", "refresh_token")
                put("refresh_token", refreshToken)
            }

            OutputStreamWriter(connection.outputStream).use { writer ->
                writer.write(requestBody.toString())
                writer.flush()
            }

            val responseCode = connection.responseCode

            if (responseCode == HttpURLConnection.HTTP_OK) {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                val jsonResponse = JSONObject(response)

                val newIdToken = jsonResponse.getString("id_token")
                val newRefreshToken = jsonResponse.optString("refresh_token", refreshToken)

                storeTokens(newIdToken, newRefreshToken)

                return@withContext newIdToken
            } else {
                Log.e(TAG, "Token refresh failed: $responseCode")
                return@withContext null
            }

        } catch (e: Exception) {
            Log.e(TAG, "Network error during token refresh for $contactName", e)
            return@withContext null
        }
    }

    private fun parseJwtExpiry(token: String): Long {
        try {
            val parts = token.split(".")
            if (parts.size >= 2) {
                val payload = String(Base64.decode(parts[1], Base64.URL_SAFE))
                val jsonPayload = JSONObject(payload)
                val exp = jsonPayload.getLong("exp")
                return exp * 1000
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing JWT expiry", e)
        }
        return System.currentTimeMillis() + 3600000 // Default 1 hour
    }

    fun hasStoredTokens(): Boolean {
        return prefs.getString(prefIdToken, null) != null
    }

    fun clearTokens() {
        prefs.edit().clear().apply()
        Log.i(TAG, "[$contactName] All tokens cleared")
    }

    fun getTokenInfo(): String {
        val idToken = prefs.getString(prefIdToken, null)
        val expiry = prefs.getLong(prefTokenExpiry, 0)
        return "[$contactName] Token Present: ${idToken != null}, Expires: ${Date(expiry)}"
    }
}