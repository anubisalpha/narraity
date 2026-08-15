package uk.aity.narraity

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM encrypt/decrypt for small secrets (the Drive and GitHub OAuth
 * tokens), using a non-exportable key held in the hardware-backed
 * AndroidKeyStore. The key is generated once on first use and never leaves the
 * Keystore; only ciphertext crosses the method channel.
 *
 * Returned ciphertext is `iv (12 bytes) || GCM ciphertext+tag`, which the Dart
 * side (`android_secret_cipher.dart`) treats as opaque bytes and stores as-is.
 */
class SecretCipher {
    companion object {
        const val CHANNEL = "uk.aity.narraity/secret_cipher"
        private const val KEY_ALIAS = "narraity_token_key"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH = 12
        private const val TAG_LENGTH_BITS = 128
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv // 12 bytes for GCM
        val ciphertext = cipher.doFinal(plaintext)
        return iv + ciphertext
    }

    private fun decrypt(data: ByteArray): ByteArray {
        require(data.size > IV_LENGTH) { "ciphertext too short" }
        val iv = data.copyOfRange(0, IV_LENGTH)
        val ciphertext = data.copyOfRange(IV_LENGTH, data.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_LENGTH_BITS, iv))
        return cipher.doFinal(ciphertext)
    }

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "encrypt" -> result.success(encrypt(call.arguments as ByteArray))
                        "decrypt" -> result.success(decrypt(call.arguments as ByteArray))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("secret_cipher_error", e.message, null)
                }
            }
    }
}
