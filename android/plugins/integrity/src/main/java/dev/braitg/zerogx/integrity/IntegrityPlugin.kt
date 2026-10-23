package dev.braitg.zerogx.integrity

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/** One classic Play Integrity request, so the server can check `requestDetails.nonce`. */
class IntegrityPlugin(godot: Godot) : GodotPlugin(godot) {
    // Boxed, as the Play Games plugin declares its signal types.
    private val resultSignal = SignalInfo("integrity_result", Long::class.javaObjectType, String::class.java, String::class.java)

    override fun getPluginName() = "ZeroGxIntegrity"

    override fun getPluginSignals() = setOf(resultSignal)

    /** Answers once with `integrity_result(requestId, token, error)`: the token, or else an empty token and the error text. */
    @UsedByGodot
    fun request(nonce: String, cloudProjectNumber: Long, requestId: Long) {
        try {
            val host = activity ?: throw IllegalStateException("The game has no activity.")
            IntegrityManagerFactory.create(host)
                .requestIntegrityToken(
                    IntegrityTokenRequest.builder()
                        .setNonce(nonce)
                        .setCloudProjectNumber(cloudProjectNumber)
                        .build()
                )
                .addOnSuccessListener { emitSignal(resultSignal, requestId, it.token(), "") }
                .addOnFailureListener { emitSignal(resultSignal, requestId, "", it.message ?: it.toString()) }
        } catch (e: Exception) {
            emitSignal(resultSignal, requestId, "", e.message ?: e.toString())
        }
    }
}
