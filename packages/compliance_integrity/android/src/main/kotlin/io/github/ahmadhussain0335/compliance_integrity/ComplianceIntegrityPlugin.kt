package io.github.ahmadhussain0335.compliance_integrity

import android.content.Context
import android.content.pm.PackageManager
import com.google.android.gms.tasks.Task
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Play Integrity (standard requests) for compliance_integrity.
 *
 * The token provider is prepared once per Cloud project number and reused.
 * If Play reports INTEGRITY_TOKEN_PROVIDER_INVALID, the provider is prepared
 * again and the request is retried once.
 */
class ComplianceIntegrityPlugin : FlutterPlugin, IntegrityHostApi {
    private var context: Context? = null
    private var manager: StandardIntegrityManager? = null
    private var provider: StandardIntegrityTokenProvider? = null
    private var providerProjectNumber: Long? = null
    private val mutex = Mutex()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        IntegrityHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        IntegrityHostApi.setUp(binding.binaryMessenger, null)
        context = null
        manager = null
        provider = null
    }

    override suspend fun isSupported(): Boolean {
        val pm = context?.packageManager ?: return false
        return isEnabled(pm, PLAY_STORE) && isEnabled(pm, PLAY_SERVICES)
    }

    override suspend fun prepare(cloudProjectNumber: Long?) {
        mutex.withLock { providerFor(requireProjectNumber(cloudProjectNumber)) }
    }

    override suspend fun requestToken(
        requestHash: String,
        cloudProjectNumber: Long?,
    ): TokenMessage {
        val projectNumber = requireProjectNumber(cloudProjectNumber)
        return mutex.withLock {
            val request = StandardIntegrityTokenRequest.builder()
                .setRequestHash(requestHash)
                .build()
            val token = try {
                call { providerFor(projectNumber).request(request).awaitResult() }
            } catch (e: FlutterError) {
                if (e.details != StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID.toString()) {
                    throw e
                }
                provider = null
                call { providerFor(projectNumber).request(request).awaitResult() }
            }
            TokenMessage(token = token.token(), kind = TokenKindMessage.PLAY_INTEGRITY_STANDARD)
        }
    }

    override suspend fun reset() {
        mutex.withLock {
            provider = null
            providerProjectNumber = null
        }
    }

    /** Returns a prepared provider for [projectNumber], preparing it if needed. */
    private suspend fun providerFor(projectNumber: Long): StandardIntegrityTokenProvider {
        val cached = provider
        if (cached != null && providerProjectNumber == projectNumber) return cached
        val request = PrepareIntegrityTokenRequest.builder()
            .setCloudProjectNumber(projectNumber)
            .build()
        val prepared = call { integrityManager().prepareIntegrityToken(request).awaitResult() }
        provider = prepared
        providerProjectNumber = projectNumber
        return prepared
    }

    private fun integrityManager(): StandardIntegrityManager {
        manager?.let { return it }
        val ctx = context ?: throw FlutterError(
            IntegrityErrors.PLATFORM,
            "Plugin is not attached to an engine.",
        )
        return IntegrityManagerFactory.createStandard(ctx).also { manager = it }
    }

    /** Runs [block] with a timeout and converts failures to [FlutterError]. */
    private suspend fun <T> call(block: suspend () -> T): T = try {
        withTimeout(TIMEOUT_MS) { block() }
    } catch (e: FlutterError) {
        throw e
    } catch (e: TimeoutCancellationException) {
        throw FlutterError(IntegrityErrors.NETWORK, "Play Integrity did not respond in time.")
    } catch (e: StandardIntegrityException) {
        throw FlutterError(
            IntegrityErrors.fromStandardErrorCode(e.errorCode),
            e.message,
            e.errorCode.toString(),
        )
    } catch (e: Exception) {
        throw FlutterError(IntegrityErrors.PLATFORM, e.message)
    }

    private fun requireProjectNumber(value: Long?): Long {
        if (value == null || value <= 0) {
            throw FlutterError(
                IntegrityErrors.CONFIGURATION,
                "A Google Cloud project number is required on Android.",
            )
        }
        return value
    }

    private fun isEnabled(pm: PackageManager, packageName: String): Boolean = try {
        pm.getApplicationInfo(packageName, 0).enabled
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private companion object {
        const val PLAY_STORE = "com.android.vending"
        const val PLAY_SERVICES = "com.google.android.gms"

        /** Google suggests a timeout of about one minute for integrity calls. */
        const val TIMEOUT_MS = 60_000L
    }
}

/** Suspends until the Play services [Task] completes. */
private suspend fun <T> Task<T>.awaitResult(): T = suspendCancellableCoroutine { cont ->
    addOnSuccessListener { cont.resume(it) }
    addOnFailureListener { cont.resumeWithException(it) }
    addOnCanceledListener { cont.cancel() }
}
