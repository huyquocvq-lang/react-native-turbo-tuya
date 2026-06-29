package com.jimmyvu.turbotuya.auth

import com.jimmyvu.turbotuya.NativeTuyaAuthSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.thingclips.smart.android.user.api.ILoginCallback
import com.thingclips.smart.android.user.api.ILogoutCallback
import com.thingclips.smart.android.user.api.IRegisterCallback
import com.thingclips.smart.android.user.bean.User
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IResultCallback

// TuyaAuth — đăng ký/đăng nhập email + third-party + session.
class TuyaAuthModule(reactContext: ReactApplicationContext) :
  NativeTuyaAuthSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaAuthSpec.NAME
  }

  // ---------- Auth: email ----------
  override fun sendVerifyCode(
    email: String,
    countryCode: String,
    type: Double,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().sendVerifyCodeWithUserName(
      email, "", countryCode, type.toInt(),
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "send_code_error", error)
      },
    )
  }

  override fun registerWithEmail(
    countryCode: String,
    email: String,
    password: String,
    code: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().registerAccountWithEmail(
      countryCode, email, password, code,
      object : IRegisterCallback {
        override fun onSuccess(user: User?) {
          promise.resolve(userToMap(user))
        }
        override fun onError(code: String?, error: String?) {
          promise.reject(code ?: "register_error", error)
        }
      },
    )
  }

  override fun loginWithEmail(
    countryCode: String,
    email: String,
    password: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().loginWithEmail(
      countryCode, email, password, loginCallback(promise),
    )
  }

  override fun loginWithEmailCode(
    countryCode: String,
    email: String,
    code: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().loginWithEmailCode(
      countryCode, email, code, loginCallback(promise),
    )
  }

  // ---------- Auth: third-party (Google "gg" + idToken / Apple "ap") ----------
  override fun thirdLogin(
    countryCode: String,
    token: String,
    type: String,
    extraInfo: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().thirdLogin(
      countryCode, token, type, extraInfo, loginCallback(promise),
    )
  }

  // ---------- Session ----------
  override fun isLoggedIn(promise: Promise) {
    promise.resolve(ThingHomeSdk.getUserInstance().isLogin)
  }

  override fun getCurrentUser(promise: Promise) {
    val user = ThingHomeSdk.getUserInstance().user
    if (user == null) {
      promise.reject("no_user", "Chưa đăng nhập")
    } else {
      promise.resolve(userToMap(user))
    }
  }

  override fun logout(promise: Promise) {
    ThingHomeSdk.getUserInstance().logout(object : ILogoutCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "logout_error", error)
    })
  }

  // ---------- helpers ----------
  private fun loginCallback(promise: Promise) = object : ILoginCallback {
    override fun onSuccess(user: User?) = promise.resolve(userToMap(user))
    override fun onError(code: String?, error: String?) =
      promise.reject(code ?: "login_error", error)
  }

  private fun userToMap(user: User?): WritableMap {
    val m = Arguments.createMap()
    m.putString("uid", user?.uid ?: "")
    m.putString("email", user?.email ?: "")
    m.putString("nickName", user?.nickName ?: "")
    m.putString("sessionId", user?.sid ?: "")
    return m
  }
}
