package dev.braitg.zerogx.integrity

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/** One classic Play Integrity request, so the server can check `requestDetails.nonce`. */
class IntegrityPlugin(godot: Godot) : GodotPlugin(godot) {
    private val tokenSignal = SignalInfo("integrity_token", String::class.java)
    private val failedSignal = SignalInfo("integrity_failed", String::class.java)

    override fun getPluginName() = "ZeroGxIntegrity"

    override fun getPluginSignals() = setOf(tokenSignal, failedSignal)

    /** Answers with exactly one signal: `integrity_token(token)` or `integrity_failed(message)`. */
    @UsedByGodot
    fun request(nonce: String, cloudProjectNumber: Long) {
        try {
            val host = activity ?: throw IllegalStateException("The game has no activity.")
            IntegrityManagerFactory.create(host)
                .requestIntegrityToken(
                    IntegrityTokenRequest.builder()
                        .setNonce(nonce)
                        .setCloudProjectNumber(cloudProjectNumber)
                        .build()
                )
                .addOnSuccessListener { emitSignal(tokenSignal, it.token()) }
                .addOnFailureListener { emitSignal(failedSignal, it.message ?: it.toString()) }
        } catch (e: Exception) {
            emitSignal(failedSignal, e.message ?: e.toString())
        }
    }
}
