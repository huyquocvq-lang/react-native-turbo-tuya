package com.jimmyvu.turbotuya.auth

// Viết theo docs/research/tuya-home-sdk-user-account.md (verbatim signatures) — CHƯA build-verify.
// ⚠️ Lần build đầu kiểm tra đường dẫn import của: IReNickNameCallback, IResetPasswordCallback,
// TempUnitEnum, INeedLoginListener (package com.thingclips.* có thể lệch theo bản SDK 7.5.x).

import com.jimmyvu.turbotuya.NativeTuyaAuthSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.user.api.ILoginCallback
import com.thingclips.smart.android.user.api.ILogoutCallback
import com.thingclips.smart.android.user.api.IReNickNameCallback
import com.thingclips.smart.android.user.api.IRegisterCallback
import com.thingclips.smart.android.user.api.IResetPasswordCallback
import com.thingclips.smart.android.user.api.TempUnitEnum
import com.thingclips.smart.android.user.bean.User
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.api.INeedLoginListener
import com.thingclips.smart.sdk.api.IResultCallback

// TuyaAuth — đăng ký/đăng nhập email + third-party + session + profile (B3 mở rộng).
class TuyaAuthModule(reactContext: ReactApplicationContext) :
  NativeTuyaAuthSpec(reactContext) {

  private val ctx = reactContext

  companion object {
    const val NAME = NativeTuyaAuthSpec.NAME
    private const val EVT_SESSION = "onSessionExpired"
  }

  init {
    // Đăng ký 1 lần: session hết hạn / bị kick-off → đẩy event onSessionExpired lên JS.
    try {
      ThingHomeSdk.setOnNeedLoginListener {
        emit(EVT_SESSION, Arguments.createMap().apply { putString("reason", "need_login") })
      }
    } catch (_: Throwable) {
      // listener optional; bỏ qua nếu SDK chưa init
    }
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  private fun todo(promise: Promise, what: String) {
    promise.reject(
      "not_implemented",
      "$what chưa wire (cần verify chữ ký native) — xem docs/research/tuya-home-sdk-user-account.md",
    )
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
        override fun onSuccess(user: User?) = promise.resolve(userToMap(user))
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "register_error", error)
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
    if (user == null) promise.reject("no_user", "Chưa đăng nhập")
    else promise.resolve(userToMap(user))
  }

  override fun syncUserInfo(promise: Promise) {
    ThingHomeSdk.getUserInstance().updateUserInfo(object : IResultCallback {
      override fun onSuccess() {
        val u = ThingHomeSdk.getUserInstance().user
        if (u == null) promise.reject("no_user", "Chưa đăng nhập") else promise.resolve(userToMap(u))
      }
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "sync_user_error", error)
    })
  }

  override fun logout(promise: Promise) {
    ThingHomeSdk.getUserInstance().logout(object : ILogoutCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "logout_error", error)
    })
  }

  override fun cancelAccount(promise: Promise) {
    ThingHomeSdk.getUserInstance().cancelAccount(object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "cancel_account_error", error)
    })
  }

  // ---------- Profile ----------
  override fun updateNickname(nickName: String, promise: Promise) {
    ThingHomeSdk.getUserInstance().updateNickName(nickName, object : IReNickNameCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "update_nickname_error", error)
    })
  }

  override fun updateTempUnit(unit: Double, promise: Promise) {
    // 1=Celsius, 2=Fahrenheit
    val tempUnit = if (unit.toInt() == 2) TempUnitEnum.Fahrenheit else TempUnitEnum.Celsius
    ThingHomeSdk.getUserInstance().setTempUnit(tempUnit, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "temp_unit_error", error)
    })
  }

  override fun updateTimeZone(timezoneId: String, promise: Promise) {
    ThingHomeSdk.getUserInstance().updateTimeZone(timezoneId, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "timezone_error", error)
    })
  }

  override fun updateAvatarByUrl(imageUrl: String, promise: Promise) {
    // updateAvatarWithImageUrl(url, IBooleanCallback) — DEPRECATED bởi Tuya (rủi ro compliance).
    // Ưu tiên avatar preset; để TODO tránh phụ thuộc API deprecated + IBooleanCallback.
    todo(promise, "updateAvatarByUrl (deprecated)")
  }

  // ---------- Reset password (OTP) ----------
  override fun resetEmailPassword(
    countryCode: String,
    email: String,
    code: String,
    newPassword: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().resetEmailPassword(
      countryCode, email, code, newPassword,
      object : IResetPasswordCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(errCode: String?, error: String?) =
          promise.reject(errCode ?: "reset_email_pw_error", error)
      },
    )
  }

  override fun resetPhonePassword(
    countryCode: String,
    phone: String,
    code: String,
    newPassword: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().resetPhonePassword(
      countryCode, phone, code, newPassword,
      object : IResetPasswordCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(errCode: String?, error: String?) =
          promise.reject(errCode ?: "reset_phone_pw_error", error)
      },
    )
  }

  // ---------- Third-party bind (bindThirdPlatform 5 String — thứ tự param chưa rõ → TODO verify) ----------
  override fun bindThirdParty(provider: String, token: String, extraInfo: String, promise: Promise) =
    todo(promise, "bindThirdParty")

  override fun unbindThirdParty(provider: String, promise: Promise) =
    todo(promise, "unbindThirdParty")

  override fun getLinkedThirdParties(promise: Promise) =
    todo(promise, "getLinkedThirdParties")

  // ---------- Multi-device (Android chưa có signature verbatim — TODO verify) ----------
  override fun getLoginTerminals(promise: Promise) =
    todo(promise, "getLoginTerminals (Android)")

  override fun terminateSession(terminalId: String, logoutCode: String, promise: Promise) =
    todo(promise, "terminateSession (Android)")

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

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
    m.putString("headPic", user?.headPic ?: "")
    m.putString("mobile", user?.mobile ?: "")
    m.putDouble("tempUnit", (user?.tempUnit ?: 0).toDouble())
    m.putString("timezoneId", user?.timezoneId ?: "")
    m.putString("countryCode", "") // Android User bean không expose countryCode trực tiếp (iOS có)
    m.putString("regionCode", "") // Android User bean không có regionCode (nằm trong Domain) — verify
    return m
  }
}
