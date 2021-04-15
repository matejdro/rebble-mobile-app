package io.rebble.cobble.bridges.background

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.view.FlutterCallbackInformation
import io.rebble.cobble.datasources.AndroidPreferences
import io.rebble.cobble.di.BackgroundFlutterSubcomponent
import io.rebble.cobble.pigeons.Pigeons
import io.rebble.cobble.util.registerAsyncPigeonCallback
import io.rebble.cobble.util.voidResult
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

@Singleton
class FlutterBackgroundController @Inject constructor(
        private val context: Context,
        private val androidPreferences: AndroidPreferences,
        private val backgroundFlutterSubcomponentFactory: BackgroundFlutterSubcomponent.Factory
) {
    private val mutex = Mutex()
    private var engine: FlutterEngine? = null

    suspend fun getBackgroundFlutterEngine(): FlutterEngine? {
        engine?.let { return it }

        mutex.withLock {
            val currentEngine = engine
            if (currentEngine != null) {
                return currentEngine
            }

            engine = initEngine()
            return engine
        }
    }

    private suspend fun initEngine(): FlutterEngine? = withContext(Dispatchers.Main.immediate) {
        // Flutter must be initialized on the main thread

        val backgroundEndpointMethodHandle = androidPreferences.backgroundEndpoint
                ?: return@withContext null

        val callbackInformation: FlutterCallbackInformation = try {
            FlutterCallbackInformation
                    .lookupCallbackInformation(backgroundEndpointMethodHandle)
        } catch (e: NullPointerException) {
            // Even though this method is marked as @NonNull, it can still return null which
            // confuses Kotlin runtime and crashes the app.

            // Catch this exception here and treat this error
            // as if set method handle is invalid.
            return@withContext null
        }

        val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()

        val callback = DartExecutor.DartCallback(
                context.assets,
                bundlePath,
                callbackInformation
        )

        val flutterEngine = FlutterEngine(context)

        createFlutterBridges(flutterEngine, callback)

        flutterEngine
    }

    private suspend fun createFlutterBridges(
            flutterEngine: FlutterEngine,
            callbackToStart: DartExecutor.DartCallback?
    ): Unit = coroutineScope {
        val bridgeScope = CoroutineScope(SupervisorJob())

        val dartExecutor = flutterEngine.dartExecutor
        val binaryMessenger = dartExecutor.binaryMessenger
        val androidSideReadyCompletable = CompletableDeferred<Unit>()

        val dartInitWait = launch {
            suspendCoroutine { continuation ->
                binaryMessenger.registerAsyncPigeonCallback(
                        GlobalScope + Dispatchers.Main.immediate,
                        "dev.flutter.pigeon.BackgroundControl.notifyFlutterBackgroundStarted"
                ) {
                    continuation.resume(Unit)

                    // Do not return from notifyFlutterBackgroundStarted() method until
                    // initEngine() has completed
                    androidSideReadyCompletable.join()

                    // Kill this callback to prevent re-call when flutter hot restarts
                    Pigeons.BackgroundControl.setup(binaryMessenger, null)

                    // Return blank result
                    voidResult
                }
            }
        }

        if (callbackToStart != null) {
            // We are starting the engine from scratch. Register all plugins and begin its run
            dartExecutor.executeDartCallback(callbackToStart)
            GeneratedPluginRegister.registerGeneratedPlugins(flutterEngine)
        }

        dartInitWait.join()

        val component = backgroundFlutterSubcomponentFactory.create(flutterEngine, bridgeScope)
        component.createCommonBridges()
        component.createBackgroundBridges()

        androidSideReadyCompletable.complete(Unit)

        flutterEngine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {
                bridgeScope.cancel()

                GlobalScope.launch(Dispatchers.Main.immediate) {
                    createFlutterBridges(flutterEngine, null)
                }
            }

            override fun onEngineWillDestroy() {
                bridgeScope.cancel()
            }
        })
    }
}