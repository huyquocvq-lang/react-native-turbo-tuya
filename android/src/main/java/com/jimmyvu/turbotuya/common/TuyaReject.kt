package com.jimmyvu.turbotuya.common

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise

/**
 * Reject a Promise with the standard TuyaError shape { code, message, domain }.
 * domain: "sdk" (on-device SDK), "cloud" (OpenAPI), "network". Matches src/errors.ts (TuyaErrors).
 * Dùng dần cho các module mới — đừng nuốt code về "-1".
 */
object TuyaReject {
  @JvmStatic
  @JvmOverloads
  fun reject(promise: Promise, code: String?, message: String?, domain: String = "sdk") {
    val info = Arguments.createMap().apply { putString("domain", domain) }
    promise.reject(code ?: "unknown", message ?: "", info)
  }
}
