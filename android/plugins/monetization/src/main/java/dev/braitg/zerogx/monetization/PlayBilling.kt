package dev.braitg.zerogx.monetization

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams

internal class PlayBilling(
    context: Context,
    private val activity: () -> Activity?,
    private val emitStoreState: (Long, Boolean, String, String) -> Unit,
    private val emitPurchaseState: (Long, String, String, String) -> Unit,
    private val setPurchaseDialogOpen: (Boolean) -> Unit,
    private val markOwnershipUnknown: () -> Unit,
) {
    private data class ConnectionRequest(
        val ready: () -> Unit,
        val failed: (Int) -> Unit,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val connectionRequests = mutableListOf<ConnectionRequest>()
    private val client = BillingClient.newBuilder(context.applicationContext)
        .setListener { result, purchases -> onMain { handlePurchaseUpdate(result, purchases) } }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    @Volatile private var closed = false
    private var connecting = false
    private var setupComplete = false
    private var purchaseFlowOpen = false

    fun start() {
        val productGeneration = nextGeneration()
        val purchasesGeneration = nextPurchaseGeneration()
        onMain {
            ensureConnected(
                ready = {
                    queryProductDetails(productGeneration)
                    queryOwnedPurchases(purchasesGeneration)
                },
                failed = { responseCode ->
                    emitStoreState(productGeneration, false, "", billingError("Product details", responseCode))
                    emitPurchaseState(purchasesGeneration, "error", "", billingError("Purchase query", responseCode))
                },
            )
        }
    }

    fun refreshPurchases(onComplete: (() -> Unit)? = null) {
        markOwnershipUnknown()
        val queryGeneration = nextPurchaseGeneration()
        onMain {
            ensureConnected(
                ready = { queryOwnedPurchases(queryGeneration, onComplete) },
                failed = { responseCode ->
                    emitPurchaseState(queryGeneration, "error", "", billingError("Purchase query", responseCode))
                    onComplete?.invoke()
                },
            )
        }
    }

    fun buy() {
        val productGeneration = nextGeneration()
        onMain {
            if (closed || purchaseFlowOpen) return@onMain
            if (activity() == null) {
                emitPurchaseState(nextPurchaseGeneration(), "error", "", "Google Play is unavailable without an Android activity.")
                return@onMain
            }
            setFlowOpen(true)
            ensureConnected(
                ready = {
                    queryProductDetails(productGeneration) { product, offer ->
                        if (!isCurrentGeneration(productGeneration)) {
                            setFlowOpen(false)
                        } else if (product == null || offer == null) {
                            emitPurchaseState(nextPurchaseGeneration(), "error", "", "Remove ads is unavailable on Google Play.")
                            setFlowOpen(false)
                        } else {
                            val offerToken = offer.offerToken
                            if (offerToken == null || offerToken.isBlank()) {
                                emitPurchaseState(nextPurchaseGeneration(), "error", "", "Google Play did not provide a valid purchase offer.")
                                setFlowOpen(false)
                            } else {
                                launchPurchase(product, offerToken)
                            }
                        }
                    }
                },
                failed = { responseCode ->
                    emitStoreState(productGeneration, false, "", billingError("Product details", responseCode))
                    emitPurchaseState(nextPurchaseGeneration(), "error", "", billingError("Purchase flow", responseCode))
                    setFlowOpen(false)
                },
            )
        }
    }

    fun isCurrentGeneration(value: Long): Boolean = generationState.isCurrentProductDetails(value)

    fun isCurrentPurchaseGeneration(value: Long): Boolean = generationState.isCurrentPurchase(value)

    fun close() {
        if (closed) return
        closed = true
        onMain {
            connectionRequests.clear()
            connecting = false
            purchaseFlowOpen = false
            client.endConnection()
        }
    }

    private fun ensureConnected(ready: () -> Unit, failed: (Int) -> Unit) {
        if (closed) return
        if (client.isReady || setupComplete) {
            ready()
            return
        }
        connectionRequests.add(ConnectionRequest(ready, failed))
        if (connecting) return
        connecting = true
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                onMain {
                    connecting = false
                    val waiting = connectionRequests.toList()
                    connectionRequests.clear()
                    if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                        setupComplete = true
                        waiting.forEach { it.ready() }
                    } else {
                        waiting.forEach { it.failed(result.responseCode) }
                    }
                }
            }

            override fun onBillingServiceDisconnected() {
                // Automatic service reconnection is enabled on the single BillingClient.
            }
        })
    }

    private fun queryProductDetails(
        queryGeneration: Long,
        completion: ((ProductDetails?, ProductDetails.OneTimePurchaseOfferDetails?) -> Unit)? = null,
    ) {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(PRODUCT_ID)
                        .setProductType(BillingClient.ProductType.INAPP)
                        .build(),
                ),
            )
            .build()

        client.queryProductDetailsAsync(params) { result, queryResult ->
            onMain {
                if (closed) return@onMain
                val product = if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    queryResult.productDetailsList.firstOrNull { it.productId == PRODUCT_ID }
                } else {
                    null
                }
                val offer = product?.oneTimePurchaseOfferDetailsList?.firstOrNull()
                val price = offer?.formattedPrice.orEmpty()
                val available = product != null && offer != null && price.isNotEmpty()
                val error = when {
                    result.responseCode != BillingClient.BillingResponseCode.OK -> billingError("Product details", result.responseCode)
                    !available -> "Remove ads is unavailable on Google Play."
                    else -> ""
                }
                emitStoreState(queryGeneration, available, if (available) price else "", error)
                completion?.invoke(if (available) product else null, if (available) offer else null)
            }
        }
    }

    private fun queryOwnedPurchases(queryGeneration: Long, onComplete: (() -> Unit)? = null) {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP)
            .build()
        client.queryPurchasesAsync(params) { result, purchases ->
            onMain {
                if (closed) return@onMain
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    emitPurchaseState(queryGeneration, "error", "", billingError("Purchase query", result.responseCode))
                } else {
                    val owned = purchases.filter { PRODUCT_ID in it.products }
                    val purchase = owned.firstOrNull { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                        ?: owned.firstOrNull()
                    if (purchase == null) {
                        emitPurchaseState(queryGeneration, "not_owned", "", "")
                    } else {
                        emitPurchase(queryGeneration, purchase)
                    }
                }
                onComplete?.invoke()
            }
        }
    }

    private fun launchPurchase(product: ProductDetails, offerToken: String) {
        val host = activity()
        if (host == null || closed) {
            emitPurchaseState(nextPurchaseGeneration(), "error", "", "Google Play is unavailable without an Android activity.")
            setFlowOpen(false)
            return
        }
        val detailsParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(product)
            .setOfferToken(offerToken)
            .build()
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(detailsParams))
            .build()
        val result = client.launchBillingFlow(host, params)
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> Unit
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                markOwnershipUnknown()
                refreshPurchases { setFlowOpen(false) }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                emitPurchaseState(nextPurchaseGeneration(), "cancelled", "", "")
                setFlowOpen(false)
            }
            else -> {
                emitPurchaseState(nextPurchaseGeneration(), "error", "", billingError("Purchase flow", result.responseCode))
                setFlowOpen(false)
            }
        }
    }

    private fun handlePurchaseUpdate(result: BillingResult, purchases: List<Purchase>?) {
        if (closed) return
        val updateGeneration = nextPurchaseGeneration()
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val owned = purchases.orEmpty().filter { PRODUCT_ID in it.products }
                if (owned.isEmpty()) {
                    refreshPurchases { setFlowOpen(false) }
                    return
                }
                owned.forEach { emitPurchase(updateGeneration, it) }
                setFlowOpen(false)
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                emitPurchaseState(updateGeneration, "cancelled", "", "")
                setFlowOpen(false)
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                markOwnershipUnknown()
                refreshPurchases { setFlowOpen(false) }
            }
            else -> {
                emitPurchaseState(updateGeneration, "error", "", billingError("Purchase update", result.responseCode))
                setFlowOpen(false)
            }
        }
    }

    private fun emitPurchase(generation: Long, purchase: Purchase) {
        when (purchase.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> emitPurchaseState(generation, "purchased", purchase.purchaseToken, "")
            Purchase.PurchaseState.PENDING -> emitPurchaseState(generation, "pending", "", "")
            else -> emitPurchaseState(generation, "error", "", "Google Play returned an unsupported purchase state.")
        }
    }

    private fun setFlowOpen(open: Boolean) {
        if (purchaseFlowOpen == open) return
        purchaseFlowOpen = open
        setPurchaseDialogOpen(open)
    }

    private fun nextGeneration(): Long = generationState.nextProductDetails()

    private fun nextPurchaseGeneration(): Long = generationState.nextPurchaseQuery()

    private fun billingError(operation: String, responseCode: Int): String =
        "$operation failed (Google Play response $responseCode)."

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else handler.post { action() }
    }

    private companion object {
        const val PRODUCT_ID = "remove_ads"
        private val generationState = BillingGenerationState()
    }
}
