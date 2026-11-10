package dev.braitg.zerogx.monetization

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonetizationStateTest {
    @Test
    fun refreshMakesKnownUnpaidOwnershipUnknownEvenWhenTheQueryErrors() {
        val ownership = OwnershipState()
        ownership.setVerifiedAdFree(false)
        assertTrue(ownership.canAdvertise())

        ownership.beginPurchaseRefresh()
        assertFalse(ownership.canAdvertise())
        ownership.applyPurchaseState("error")
        assertFalse(ownership.canAdvertise())
    }

    @Test
    fun successfulEmptyRefreshRestoresKnownUnpaidOwnership() {
        val ownership = OwnershipState()
        ownership.setVerifiedAdFree(false)
        ownership.beginPurchaseRefresh()
        ownership.applyPurchaseState("not_owned")

        assertTrue(ownership.canAdvertise())
    }

    @Test
    fun purchaseQueryDoesNotMakeCurrentBuyProductDetailsStale() {
        val generations = BillingGenerationState()
        val buyDetails = generations.nextProductDetails()

        generations.nextPurchase()

        assertTrue(generations.isCurrentProductDetails(buyDetails))
    }

    @Test
    fun newerPendingPurchaseQueryMakesOlderGenerationNonCurrent() {
        val generations = BillingGenerationState()
        val olderQuery = generations.nextPurchaseQuery()
        val newerQuery = generations.nextPurchaseQuery()

        assertTrue(newerQuery > olderQuery)
        assertFalse(generations.isCurrentPurchase(olderQuery))
        assertTrue(generations.isCurrentPurchase(newerQuery))
    }

    @Test
    fun staleInactiveVerificationCannotClearPaidOwnershipAfterNewerRefreshErrors() {
        val generations = BillingGenerationState()
        val ownership = OwnershipState()
        ownership.restoreCached(true)
        val staleVerification = generations.beginPurchaseQuery(ownership)
        val currentRefresh = generations.beginPurchaseQuery(ownership)
        assertFalse(generations.isCurrentPurchase(staleVerification))
        assertTrue(generations.isCurrentPurchase(currentRefresh))
        assertFalse(generations.setVerifiedAdFreeIfCurrent(staleVerification, ownership, false))
        ownership.applyPurchaseState("error")

        assertTrue(ownership.verifiedAdFree)
        assertFalse(ownership.canAdvertise())
    }

    @Test
    fun currentPurchaseGenerationCanCommitVerifiedOwnership() {
        val generations = BillingGenerationState()
        val ownership = OwnershipState()
        ownership.restoreCached(true)
        val currentRefresh = generations.beginPurchaseQuery(ownership)
        ownership.applyPurchaseState("not_owned")

        assertTrue(generations.setVerifiedAdFreeIfCurrent(currentRefresh, ownership, false))
        assertFalse(ownership.verifiedAdFree)
        assertTrue(ownership.canAdvertise())
    }

    @Test
    fun paidColdStartDiscoversPrivacyInformationAndLaterUnpaidCanShowRequiredForm() {
        assertTrue(
            MonetizationGates.canRefreshConsentInformation(
                destroyed = false,
                foreground = true,
                consentUpdateInFlight = false,
                paymentDialogOpen = false,
                consentOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.canRefreshConsentInformation(
                destroyed = false,
                foreground = true,
                consentUpdateInFlight = false,
                paymentDialogOpen = true,
                consentOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.shouldShowRequiredConsentForm(
                informationAvailable = true,
                informationUpdated = true,
                formAttempted = false,
                destroyed = false,
                advertisingAllowed = false,
                foreground = true,
                ownershipKnown = false,
                paid = true,
                paymentDialogOpen = false,
                consentOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.canInitializeAds(
                destroyed = false,
                advertisingAllowed = true,
                foreground = true,
                ownershipKnown = true,
                paid = true,
                paymentDialogOpen = false,
                consentOpen = false,
                canRequestAds = true,
            ),
        )
        assertFalse(
            MonetizationGates.canShowPrivacyChoices(
                destroyed = false,
                foreground = true,
                informationAvailable = false,
                privacyRequired = true,
                consentOpen = false,
                paymentDialogOpen = false,
            ),
        )
        assertTrue(
            MonetizationGates.shouldShowRequiredConsentForm(
                informationAvailable = true,
                informationUpdated = true,
                formAttempted = false,
                destroyed = false,
                advertisingAllowed = true,
                foreground = true,
                ownershipKnown = true,
                paid = false,
                paymentDialogOpen = false,
                consentOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.shouldShowRequiredConsentForm(
                informationAvailable = true,
                informationUpdated = true,
                formAttempted = true,
                destroyed = false,
                advertisingAllowed = true,
                foreground = true,
                ownershipKnown = true,
                paid = false,
                paymentDialogOpen = false,
                consentOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.canInitializeAds(
                destroyed = false,
                advertisingAllowed = true,
                foreground = true,
                ownershipKnown = true,
                paid = false,
                paymentDialogOpen = false,
                consentOpen = false,
                canRequestAds = false,
            ),
        )
    }

    @Test
    fun requiredPrivacyChoicesDoNotDependOnAdvertisingEligibility() {
        assertTrue(
            MonetizationGates.canShowPrivacyChoices(
                destroyed = false,
                foreground = true,
                informationAvailable = true,
                privacyRequired = true,
                consentOpen = false,
                paymentDialogOpen = false,
            ),
        )
    }

    @Test
    fun privacyChoicesStillRespectLifecycleAndDialogGuards() {
        assertFalse(
            MonetizationGates.canShowPrivacyChoices(
                destroyed = true,
                foreground = true,
                informationAvailable = true,
                privacyRequired = true,
                consentOpen = false,
                paymentDialogOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.canShowPrivacyChoices(
                destroyed = false,
                foreground = false,
                informationAvailable = true,
                privacyRequired = true,
                consentOpen = false,
                paymentDialogOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.canShowPrivacyChoices(
                destroyed = false,
                foreground = true,
                informationAvailable = true,
                privacyRequired = true,
                consentOpen = true,
                paymentDialogOpen = false,
            ),
        )
        assertFalse(
            MonetizationGates.canShowPrivacyChoices(
                destroyed = false,
                foreground = true,
                informationAvailable = true,
                privacyRequired = true,
                consentOpen = false,
                paymentDialogOpen = true,
            ),
        )
    }

    @Test
    fun queuedInitializationRechecksCurrentConsentAndPermission() {
        var consentOpen = false
        var canRequestAds = true
        val queuedInitialization = {
            MonetizationGates.canInitializeAds(
                destroyed = false,
                advertisingAllowed = true,
                foreground = true,
                ownershipKnown = true,
                paid = false,
                paymentDialogOpen = false,
                consentOpen = consentOpen,
                canRequestAds = canRequestAds,
            )
        }

        assertTrue(queuedInitialization())
        consentOpen = true
        assertFalse(queuedInitialization())
        consentOpen = false
        canRequestAds = false
        assertFalse(queuedInitialization())
    }

    @Test
    fun staleLoadedCallbackCannotClearANewerAdRequest() {
        val state = AdRequestState()
        val staleRequest = state.beginRequest()
        state.invalidate()
        state.resetForViewDestroy()
        val currentRequest = state.beginRequest()

        assertFalse(state.completeLoaded(staleRequest))
        assertEquals(currentRequest, state.generation)
        assertTrue(state.inFlight)
        assertFalse(state.loaded)
    }

    @Test
    fun staleFailedCallbackCannotClearANewerAdRequest() {
        val state = AdRequestState()
        val staleRequest = state.beginRequest()
        state.invalidate()
        state.resetForViewDestroy()
        val currentRequest = state.beginRequest()

        assertFalse(state.completeFailed(staleRequest))
        assertEquals(currentRequest, state.generation)
        assertTrue(state.inFlight)
        assertFalse(state.loaded)
    }

}

