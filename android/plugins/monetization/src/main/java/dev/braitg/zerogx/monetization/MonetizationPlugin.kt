package dev.braitg.zerogx.monetization

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.FrameLayout
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class MonetizationPlugin(godot: Godot) : GodotPlugin(godot) {
    private val storeStateSignal = SignalInfo(
        "store_state",
        Long::class.javaObjectType,
        Boolean::class.javaObjectType,
        String::class.java,
        String::class.java,
    )
    private val purchaseStateSignal = SignalInfo(
        "purchase_state",
        Long::class.javaObjectType,
        String::class.java,
        String::class.java,
        String::class.java,
    )
    private val purchaseRefreshStartedSignal = SignalInfo(
        "purchase_refresh_started",
        Long::class.javaObjectType,
    )
    private val adStateSignal = SignalInfo(
        "ad_state",
        Boolean::class.javaObjectType,
        Boolean::class.javaObjectType,
        Boolean::class.javaObjectType,
        String::class.java,
    )

    private val ownership = OwnershipState()
    private val purchaseGenerations = BillingGenerationState()
    @Volatile private var started = false
    private var bannerAds: BannerAds? = null
    private var billing: PlayBilling? = null

    override fun getPluginName(): String = "ZeroGxMonetization"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(storeStateSignal, purchaseStateSignal, purchaseRefreshStartedSignal, adStateSignal)

    override fun onMainCreate(activity: Activity?): View? {
        val activeActivity = activity ?: return null
        val preferences = activeActivity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        ownership.restoreCached(preferences.getBoolean(VERIFIED_AD_FREE, false))

        bannerAds?.destroy()
        val overlay = FrameLayout(activeActivity).apply {
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        bannerAds = BannerAds(activeActivity, overlay, ::emitAdState).also {
            it.setOwnership(ownership.canAdvertise(), ownership.verifiedAdFree)
        }
        return overlay
    }

    override fun shouldBeOnTop(): Boolean = true

    override fun onMainResume() {
        if (started) billing?.refreshPurchases()
        bannerAds?.setForeground(true)
    }

    override fun onMainPause() {
        bannerAds?.setForeground(false)
    }

    override fun onMainDestroy() {
        started = false
        bannerAds?.destroy()
        bannerAds = null
        billing?.close()
        billing = null
    }

    @UsedByGodot
    fun start() {
        if (started) return
        val hostActivity = activity ?: return
        started = true
        billing = PlayBilling(
            hostActivity.applicationContext,
            { activity },
            purchaseGenerations,
            ownership,
            ::emitStoreState,
            ::handlePurchaseState,
            ::emitPurchaseRefreshStarted,
            { open -> bannerAds?.setPurchaseDialogOpen(open) },
        ).also { it.start() }
    }

    @UsedByGodot
    fun refreshPurchases() {
        billing?.refreshPurchases()
    }

    @UsedByGodot
    fun buy() {
        billing?.buy()
    }

    @UsedByGodot
    fun showPrivacyOptions() {
        bannerAds?.showPrivacyOptions()
    }

    @UsedByGodot
    fun getCachedAdFree(): Boolean = ownership.verifiedAdFree

    @UsedByGodot
    fun setVerifiedAdFree(value: Boolean, generation: Long): Boolean =
        synchronized(purchaseGenerations) {
            if (!started || !purchaseGenerations.setVerifiedAdFreeIfCurrent(generation, ownership, value)) {
                return@synchronized false
            }
            activity?.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                ?.edit()
                ?.putBoolean(VERIFIED_AD_FREE, value)
                ?.apply()
            syncOwnership()
            true
        }

    @UsedByGodot
    fun getDensity(): Double = activity?.resources?.displayMetrics?.density?.toDouble() ?: 1.0

    @UsedByGodot
    fun setBannerBounds(left: Int, top: Int, width: Int, height: Int) {
        bannerAds?.setBounds(left, top, width, height)
    }

    @UsedByGodot
    fun setAdvertisingAllowed(allowed: Boolean) {
        bannerAds?.setAllowed(allowed)
    }

    private fun handlePurchaseState(generation: Long, status: String, token: String, error: String) {
        synchronized(purchaseGenerations) {
            if (!started) return@synchronized
            val currentBilling = billing ?: return@synchronized
            if (!currentBilling.isCurrentPurchaseGeneration(generation)) return@synchronized
            ownership.applyPurchaseState(status)
            syncOwnership()
            emitSignal(purchaseStateSignal.name, generation, status, token, error)
        }
    }


    private fun syncOwnership() {
        bannerAds?.setOwnership(ownership.canAdvertise(), ownership.verifiedAdFree)
    }
    private fun emitPurchaseRefreshStarted(generation: Long) {
        if (!started) return
        syncOwnership()
        emitSignal(purchaseRefreshStartedSignal.name, generation)
    }

    private fun emitStoreState(generation: Long, available: Boolean, formattedPrice: String, error: String) {
        if (started) emitSignal(storeStateSignal.name, generation, available, formattedPrice, error)
    }

    private fun emitAdState(loaded: Boolean, privacyRequired: Boolean, consentOpen: Boolean, error: String) {
        if (started) emitSignal(adStateSignal.name, loaded, privacyRequired, consentOpen, error)
    }

    private companion object {
        const val PREFERENCES = "zero_gx_monetization"
        const val VERIFIED_AD_FREE = "verified_ad_free"
    }
}
