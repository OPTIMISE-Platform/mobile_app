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

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.controls.Control
import android.service.controls.ControlsProviderService
import android.service.controls.DeviceTypes
import android.service.controls.actions.BooleanAction
import android.service.controls.actions.ControlAction
import android.service.controls.templates.ControlButton
import android.service.controls.templates.ToggleTemplate
import android.util.Log
import androidx.annotation.RequiresApi
import com.google.gson.Gson
import io.flutter.plugin.common.MethodChannel
import io.reactivex.processors.FlowableProcessor
import io.reactivex.processors.PublishProcessor
import io.reactivex.processors.ReplayProcessor
import org.reactivestreams.FlowAdapters
import java.util.concurrent.Flow
import java.util.function.Consumer


@RequiresApi(Build.VERSION_CODES.R)
class AppControlsProviderService : ControlsProviderService() {

    private lateinit var updatePublisher: ReplayProcessor<Control>

    var enabled = false;

    override fun createPublisherForAllAvailable(): Flow.Publisher<Control> {
        val context: Context = baseContext
        val i = Intent(this, MainActivity::class.java)
        val pi =
                PendingIntent.getActivity(
                        context,
                        -1 /*CONTROL_REQUEST_CODE*/,
                        i,
                        PendingIntent.FLAG_IMMUTABLE
                )

        val processor = PublishProcessor.create<Control>()

        val handler = StatelessResultHandler(processor, pi)
        AndroidPipe.flutterEngine?.dartExecutor?.let {
            MethodChannel(
                it.binaryMessenger,
                "flutter/controlMethodChannel"
            ).invokeMethod("getToggleStateless", null, handler)
        }
        return FlowAdapters.toFlowPublisher(processor)
    }

    override fun createPublisherFor(controlIds: MutableList<String>): Flow.Publisher<Control> {
        val context: Context = baseContext
        /* Fill in details for the activity related to this device. On long press,
         * this Intent will be launched in a bottomsheet. Please design the activity
         * accordingly to fit a more limited space (about 2/3 screen height).
         */
        // val i = Intent(this, CustomSettingsActivity::class.java)
        val i = Intent(this, MainActivity::class.java)
        val pi =
            PendingIntent.getActivity(
                context,
                -1 /*CONTROL_REQUEST_CODE*/,
                i,
                PendingIntent.FLAG_IMMUTABLE
            )
        updatePublisher = ReplayProcessor.create()


        val control =
            Control.StatefulBuilder("switch-0", pi)
                // Required: The name of the control
                .setTitle("switch-0")
                // Required: Usually the room where the control is located
                .setSubtitle("")
                // Required: Type of device, i.e., thermostat, light, switch
                .setDeviceType(DeviceTypes.TYPE_LIGHT) // For example, DeviceTypes.TYPE_THERMOSTAT
                .setStatus(Control.STATUS_OK)
                .setControlTemplate(ToggleTemplate("",  ControlButton(
                    enabled,
                    "Toggle switch"
                ) ))
                .build()

        updatePublisher.onNext(control)


        // If you have other controls, check that they have been selected here

        // Uses the Reactive Streams API
        updatePublisher.onNext(control)

        return FlowAdapters.toFlowPublisher(updatePublisher);
    }

    override fun performControlAction(
        controlId: String, action: ControlAction, consumer: Consumer<Int>
    ) {


        /* First, locate the control identified by the controlId. Once it is located, you can
         * interpret the action appropriately for that specific device. For instance, the following
         * assumes that the controlId is associated with a light, and the light can be turned on
         * or off.
         */

        consumer.accept(ControlAction.RESPONSE_OK)
        val context: Context = baseContext
        val i = Intent(this, MainActivity::class.java)

        val pi =
            PendingIntent.getActivity(
                context, -1 /*CONTROL_REQUEST_CODE*/, i,
                PendingIntent.FLAG_IMMUTABLE
            )

        enabled = !enabled

        val control =
            Control.StatefulBuilder("switch-0", pi)
                // Required: The name of the control
                .setTitle("switch-0")
                // Required: Usually the room where the control is located
                .setSubtitle("")
                // Required: Type of device, i.e., thermostat, light, switch
                .setDeviceType(DeviceTypes.TYPE_LIGHT) // For example, DeviceTypes.TYPE_THERMOSTAT
                .setStatus(Control.STATUS_OK)
                .setControlTemplate(ToggleTemplate("",  ControlButton(
                    !enabled,
                    "Toggle switch"
                ) ))
                .build()
        updatePublisher.onNext(control);


        if (action is BooleanAction) {


            // Inform SystemUI that the action has been received and is being processed
            consumer.accept(ControlAction.RESPONSE_OK)

            // In this example, action.getNewState() will have the requested action: true for “On”,
            // false for “Off”.

            /* This is where application logic/network requests would be invoked to update the state of
             * the device.
             * After updating, the application should use the publisher to update SystemUI with the new
             * state.
             */

        }
    }
}

private class StatelessResultHandler: MethodChannel.Result {

    val processor: FlowableProcessor<Control>
    val pi: PendingIntent

    constructor(flow: FlowableProcessor<Control>, pi: PendingIntent) {
        this.processor = flow
        this.pi = pi
    }

    @RequiresApi(Build.VERSION_CODES.R)
    override fun success(result: Any?) {
        val states: Array<DeviceState> = Gson().fromJson(result.toString(), Array<DeviceState>::class.java)
        for (state in states) {
            Log.d("StatelessResultHandler", "Publishing " + state.name + " ("+state.serviceGroupName+")")
            processor.onNext(statelessControl(state))
        }
        processor.onComplete()
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        Log.e("StatelessResultHandler", "ERROR: ($errorCode) $errorMessage")
        processor.onError(Throwable(errorCode))
    }

    override fun notImplemented() {
        Log.e("StatelessResultHandler", "ERROR: Not Implemented")
        processor.onError(Throwable("Not Implemented"))
    }

    @RequiresApi(Build.VERSION_CODES.R)
    fun statelessControl(state: DeviceState): Control {
        var subtitle = ""
        var title = ""
        if (state.name != null) {
            title = state.name!!
        }
        if (state.serviceGroupName != null) {
            subtitle = state.serviceGroupName!!
        }
        return Control.StatelessBuilder(state.deviceId + state.serviceId, pi)
            // Required: The name of the control
            .setTitle(title)
            // Required: Usually the room where the control is located
            .setSubtitle(subtitle)
            // Required: Type of device, i.e., thermostat, light, switch
            .setDeviceType(DeviceTypes.TYPE_SWITCH) // For example, DeviceTypes.TYPE_THERMOSTAT
            .build()
    }

}

/*
@RequiresApi(Build.VERSION_CODES.R)
    fun statefulControl(state: DeviceState): Control {
        val i = Intent(this, MainActivity::class.java)
        val pi =
            PendingIntent.getActivity(
                context,
                -1 /*CONTROL_REQUEST_CODE*/,
                i,
                PendingIntent.FLAG_IMMUTABLE
            )
        var subtitle = ""
        if (state.name != null) {
            title = state.name!!
        }
        if (state.serviceGroupName != null) {
            subtitle = state.serviceGroupName!!
        }
        return Control.StatefulBuilder(state.deviceId + state.serviceId, pi)
                // Required: The name of the control
                .setTitle(title)
                // Required: Usually the room where the control is located
                .setSubtitle(subtitle)
                // Required: Type of device, i.e., thermostat, light, switch
                .setDeviceType(DeviceTypes.TYPE_SWITCH) // For example, DeviceTypes.TYPE_THERMOSTAT
                .setStatus(Control.STATUS_OK)
                .setControlTemplate(
                    ToggleTemplate(
                        "", ControlButton(
                            state.value.toString().toBoolean(),
                            "Toggle switch"
                        )
                    )
                )
                .build()
    }
 */