package dev.braitg.zerogx.monetization

import android.app.Activity
import android.content.pm.PackageManager
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
    private val metadata = readApplicationMetadata()
    private val appId = metadata?.getString(APP_ID_METADATA).orEmpty()
    private val bannerUnitId = metadata?.getString(BANNER_ID_METADATA).orEmpty()
    private val adRequestState = AdRequestState()

    @Volatile private var allowed = false
    @Volatile private var foreground = false
    @Volatile private var ownershipKnown = false
    @Volatile private var paid = false
    @Volatile private var paymentDialogOpen = false
    @Volatile private var destroyed = false
    @Volatile private var consentOpen = false
    @Volatile private var canRequestAds = false

    private var boundsLeft = 0
    private var boundsTop = 0
    private var boundsWidth = 0
    private var boundsHeight = 0
    private var consentInformation: ConsentInformation? = null
    private var consentUpdateInFlight = false
    private var consentUpdated = false
    private var consentInformationUpdated = false
    private var consentFormAttempted = false
    private var privacyRequired = false
    private var sdkInitializing = false
    private var sdkInitialized = false
    private var adView: AdView? = null

    fun setOwnership(known: Boolean, adFree: Boolean) {
        ownershipKnown = known
        paid = adFree
        onMain {
            if (adFree) {
                invalidateAdRequest()
                destroyAdView()
                emit()
            }
            maybeContinue()
        }
    }

    fun setForeground(value: Boolean) {
        foreground = value
        onMain {
            if (!value) {
                invalidateAdRequest()
                hideBanner()
            } else {
                // A failed consent-information refresh is retried once per foreground.
                if (!consentInformationUpdated) consentUpdated = false
                maybeContinue()
            }
        }
    }

    fun setAllowed(value: Boolean) {
        allowed = value
        onMain {
            if (!value) {
                invalidateAdRequest()
                hideBanner()
            }
            maybeContinue()
        }
    }

    fun setPurchaseDialogOpen(value: Boolean) {
        paymentDialogOpen = value
        onMain {
            if (value) {
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
            if (!MonetizationGates.canShowPrivacyChoices(
                    destroyed = destroyed,
                    foreground = foreground,
                    informationAvailable = information != null,
                    privacyRequired = privacyRequired,
                    consentOpen = consentOpen,
                    paymentDialogOpen = paymentDialogOpen,
                )
            ) {
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
                    canRequestAds = information?.canRequestAds() == true
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
        onMain {
            destroyAdView()
            consentInformation = null
            emit()
        }
    }

    private fun maybeContinue() {
        if (!MonetizationGates.canRefreshConsentInformation(
                destroyed = destroyed,
                foreground = foreground,
                consentUpdateInFlight = consentUpdateInFlight,
                paymentDialogOpen = paymentDialogOpen,
                consentOpen = consentOpen,
            )
        ) {
            hideBanner()
            emit()
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
        if (!consentInformationUpdated) {
            if (canRequestAds && canBeginConsent()) {
                if (appId.isBlank() || bannerUnitId.isBlank()) {
                    hideBanner()
                    emit("AdMob app or banner ID is not configured.")
                } else {
                    initializeAds()
                }
            } else {
                hideBanner()
                emit()
            }
            return
        }
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
        if (MonetizationGates.shouldShowRequiredConsentForm(
                informationAvailable = consentInformation != null,
                informationUpdated = consentInformationUpdated,
                formAttempted = consentFormAttempted,
                destroyed = destroyed,
                advertisingAllowed = allowed,
                foreground = foreground,
                ownershipKnown = ownershipKnown,
                paid = paid,
                paymentDialogOpen = paymentDialogOpen,
                consentOpen = consentOpen,
            )
        ) {
            showRequiredConsentForm(information)
            return
        }
        if (canRequestAds) initializeAds()
        else {
            hideBanner()
            emit()
        }
    }

    private fun requestConsentUpdate(information: ConsentInformation) {
        if (!MonetizationGates.canRefreshConsentInformation(
                destroyed = destroyed,
                foreground = foreground,
                consentUpdateInFlight = consentUpdateInFlight,
                paymentDialogOpen = paymentDialogOpen,
                consentOpen = consentOpen,
            )
        ) return
        consentUpdateInFlight = true
        val parameters = ConsentRequestParameters.Builder()
            .setTagForUnderAgeOfConsent(true)
            .build()
        information.requestConsentInfoUpdate(
            activity,
            parameters,
            {
                onMain {
                    consentUpdateInFlight = false
                    if (destroyed) return@onMain
                    consentUpdated = true
                    consentInformationUpdated = true
                    updatePrivacyRequirement()
                    canRequestAds = information.canRequestAds()
                    maybeContinue()
                }
            },
            { _ ->
                onMain {
                    consentUpdateInFlight = false
                    if (destroyed) return@onMain
                    consentUpdated = true
                    consentInformationUpdated = false
                    updatePrivacyRequirement()
                    canRequestAds = information.canRequestAds()
                    if (canRequestAds && canBeginConsent()) maybeContinue()
                    else {
                        hideBanner()
                        emit("Consent information could not be refreshed.")
                    }
                }
            },
        )
    }

    private fun showRequiredConsentForm(information: ConsentInformation) {
        if (!canBeginConsent()) {
            emit()
            return
        }
        consentFormAttempted = true
        consentOpen = true
        invalidateAdRequest()
        hideBanner()
        emit()
        UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { formError ->
            onMain {
                consentOpen = false
                if (destroyed) return@onMain
                updatePrivacyRequirement()
                canRequestAds = information.canRequestAds()
                emit(if (formError == null || canRequestAds) "" else "Consent form could not be completed.")
                maybeContinue()
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
            try {
                val requestConfiguration = RequestConfiguration.Builder()
                    .setAgeRestrictedTreatment(AgeRestrictedTreatment.CHILD)
                    .setMaxAdContentRating(RequestConfiguration.MaxAdContentRating.MAX_AD_CONTENT_RATING_G)
                    .build()
                val config = InitializationConfig.Builder(appId)
                    .setRequestConfiguration(requestConfiguration)
                    .disableSdkCrashReporting()
                    .build()
                if (!canInitializeAdsNow()) {
                    onMain {
                        sdkInitializing = false
                        emit()
                    }
                    return@Thread
                }
                MobileAds.initialize(activity.applicationContext, config) {
                    MobileAds.setUserMutedApp(true)
                    MobileAds.setUserControlledAppVolume(0.0f)
                    onMain {
                        sdkInitializing = false
                        canRequestAds = consentInformation?.canRequestAds() == true
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

    private fun canInitializeAdsNow(): Boolean = MonetizationGates.canInitializeAds(
        destroyed = destroyed,
        advertisingAllowed = allowed,
        foreground = foreground,
        ownershipKnown = ownershipKnown,
        paid = paid,
        paymentDialogOpen = paymentDialogOpen,
        consentOpen = consentOpen,
        canRequestAds = canRequestAds,
    )

    private fun loadBannerIfNeeded() {
        if (!canDisplayAds() || !hasRoom()) {
            hideBanner()
            emit()
            return
        }
        val existing = adView
        if (existing != null && (adRequestState.loaded || adRequestState.inFlight)) {
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
        val requestGeneration = adRequestState.beginRequest()
        view.visibility = View.GONE
        view.loadAd(
            BannerAdRequest.Builder(bannerUnitId, AdSize.BANNER).build(),
            object : AdLoadCallback<BannerAd> {
                override fun onAdLoaded(ad: BannerAd) {
                    onMain {
                        if (destroyed || !adRequestState.completeLoaded(requestGeneration)) return@onMain
                        if (canDisplayAds() && hasRoom()) updateBannerVisibility() else hideBanner()
                        emit()
                    }
                }

                override fun onAdFailedToLoad(adError: LoadAdError) {
                    onMain {
                        if (destroyed || !adRequestState.completeFailed(requestGeneration)) return@onMain
                        hideBanner()
                        emit("Banner ad could not be loaded.")
                    }
                }
            },
        )
    }

    private fun canBeginConsent(): Boolean = MonetizationGates.canBeginConsent(
        destroyed = destroyed,
        advertisingAllowed = allowed,
        foreground = foreground,
        ownershipKnown = ownershipKnown,
        paid = paid,
        paymentDialogOpen = paymentDialogOpen,
        consentOpen = consentOpen,
    )
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
        adView?.visibility = if (canDisplayAds() && adRequestState.loaded && hasRoom()) View.VISIBLE else View.GONE
    }

    private fun hideBanner() {
        adView?.visibility = View.GONE
        emit()
    }

    private fun invalidateAdRequest() {
        if (adRequestState.invalidate()) destroyAdView()
    }

    private fun destroyAdView() {
        val view = adView ?: return
        adView = null
        adRequestState.resetForViewDestroy()
        (view.parent as? ViewGroup)?.removeView(view)
        view.destroy()
    }

    private fun emit(error: String = "") {
        emitState(adRequestState.loaded, privacyRequired, consentOpen, error)
    }

    @Suppress("DEPRECATION")
    private fun readApplicationMetadata() = try {
        activity.packageManager.getApplicationInfo(activity.packageName, PackageManager.GET_META_DATA).metaData
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else handler.post { action() }
    }

    private companion object {
        const val APP_ID_METADATA = "com.google.android.gms.ads.APPLICATION_ID"
        const val BANNER_ID_METADATA = "dev.braitg.zerogx.BANNER_UNIT_ID"
    }
}
