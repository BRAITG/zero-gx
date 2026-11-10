package dev.braitg.zerogx.monetization

internal class OwnershipState {
    @Volatile var verifiedAdFree = false
        private set
    @Volatile var ownershipKnown = false
        private set
    @Volatile var refreshInProgress = false
        private set

    fun restoreCached(value: Boolean) {
        verifiedAdFree = value
        ownershipKnown = value
        refreshInProgress = false
    }

    fun setVerifiedAdFree(value: Boolean) {
        verifiedAdFree = value
        ownershipKnown = true
        refreshInProgress = false
    }

    fun beginPurchaseRefresh() {
        refreshInProgress = true
        if (!verifiedAdFree) ownershipKnown = false
    }

    fun applyPurchaseState(status: String) {
        when (status) {
            "not_owned" -> {
                refreshInProgress = false
                if (!verifiedAdFree) ownershipKnown = true
            }
            "purchased", "pending" -> {
                refreshInProgress = false
                if (!verifiedAdFree) ownershipKnown = false
            }
            "error" -> refreshInProgress = false
        }
    }


    fun canAdvertise(): Boolean = ownershipKnown && !verifiedAdFree && !refreshInProgress
}

internal class BillingGenerationState {
    private var latest = 0L
    private var latestProductDetails = 0L
    private var latestPurchase = 0L

    @Synchronized
    fun nextProductDetails(): Long {
        latest += 1
        latestProductDetails = latest
        return latest
    }

    @Synchronized
    fun nextPurchase(): Long = advancePurchase()

    @Synchronized
    fun nextPurchaseQuery(): Long = advancePurchase()

    @Synchronized
    fun beginPurchaseQuery(ownership: OwnershipState): Long {
        val generation = advancePurchase()
        ownership.beginPurchaseRefresh()
        return generation
    }

    @Synchronized
    fun nextPurchaseUpdate(): Long = advancePurchase()

    @Synchronized
    fun isCurrentProductDetails(generation: Long): Boolean = latestProductDetails == generation

    @Synchronized
    fun isCurrentPurchase(generation: Long): Boolean = latestPurchase == generation

    @Synchronized
    fun setVerifiedAdFreeIfCurrent(generation: Long, ownership: OwnershipState, value: Boolean): Boolean {
        if (latestPurchase != generation) return false
        ownership.setVerifiedAdFree(value)
        return true
    }

    private fun advancePurchase(): Long {
        latest += 1
        latestPurchase = latest
        return latest
    }
}

internal object MonetizationGates {
    fun canRefreshConsentInformation(
        destroyed: Boolean,
        foreground: Boolean,
        consentUpdateInFlight: Boolean,
        paymentDialogOpen: Boolean,
        consentOpen: Boolean,
    ): Boolean =
        !destroyed && foreground && !consentUpdateInFlight && !paymentDialogOpen && !consentOpen

    fun canBeginConsent(
        destroyed: Boolean,
        advertisingAllowed: Boolean,
        foreground: Boolean,
        ownershipKnown: Boolean,
        paid: Boolean,
        paymentDialogOpen: Boolean,
        consentOpen: Boolean,
    ): Boolean =
        !destroyed && advertisingAllowed && foreground && ownershipKnown && !paid &&
            !paymentDialogOpen && !consentOpen

    fun shouldShowRequiredConsentForm(
        informationAvailable: Boolean,
        informationUpdated: Boolean,
        formAttempted: Boolean,
        destroyed: Boolean,
        advertisingAllowed: Boolean,
        foreground: Boolean,
        ownershipKnown: Boolean,
        paid: Boolean,
        paymentDialogOpen: Boolean,
        consentOpen: Boolean,
    ): Boolean =
        informationAvailable && informationUpdated && !formAttempted &&
            canBeginConsent(
                destroyed,
                advertisingAllowed,
                foreground,
                ownershipKnown,
                paid,
                paymentDialogOpen,
                consentOpen,
            )

    fun canShowPrivacyChoices(
        destroyed: Boolean,
        foreground: Boolean,
        informationAvailable: Boolean,
        privacyRequired: Boolean,
        consentOpen: Boolean,
        paymentDialogOpen: Boolean,
    ): Boolean =
        !destroyed && foreground && informationAvailable && privacyRequired &&
            !consentOpen && !paymentDialogOpen

    fun canInitializeAds(
        destroyed: Boolean,
        advertisingAllowed: Boolean,
        foreground: Boolean,
        ownershipKnown: Boolean,
        paid: Boolean,
        paymentDialogOpen: Boolean,
        consentOpen: Boolean,
        canRequestAds: Boolean,
    ): Boolean =
        !destroyed && advertisingAllowed && foreground && ownershipKnown && !paid &&
            !paymentDialogOpen && !consentOpen && canRequestAds
}

internal class AdRequestState {
    var generation = 0L
        private set
    var inFlight = false
        private set
    var loaded = false
        private set

    fun beginRequest(): Long {
        generation += 1
        inFlight = true
        loaded = false
        return generation
    }

    fun invalidate(): Boolean {
        if (!inFlight) return false
        generation += 1
        inFlight = false
        loaded = false
        return true
    }

    fun completeLoaded(callbackGeneration: Long): Boolean {
        if (callbackGeneration != generation) return false
        inFlight = false
        loaded = true
        return true
    }

    fun completeFailed(callbackGeneration: Long): Boolean {
        if (callbackGeneration != generation) return false
        inFlight = false
        loaded = false
        return true
    }

    fun resetForViewDestroy() {
        if (inFlight) generation += 1
        inFlight = false
        loaded = false
    }
}
