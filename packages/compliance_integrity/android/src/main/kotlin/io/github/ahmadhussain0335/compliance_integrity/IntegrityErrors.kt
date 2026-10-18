package io.github.ahmadhussain0335.compliance_integrity

import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode

/** Error codes shared with the Dart layer (IntegrityErrorCodes). */
internal object IntegrityErrors {
    const val UNSUPPORTED = "unsupported"
    const val PLAY_SERVICES_MISSING = "play_services_missing"
    const val NETWORK = "network"
    const val RATE_LIMITED = "rate_limited"
    const val CONFIGURATION = "configuration"
    const val TRANSIENT = "transient"
    const val PLATFORM = "platform"

    /**
     * Maps a Play Integrity standard request error code to a Dart error code.
     * See https://developer.android.com/google/play/integrity/error-codes
     */
    fun fromStandardErrorCode(code: Int): String = when (code) {
        StandardIntegrityErrorCode.API_NOT_AVAILABLE,
        StandardIntegrityErrorCode.PLAY_STORE_NOT_FOUND,
        StandardIntegrityErrorCode.PLAY_SERVICES_NOT_FOUND,
        StandardIntegrityErrorCode.CANNOT_BIND_TO_SERVICE,
        StandardIntegrityErrorCode.PLAY_STORE_VERSION_OUTDATED,
        StandardIntegrityErrorCode.PLAY_SERVICES_VERSION_OUTDATED,
        -> PLAY_SERVICES_MISSING

        StandardIntegrityErrorCode.NETWORK_ERROR -> NETWORK
        StandardIntegrityErrorCode.TOO_MANY_REQUESTS -> RATE_LIMITED

        StandardIntegrityErrorCode.CLOUD_PROJECT_NUMBER_IS_INVALID,
        StandardIntegrityErrorCode.REQUEST_HASH_TOO_LONG,
        -> CONFIGURATION

        StandardIntegrityErrorCode.GOOGLE_SERVER_UNAVAILABLE,
        StandardIntegrityErrorCode.CLIENT_TRANSIENT_ERROR,
        StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID,
        StandardIntegrityErrorCode.INTERNAL_ERROR,
        -> TRANSIENT

        // APP_NOT_INSTALLED, APP_UID_MISMATCH and unknown codes: the server
        // should treat the client as failing all checks.
        else -> PLATFORM
    }
}
