package io.github.ahmadhussain0335.compliance_integrity

import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import kotlin.test.Test
import kotlin.test.assertEquals

internal class ComplianceIntegrityPluginTest {
    @Test
    fun mapsPlayIntegrityErrorCodes() {
        val cases = mapOf(
            StandardIntegrityErrorCode.API_NOT_AVAILABLE to IntegrityErrors.PLAY_SERVICES_MISSING,
            StandardIntegrityErrorCode.PLAY_STORE_NOT_FOUND to IntegrityErrors.PLAY_SERVICES_MISSING,
            StandardIntegrityErrorCode.PLAY_SERVICES_NOT_FOUND to IntegrityErrors.PLAY_SERVICES_MISSING,
            StandardIntegrityErrorCode.PLAY_SERVICES_VERSION_OUTDATED to IntegrityErrors.PLAY_SERVICES_MISSING,
            StandardIntegrityErrorCode.NETWORK_ERROR to IntegrityErrors.NETWORK,
            StandardIntegrityErrorCode.TOO_MANY_REQUESTS to IntegrityErrors.RATE_LIMITED,
            StandardIntegrityErrorCode.CLOUD_PROJECT_NUMBER_IS_INVALID to IntegrityErrors.CONFIGURATION,
            StandardIntegrityErrorCode.REQUEST_HASH_TOO_LONG to IntegrityErrors.CONFIGURATION,
            StandardIntegrityErrorCode.CLIENT_TRANSIENT_ERROR to IntegrityErrors.TRANSIENT,
            StandardIntegrityErrorCode.INTERNAL_ERROR to IntegrityErrors.TRANSIENT,
            StandardIntegrityErrorCode.APP_UID_MISMATCH to IntegrityErrors.PLATFORM,
            12345 to IntegrityErrors.PLATFORM,
        )
        cases.forEach { (code, expected) ->
            assertEquals(expected, IntegrityErrors.fromStandardErrorCode(code), "code $code")
        }
    }
}
