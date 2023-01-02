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

import android.os.Build
import android.service.controls.Control
import android.service.controls.templates.ToggleTemplate
import android.util.Log
import androidx.annotation.RequiresApi
import java.util.concurrent.Flow


@RequiresApi(Build.VERSION_CODES.R)
class LogSubscriber(val name: String) : Flow.Subscriber<Control> {
    var subscription: Flow.Subscription? = null

    override fun onSubscribe(subscription: Flow.Subscription?) {
        Log.d("LogSubscriber", "onSubscribe")
        this.subscription = subscription
        subscription?.request(Long.MAX_VALUE)
    }

    override fun onNext(item: Control?) {
        var log = "${item?.controlId}"
        if (item?.controlTemplate is ToggleTemplate) {
            log += ": ${(item.controlTemplate as ToggleTemplate).isChecked}"
        }
        Log.d(
                "LogSubscriber $name",
                log
        )
    }

    override fun onError(throwable: Throwable?) {
        Log.d("LogSubscriber $name", "onError: $throwable")
    }

    override fun onComplete() {
        Log.d("LogSubscriber $name", "onComplete")
    }

}
