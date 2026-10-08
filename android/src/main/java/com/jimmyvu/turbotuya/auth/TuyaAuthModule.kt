package com.jimmyvu.turbotuya.auth

// Viết theo docs/research/tuya-home-sdk-user-account.md (verbatim signatures) - CHƯA build-verify.
// ⚠️ Lần build đầu kiểm tra đường dẫn import của: IReNickNameCallback, IResetPasswordCallback,
// TempUnitEnum, INeedLoginListener (package com.thingclips.* có thể lệch theo bản SDK 7.5.x).

import com.jimmyvu.turbotuya.NativeTuyaAuthSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.user.api.IBooleanCallback
import com.thingclips.smart.android.user.api.ILoginCallback
import com.thingclips.smart.android.user.api.ILogoutCallback
import com.thingclips.smart.android.user.api.IReNickNameCallback
import com.thingclips.smart.android.user.api.IRegisterCallback
import com.thingclips.smart.android.user.api.IResetPasswordCallback
import com.thingclips.smart.android.user.api.IThirdBindCallback
import com.thingclips.smart.android.user.api.IUserBusinessCallback
import com.thingclips.smart.android.user.bean.BindResultBean
import com.thingclips.smart.android.user.bean.User
import com.thingclips.smart.android.user.bean.UserLoginMultiterminalVO
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.INeedLoginListener
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.enums.TempUnitEnum

// TuyaAuth - đăng ký/đăng nhập email + third-party + session + profile (B3 mở rộng).
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

  // API không tồn tại trong SDK Android 7.5.6 → giữ mã 'not_implemented' (README) nhưng nói rõ lý do.
  private fun unsupported(promise: Promise, what: String, why: String) =
    TuyaReject.reject(promise, "not_implemented", "$what is not available on Android: $why")

  // SDK bỏ qua callback (không gọi onError) ở vài API khi user == null → chặn trước để promise không treo.
  private fun requireUser(promise: Promise): User? {
    val u = ThingHomeSdk.getUserInstance().user
    if (u == null) TuyaReject.reject(promise, "no_user", "Not logged in")
    return u
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
    // SDK nhận thẳng URL → không cần tải ảnh về native. ⚠️ Tuya khuyến nghị app tự quản lý avatar (iOS đã
    // deprecate API này): server có thể trả USER_AVATAR_UPLOAD_REJECT_FOR_CUSTOMIZE → reject nguyên mã SDK.
    ThingHomeSdk.getUserInstance().updateAvatarWithImageUrl(imageUrl, object : IBooleanCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        TuyaReject.reject(promise, code ?: "update_avatar_error", error)
    })
  }

  // ---------- Login identity: bind/change email or phone via OTP ----------
  override fun sendBindEmailCode(countryCode: String, email: String, promise: Promise) {
    ThingHomeSdk.getUserInstance().sendBindVerifyCodeWithEmail(
      countryCode, email,
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "send_bind_email_code_error", error)
      },
    )
  }

  override fun sendBindPhoneCode(countryCode: String, phone: String, promise: Promise) {
    ThingHomeSdk.getUserInstance().sendBindVerifyCode(
      countryCode, phone,
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "send_bind_phone_code_error", error)
      },
    )
  }

  override fun bindEmail(
    countryCode: String,
    email: String,
    code: String,
    sessionId: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().bindEmail(
      countryCode, email, code, sessionId,
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "bind_email_error", error)
      },
    )
  }

  override fun bindMobile(countryCode: String, phone: String, code: String, promise: Promise) {
    ThingHomeSdk.getUserInstance().bindMobile(
      countryCode, phone, code,
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "bind_mobile_error", error)
      },
    )
  }

  override fun changeUserName(
    countryCode: String,
    code: String,
    sessionId: String,
    userName: String,
    promise: Promise,
  ) {
    ThingHomeSdk.getUserInstance().changeUserName(
      countryCode, code, sessionId, userName,
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "change_username_error", error)
      },
    )
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

  // ---------- Third-party bind ----------
  override fun bindThirdParty(provider: String, token: String, extraInfo: String, promise: Promise) {
    val user = requireUser(promise) ?: return
    // Thứ tự 5 String verify từ bytecode SDK 7.5.6 (→ API thing.m.user.third.bind v1.0):
    // (countryCode, type, accessToken, extraInfo, options). Spec không có countryCode → dùng phoneCode
    // (mã quốc gia) của user đang login. extraInfo '' → null (SDK bỏ key, giống iOS thirdLogin truyền nil);
    // options để null (SDK không có giá trị mặc định cho bind).
    ThingHomeSdk.getUserInstance().bindThirdPlatform(
      user.phoneCode ?: "", provider, token, extraInfo.ifEmpty { null }, null,
      object : IThirdBindCallback {
        override fun onSuccess(result: BindResultBean?) = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "bind_third_error", error)
      },
    )
  }

  // SDK 7.5.6 KHÔNG có unbind/list: IThingUser chỉ có bindThirdPlatform, và không jar nào chứa API name
  // third.unbind / third.list (đã soát toàn bộ jar 7.5.6).
  override fun unbindThirdParty(provider: String, promise: Promise) =
    unsupported(
      promise, "unbindThirdParty",
      "Tuya Home SDK 7.5.6 has no unbind API for third-party accounts (IThingUser only exposes bindThirdPlatform)",
    )

  override fun getLinkedThirdParties(promise: Promise) =
    unsupported(
      promise, "getLinkedThirdParties",
      "Tuya Home SDK 7.5.6 has no API that lists the third-party accounts linked to the current user",
    )

  // ---------- Multi-device login ----------
  override fun getLoginTerminals(promise: Promise) {
    requireUser(promise) ?: return
    // → m.life.user.terminal.login.list (UserLoginMultiterminalVO.terminalLoginList) - cùng field với iOS.
    ThingHomeSdk.getUserInstance().getUserLoginMultiTerminal(
      object : IUserBusinessCallback<UserLoginMultiterminalVO> {
        override fun onSuccess(result: UserLoginMultiterminalVO?) {
          val arr = Arguments.createArray()
          result?.terminalLoginList?.forEach { t ->
            arr.pushMap(Arguments.createMap().apply {
              putString("terminalId", t.terminalId ?: "")
              putString("platform", t.platform ?: "")
              putString("os", t.os ?: "")
              putDouble("loginTime", (t.loginTime ?: 0L).toDouble())
            })
          }
          promise.resolve(arr)
        }
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "login_terminals_error", error)
      },
    )
  }

  override fun terminateSession(terminalId: String, logoutCode: String, promise: Promise) {
    requireUser(promise) ?: return
    // logoutMultiTerminal(terminalId, loginOutCode) → m.life.user.terminal.login.out (verify bytecode 7.5.6).
    ThingHomeSdk.getUserInstance().logoutMultiTerminal(
      terminalId, logoutCode,
      object : IBooleanCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "terminate_session_error", error)
      },
    )
  }

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
    m.putString("countryCode", user?.phoneCode ?: "") // User.getPhoneCode() = mã vùng lúc đăng ký (iOS countryCode)
    m.putString("regionCode", user?.domain?.regionCode ?: "") // nằm trong User.getDomain()
    return m
  }
}
