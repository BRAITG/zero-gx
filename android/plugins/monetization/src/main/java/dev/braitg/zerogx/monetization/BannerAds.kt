package dev.braitg.zerogx.monetization

import android.app.Activity
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.google.android.libraries.ads.mobile.sdk.MobileAds
import com.google.android.libraries.ads.mobile.sdk.banner.AdSize
import com.google.android.libraries.ads.mobile.sdk.banner.AdView
import com.google.android.libraries.ads.mobile.sdk.banner.BannerAd
import com.google.android.libraries.ads.mobile.sdk.banner.BannerAdRequest
import com.google.android.libraries.ads.mobile.sdk.common.AdLoadCallback
import com.google.android.libraries.ads.mobile.sdk.common.AgeRestrictedTreatment
import com.google.android.libraries.ads.mobile.sdk.common.LoadAdError
import com.google.android.libraries.ads.mobile.sdk.common.RequestConfiguration
import com.google.android.libraries.ads.mobile.sdk.initialization.InitializationConfig
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform

internal class BannerAds(
    private val activity: Activity,
    private val host: FrameLayout,
    private val emitState: (Boolean, Boolean, Boolean, String) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val appId = activity.applicationInfo.metaData?.getString(APP_ID_METADATA).orEmpty()
    private val bannerUnitId = activity.applicationInfo.metaData?.getString(BANNER_ID_METADATA).orEmpty()

    @Volatile private var allowed = false
    @Volatile private var foreground = false
    @Volatile private var ownershipKnown = false
    @Volatile private var paid = false
    @Volatile private var paymentDialogOpen = false

    @Volatile private var destroyed = false
    private var boundsLeft = 0
    private var boundsTop = 0
    private var boundsWidth = 0
    private var boundsHeight = 0
    private var consentInformation: ConsentInformation? = null
    private var consentUpdateInFlight = false
    private var consentUpdated = false
    private var consentGeneration = 0L
    private var privacyRequired = false
    private var consentOpen = false
    private var canRequestAds = false
    private var sdkInitializing = false
    private var sdkInitialized = false
    private var adView: AdView? = null
    private var adLoaded = false
    private var adRequestInFlight = false
    private var adRequestGeneration = 0L

    fun setOwnership(known: Boolean, adFree: Boolean) {
        ownershipKnown = known
        paid = adFree
        onMain {
            if (adFree) {
                consentGeneration++
                invalidateAdRequest()
                destroyAdView()
                emit()
            } else {
                maybeContinue()
            }
        }
    }

    fun setForeground(value: Boolean) {
        foreground = value
        onMain {
            if (!value) {
                consentGeneration++
                invalidateAdRequest()
                hideBanner()
            } else {
                maybeContinue()
            }
        }
    }

    fun setAllowed(value: Boolean) {
        allowed = value
        onMain {
            if (!value) {
                consentGeneration++
                invalidateAdRequest()
                hideBanner()
            } else {
                maybeContinue()
            }
        }
    }

    fun setPurchaseDialogOpen(value: Boolean) {
        paymentDialogOpen = value
        onMain {
            if (value) {
                consentGeneration++
                invalidateAdRequest()
                hideBanner()
            } else {
                maybeContinue()
            }
        }
    }

    fun setBounds(left: Int, top: Int, width: Int, height: Int) {
        onMain {
            boundsLeft = left
            boundsTop = top
            boundsWidth = width
            boundsHeight = height
            updateBannerLayout()
            if (!hasRoom()) {
                hideBanner()
            } else {
                maybeContinue()
            }
        }
    }

    fun showPrivacyOptions() {
        onMain {
            val information = consentInformation
            if (destroyed || !allowed || !foreground || !ownershipKnown || paid || information == null || !privacyRequired || consentOpen) {
                emit()
                return@onMain
            }
            consentOpen = true
            invalidateAdRequest()
            hideBanner()
            emit()
            UserMessagingPlatform.showPrivacyOptionsForm(activity) { formError ->
                onMain {
                    consentOpen = false
                    updatePrivacyRequirement()
                    canRequestAds = information.canRequestAds()
                    val message = if (formError == null) "" else "Privacy choices could not be updated."
                    emit(message)
                    maybeContinue()
                }
            }
        }
    }

    fun destroy() {
        destroyed = true
        allowed = false
        foreground = false
        paid = true
        consentGeneration++
        onMain {
            destroyAdView()
            consentInformation = null
            emit()
        }
    }

    private fun maybeContinue() {
        if (!canBeginConsent()) {
            hideBanner()
            emit()
            return
        }
        if (appId.isBlank() || bannerUnitId.isBlank()) {
            hideBanner()
            emit("AdMob app or banner ID is not configured.")
            return
        }
        val information = consentInformation ?: UserMessagingPlatform.getConsentInformation(activity).also {
            consentInformation = it
        }
        if (!consentUpdated) {
            requestConsentUpdate(information)
            return
        }
        updatePrivacyRequirement()
        canRequestAds = information.canRequestAds()
        if (canRequestAds) initializeAds()
        else {
            hideBanner()
            emit()
        }
    }

    private fun requestConsentUpdate(information: ConsentInformation) {
        if (consentUpdateInFlight || !canBeginConsent()) return
        consentUpdateInFlight = true
        val requestGeneration = ++consentGeneration
        val parameters = ConsentRequestParameters.Builder()
            .setTagForUnderAgeOfConsent(true)
            .build()
        information.requestConsentInfoUpdate(
            activity,
            parameters,
            {
                onMain {
                    consentUpdateInFlight = false
                    if (destroyed || requestGeneration != consentGeneration) {
                        maybeContinue()
                        return@onMain
                    }
                    consentUpdated = true
                    updatePrivacyRequirement()
                    showRequiredConsentForm(requestGeneration, information)
                }
            },
            { _ ->
                onMain {
                    consentUpdateInFlight = false
                    if (destroyed || requestGeneration != consentGeneration) {
                        maybeContinue()
                        return@onMain
                    }
                    consentUpdated = true
                    updatePrivacyRequirement()
                    canRequestAds = information.canRequestAds()
                    if (canRequestAds) initializeAds()
                    else {
                        hideBanner()
                        emit("Consent information could not be refreshed.")
                    }
                }
            },
        )
    }

    private fun showRequiredConsentForm(requestGeneration: Long, information: ConsentInformation) {
        if (!canBeginConsent()) {
            emit()
            return
        }
        consentOpen = true
        invalidateAdRequest()
        hideBanner()
        emit()
        UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { formError ->
            onMain {
                consentOpen = false
                updatePrivacyRequirement()
                canRequestAds = information.canRequestAds()
                if (requestGeneration != consentGeneration || destroyed) {
                    emit()
                    maybeContinue()
                    return@onMain
                }
                if (canRequestAds) initializeAds()
                else {
                    hideBanner()
                    emit(if (formError == null) "" else "Consent form could not be completed.")
                }
            }
        }
    }

    private fun updatePrivacyRequirement() {
        privacyRequired = consentInformation?.privacyOptionsRequirementStatus ==
            ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
    }

    private fun initializeAds() {
        if (!canBeginConsent() || !canRequestAds || !hasRoom()) {
            hideBanner()
            emit()
            return
        }
        if (sdkInitialized) {
            loadBannerIfNeeded()
            return
        }
        if (sdkInitializing) return
        sdkInitializing = true
        Thread({
            if (destroyed || !allowed || !foreground || !ownershipKnown || paid || paymentDialogOpen) {
                onMain {
                    sdkInitializing = false
                    emit()
                }
                return@Thread
            }
            try {
                val requestConfiguration = RequestConfiguration.Builder()
                    .setAgeRestrictedTreatment(AgeRestrictedTreatment.CHILD)
                    .setMaxAdContentRating(RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_G)
                    .build()
                val config = InitializationConfig.Builder(appId)
                    .setRequestConfiguration(requestConfiguration)
                    .disableSdkCrashReporting()
                    .build()
                MobileAds.initialize(activity.applicationContext, config) {
                    MobileAds.setUserMutedApp(true)
                    MobileAds.setUserControlledAppVolume(0.0f)
                    onMain {
                        sdkInitializing = false
                        sdkInitialized = true
                        if (canBeginConsent() && canRequestAds) loadBannerIfNeeded() else emit()
                    }
                }
            } catch (_: Exception) {
                onMain {
                    sdkInitializing = false
                    hideBanner()
                    emit("Ad SDK initialization failed.")
                }
            }
        }, "ZeroGxAdsInit").start()
    }

    private fun loadBannerIfNeeded() {
        if (!canDisplayAds() || !hasRoom()) {
            hideBanner()
            emit()
            return
        }
        val existing = adView
        if (existing != null && (adLoaded || adRequestInFlight)) {
            updateBannerVisibility()
            emit()
            return
        }
        val view = existing ?: AdView(activity).also {
            it.setBackgroundColor(Color.TRANSPARENT)
            host.addView(it)
            adView = it
        }
        updateBannerLayout()
        adLoaded = false
        adRequestInFlight = true
        val requestGeneration = ++adRequestGeneration
        view.visibility = View.GONE
        view.loadAd(
            BannerAdRequest.Builder(bannerUnitId, AdSize.BANNER).build(),
            object : AdLoadCallback<BannerAd> {
                override fun onAdLoaded(ad: BannerAd) {
                    onMain {
                        if (requestGeneration != adRequestGeneration || destroyed) {
                            adRequestInFlight = false
                            destroyAdView()
                            if (canDisplayAds() && hasRoom()) loadBannerIfNeeded() else emit()
                            return@onMain
                        }
                        adRequestInFlight = false
                        adLoaded = true
                        if (canDisplayAds() && hasRoom()) updateBannerVisibility() else hideBanner()
                        emit()
                    }
                }

                override fun onAdFailedToLoad(adError: LoadAdError) {
                    onMain {
                        if (requestGeneration != adRequestGeneration || destroyed) {
                            adRequestInFlight = false
                            destroyAdView()
                            if (canDisplayAds() && hasRoom()) loadBannerIfNeeded() else emit()
                            return@onMain
                        }
                        adRequestInFlight = false
                        adLoaded = false
                        hideBanner()
                        emit("Banner ad could not be loaded.")
                    }
                }
            },
        )
    }

    private fun canBeginConsent(): Boolean =
        !destroyed && allowed && foreground && ownershipKnown && !paid && !paymentDialogOpen && !consentOpen

    private fun canDisplayAds(): Boolean = canBeginConsent() && hasRoom() && canRequestAds && sdkInitialized

    private fun hasRoom(): Boolean =
        boundsLeft >= 0 && boundsTop >= 0 &&
            boundsWidth >= AdSize.BANNER.getWidthInPixels(activity) &&
            boundsHeight >= AdSize.BANNER.getHeightInPixels(activity)

    private fun updateBannerLayout() {
        val view = adView ?: return
        val width = AdSize.BANNER.getWidthInPixels(activity)
        val height = AdSize.BANNER.getHeightInPixels(activity)
        view.layoutParams = FrameLayout.LayoutParams(width, height, Gravity.TOP or Gravity.LEFT).apply {
            leftMargin = boundsLeft
            topMargin = boundsTop
        }
    }

    private fun updateBannerVisibility() {
        adView?.visibility = if (canDisplayAds() && adLoaded && hasRoom()) View.VISIBLE else View.GONE
    }

    private fun hideBanner() {
        adView?.visibility = View.GONE
        emit()
    }

    private fun invalidateAdRequest() {
        if (adRequestInFlight) adRequestGeneration++
    }

    private fun destroyAdView() {
        val view = adView ?: return
        adView = null
        adLoaded = false
        adRequestInFlight = false
        (view.parent as? ViewGroup)?.removeView(view)
        view.destroy()
    }

    private fun emit(error: String = "") {
        emitState(adLoaded, privacyRequired, consentOpen, error)
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else handler.post { action() }
    }

    private companion object {
        const val APP_ID_METADATA = "com.google.android.gms.ads.APPLICATION_ID"
        const val BANNER_ID_METADATA = "dev.braitg.zerogx.BANNER_UNIT_ID"
    }
}
