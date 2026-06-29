package com.jimmyvu.turbotuya.core

import com.jimmyvu.turbotuya.NativeTuyaCoreSpec
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.thingclips.smart.home.sdk.ThingHomeSdk

// TuyaCore — init/destroy SDK. AppKey/AppSecret đọc từ AndroidManifest meta-data của app tiêu thụ.
class TuyaCoreModule(reactContext: ReactApplicationContext) :
  NativeTuyaCoreSpec(reactContext) {

  private val ctx = reactContext

  companion object {
    const val NAME = NativeTuyaCoreSpec.NAME
  }

  override fun initSdk(promise: Promise) {
    try {
      ThingHomeSdk.init(ctx.applicationContext as android.app.Application)
      promise.resolve(true)
    } catch (e: Throwable) {
      promise.reject("init_error", e)
    }
  }

  override fun getSdkVersion(promise: Promise) {
    // Tuya không expose hằng version ổn định qua API public → trả version đã pin.
    promise.resolve("thingsmart:7.5.6")
  }

  override fun destroySdk() {
    ThingHomeSdk.onDestroy()
  }
}
