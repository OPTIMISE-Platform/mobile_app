/*
 * Copyright 2022 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

package org.infai.optimise.mobile_app

import android.content.Context
import android.os.Build
import android.service.controls.Control
import android.service.controls.ControlsProviderService
import android.service.controls.actions.BooleanAction
import android.service.controls.actions.ControlAction
import android.service.controls.actions.FloatAction
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.google.gson.JsonParser
import io.reactivex.processors.FlowableProcessor
import io.reactivex.processors.ReplayProcessor
import org.reactivestreams.FlowAdapters
import java.util.concurrent.Flow
import java.util.function.Consumer

@RequiresApi(Build.VERSION_CODES.R)
class AppControlsProviderService : ControlsProviderService(), FlutterPlugin {

    companion object {
        var binaryMessenger: BinaryMessenger? = null
        const val TAG = "AppControlsProviderSe.."
        var updateProcessor: ReplayProcessor<Control> = ReplayProcessor.create()

        // The engine the service started for itself while the app was not
        // running (ensureFlutterReady). Null once the app's engine took over.
        private var ownEngine: FlutterEngine? = null
    }

    override fun createPublisherForAllAvailable(): Flow.Publisher<Control> {
        ensureFlutterReady()
        val processor = ReplayProcessor.create<Control>()

        val handler = StatelessResultHandler(baseContext, processor)
        MethodChannel(binaryMessenger!!, "flutter/controlMethodChannel")
                .invokeMethod("getToggleStateless", null, handler)

        val flow = FlowAdapters.toFlowPublisher(processor)
        flow.subscribe(LogSubscriber("ALL"))
        return flow
    }

    override fun createPublisherFor(controlIds: MutableList<String>): Flow.Publisher<Control> {
        Log.d(TAG, "createPublisherFor: Requested for ${controlIds}}")
        ensureFlutterReady()

        val toggleStreamHandler = ToggleStreamHandler(baseContext, updateProcessor, controlIds)
        MethodChannel(binaryMessenger!!, "flutter/controlMethodChannel").setMethodCallHandler(toggleStreamHandler)
        val statefulResultHandler = StatefulResultHandler(baseContext, updateProcessor)
        val states = mutableListOf<DeviceState>()
        for (controlId in controlIds) {
            states.add(DeviceState(controlId))
        }
        MethodChannel(
                binaryMessenger!!,
                "flutter/controlMethodChannel"
        ).invokeMethod("getToggleStates",
                DeviceState.toJSONList(states), statefulResultHandler)
        return FlowAdapters.toFlowPublisher(updateProcessor)
    }

    override fun performControlAction(controlId: String, action: ControlAction, consumer: Consumer<Int>) {
        ensureFlutterReady()

        val state = DeviceState(controlId)
        // A group's control is a toggle as well; Dart finds out what the id means.
        val method = when (action) {
            is BooleanAction -> {
                state.value = action.newState
                "setToggle"
            }
            is FloatAction -> {
                state.value = action.newValue.toDouble()
                "setValue"
            }
            else -> {
                Log.w(TAG, "Unsupported action: $action")
                consumer.accept(ControlAction.RESPONSE_FAIL)
                return
            }
        }
        MethodChannel(binaryMessenger!!, "flutter/controlMethodChannel")
                .invokeMethod(
                        method,
                        state.toJSON(),
                        ToggleResultHandler(baseContext, updateProcessor, state, consumer)
                )
    }

    init {
        FlowAdapters.toFlowPublisher(updateProcessor).subscribe(LogSubscriber("UPD"))
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "Attached to engine")
        binaryMessenger = binding.binaryMessenger
        // The app has started: its engine answers the controls from now on, and
        // the service's own one stops. Both run in this process, and two Dart
        // isolates keeping the same Hive boxes open lose each other's writes
        // and read stale settings (docs/device-commands.md).
        val own = ownEngine
        if (own != null && own.dartExecutor !== binding.binaryMessenger) {
            Log.d(TAG, "App engine attached, stopping the controls engine")
            ownEngine = null
            own.destroy()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "Detached from engine")
        // An engine that already took over stays.
        if (binaryMessenger === binding.binaryMessenger) {
            binaryMessenger = null
        }
        updateProcessor.onComplete()
        updateProcessor = ReplayProcessor.create()
    }

    private fun ensureFlutterReady() {
        if (binaryMessenger == null) {
            Log.d(TAG, "binaryMessenger NULL")
            Log.d(TAG, "Try init flutter Engine")
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(baseContext)
            loader.ensureInitializationComplete(baseContext, null)
            val engine = FlutterEngine(baseContext)
            ownEngine = engine
            engine.plugins.add(AppControlsProviderService())
            // Not main: that runs the whole app, which needs a view this engine
            // does not have. controlsMain sets up what the controls need.
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "controlsMain"))
            Log.d(TAG, "Flutter Engine inited")
            Log.d(TAG, "Binary Messanger now: " + binaryMessenger.toString())
        }
    }
}

private class StatelessResultHandler(
        val context: Context,
        val processor: FlowableProcessor<Control>,
) : MethodChannel.Result {
    @RequiresApi(Build.VERSION_CODES.R)
    override fun success(result: Any?) {
        val states = DeviceState.fromJSONList(result.toString())
        for (state in states) {
            processor.onNext(state.statelessControl(context))
        }
        processor.onComplete()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        Log.e("StatelessResultHandler", "ERROR: ($errorCode) $errorMessage $errorDetails")
        processor.onError(Throwable(errorCode))
    }

    override fun notImplemented() {
        Log.e("StatelessResultHandler", "ERROR: Not Implemented")
        processor.onError(Throwable("Not Implemented"))
    }
}

private class ToggleStreamHandler(
        val context: Context,
        val processor: FlowableProcessor<Control>,
        val controlIds: MutableList<String>
) : MethodChannel.MethodCallHandler {

    @RequiresApi(Build.VERSION_CODES.R)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "toggleEvent" -> {
                val state = DeviceState(call.arguments.toString())
                if (!controlIds.contains(state.getId())) {
                    return
                }
                processor.onNext(state.statefulControl(context))
            }

            else -> result.notImplemented()
        }
    }
}

private class StatefulResultHandler(
        val context: Context,
        val processor: FlowableProcessor<Control>,
) : MethodChannel.Result {
    @RequiresApi(Build.VERSION_CODES.R)
    override fun success(result: Any?) {
        val states = DeviceState.fromJSONList(result.toString())
        for (state in states) {
            processor.onNext(state.statefulControl(context))
        }
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        Log.e("StatefulResultHandler", "ERROR: ($errorCode) $errorMessage")
        processor.onError(Throwable(errorCode))
    }

    override fun notImplemented() {
        Log.e("StatefulResultHandler", "ERROR: Not Implemented")
        processor.onError(Throwable("Not Implemented"))
    }
}

private class ToggleResultHandler(
        val context: Context,
        val processor: FlowableProcessor<Control>,
        val state: DeviceState,
        val consumer: Consumer<Int>,
) : MethodChannel.Result {
    // The answer holds the command's responses and the entry as it is now, with
    // the value read back for a range.
    // An answer that cannot be read fails the action instead of leaving the
    // system waiting for it.
    @RequiresApi(Build.VERSION_CODES.R)
    override fun success(result: Any?) {
        val control = try {
            val answer = JsonParser.parseString(result.toString()).asJsonObject
            val responses = DeviceCommandResponse.fromJSONList(answer.get("responses").toString())
            if (responses.isEmpty() || responses.any { it.status_code != 200 }) {
                null
            } else {
                val updated = if (answer.has("state") && !answer.get("state").isJsonNull) DeviceState(answer.get("state").toString()) else state
                updated.statefulControl(context)
            }
        } catch (e: Exception) {
            Log.e("ToggleResultHandler", "Unreadable answer: $result", e)
            null
        }
        if (control == null) {
            consumer.accept(ControlAction.RESPONSE_FAIL)
            return
        }
        processor.onNext(control)
        consumer.accept(ControlAction.RESPONSE_OK)
    }

    // Only this action fails; an error on the shared processor would end the
    // updates of every control.
    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        Log.e("ToggleResultHandler", "ERROR: ($errorCode) $errorMessage")
        consumer.accept(ControlAction.RESPONSE_FAIL)
    }

    override fun notImplemented() {
        Log.e("ToggleResultHandler", "ERROR: Not Implemented")
        consumer.accept(ControlAction.RESPONSE_FAIL)
    }
}
