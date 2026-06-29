package com.coolbath.tuyareactnative

// ⚠️ VIẾT THEO docs/research/tuya-m1-sdk-foundation.md — CHƯA build/verify trên máy thật
// (thiếu Android SDK + JDK17 + security-algorithm.aar). Khi build lần đầu cần kiểm tra lại:
//  - đường dẫn import package Tuya (com.thingclips.*) có thể lệch theo bản SDK 7.5.6
//  - tên getter của User/HomeBean/DeviceBean
//  - chữ ký BLE scan (LeScanSetting/BleScanResponse)
// Init đọc AppKey/AppSecret từ AndroidManifest meta-data của app tiêu thụ (xem SETUP.md).

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.ble.api.LeScanSetting
import com.thingclips.smart.android.ble.api.ScanType
import com.thingclips.smart.android.user.api.ILoginCallback
import com.thingclips.smart.android.user.api.ILogoutCallback
import com.thingclips.smart.android.user.api.IRegisterCallback
import com.thingclips.smart.android.user.bean.User
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.bean.HomeBean
import com.thingclips.smart.home.sdk.callback.IThingGetHomeListCallback
import com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback
import com.thingclips.smart.sdk.api.IDevListener
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingActivator
import com.thingclips.smart.sdk.api.IThingActivatorGetToken
import com.thingclips.smart.sdk.api.IThingDevice
import com.thingclips.smart.sdk.api.IThingSmartActivatorListener
import com.thingclips.smart.sdk.bean.ActivatorBuilder
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.enums.ActivatorModelEnum
import org.json.JSONObject

class TuyaReactNativeModule(reactContext: ReactApplicationContext) :
  NativeTuyaReactNativeSpec(reactContext) {

  private val ctx = reactContext
  private val devices = mutableMapOf<String, IThingDevice>()
  private var wifiActivator: IThingActivator? = null

  companion object {
    const val NAME = NativeTuyaReactNativeSpec.NAME
    private const val EVT_DEVICE = "onDeviceStatus"
    private const val EVT_PAIRING = "onPairingProgress"
    private const val EVT_BLE = "onBleScan"
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  // ---------- Init ----------
  override fun initSdk(promise: Promise) {
    try {
      // AppKey/AppSecret lấy từ meta-data trong AndroidManifest của app tiêu thụ.
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

  // ---------- Home ----------
  override fun createHome(
    name: String,
    lon: Double,
    lat: Double,
    geoName: String,
    rooms: ReadableArray,
    promise: Promise,
  ) {
    val roomList = (0 until rooms.size()).mapNotNull { rooms.getString(it) }
    ThingHomeSdk.getHomeManagerInstance().createHome(
      name, lon, lat, geoName, roomList,
      object : IThingHomeResultCallback {
        override fun onSuccess(bean: HomeBean?) = promise.resolve(homeToMap(bean))
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "create_home_error", error)
      },
    )
  }

  override fun getHomeList(promise: Promise) {
    ThingHomeSdk.getHomeManagerInstance().queryHomeList(
      object : IThingGetHomeListCallback {
        override fun onSuccess(homeBeans: MutableList<HomeBean>?) {
          val arr = Arguments.createArray()
          homeBeans?.forEach { arr.pushMap(homeToMap(it)) }
          promise.resolve(arr)
        }
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "home_list_error", error)
      },
    )
  }

  override fun getHomeDetail(homeId: Double, promise: Promise) {
    ThingHomeSdk.newHomeInstance(homeId.toLong()).getHomeDetail(
      object : IThingHomeResultCallback {
        override fun onSuccess(bean: HomeBean?) = promise.resolve(homeToMap(bean))
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "home_detail_error", error)
      },
    )
  }

  // ---------- Pairing: Wi-Fi (EZ/AP) ----------
  override fun getPairingToken(homeId: Double, promise: Promise) {
    ThingHomeSdk.getActivatorInstance().getActivatorToken(
      homeId.toLong(),
      object : IThingActivatorGetToken {
        override fun onSuccess(token: String?) = promise.resolve(token)
        override fun onFailure(code: String?, error: String?) =
          promise.reject(code ?: "token_error", error)
      },
    )
  }

  override fun startWifiPairing(
    mode: String,
    ssid: String,
    password: String,
    token: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    val model =
      if (mode.equals("AP", true)) ActivatorModelEnum.TY_AP else ActivatorModelEnum.TY_EZ
    val builder = ActivatorBuilder()
      .setSsid(ssid)
      .setPassword(password)
      .setContext(ctx)
      .setActivatorModel(model)
      .setTimeOut(timeoutSec.toLong())
      .setToken(token)
      .setListener(object : IThingSmartActivatorListener {
        override fun onActiveSuccess(devResp: DeviceBean?) =
          promise.resolve(deviceToMap(devResp))
        override fun onError(code: String?, msg: String?) =
          promise.reject(code ?: "pairing_error", msg)
        override fun onStep(step: String?, data: Any?) {
          val m = Arguments.createMap()
          m.putString("step", step ?: "")
          m.putString("dataJson", data?.toString() ?: "")
          emit(EVT_PAIRING, m)
        }
      })
    wifiActivator = ThingHomeSdk.getActivatorInstance().newMultiActivator(builder)
    wifiActivator?.start()
  }

  override fun stopWifiPairing() {
    wifiActivator?.stop()
    wifiActivator?.onDestroy()
    wifiActivator = null
  }

  // ---------- Pairing: BLE ----------
  // ⚠️ Chữ ký BLE scan (LeScanSetting/BleScanResponse/ScanDeviceBean) cần verify trên SDK thật.
  override fun startBleScan(timeoutSec: Double) {
    val setting = LeScanSetting.Builder()
      .setTimeout(timeoutSec.toLong() * 1000)
      .addScanType(ScanType.SINGLE)
      .build()
    ThingHomeSdk.getBleOperator().startLeScan(setting) { bean ->
      val m = Arguments.createMap()
      m.putString("id", bean?.id ?: "")
      m.putString("name", bean?.name ?: "")
      m.putString("productId", bean?.productId ?: "")
      m.putString("uuid", bean?.uuid ?: "")
      m.putString("mac", bean?.mac ?: "")
      m.putString("address", bean?.address ?: "")
      m.putDouble("deviceType", (bean?.deviceType ?: 0).toDouble())
      emit(EVT_BLE, m)
    }
  }

  override fun stopBleScan() {
    ThingHomeSdk.getBleOperator().stopLeScan()
  }

  override fun startBlePairing(
    homeId: Double,
    uuid: String,
    productId: String,
    address: String,
    deviceType: Double,
    timeoutSec: Double,
    promise: Promise,
  ) {
    // TODO(verify): dựng BleActivatorBean từ kết quả scan + newBleActivator().startActivator(...)
    // Chữ ký BleActivatorBean/IBleActivatorListener cần kiểm tra trên SDK 7.5.6.
    promise.reject(
      "ble_pairing_todo",
      "BLE pairing chưa wire — cần verify BleActivatorBean/IBleActivatorListener trên máy thật.",
    )
  }

  // ---------- Device control (DP) ----------
  override fun publishDps(devId: String, dpsJson: String, promise: Promise) {
    deviceOf(devId).publishDps(dpsJson, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "publish_dps_error", error)
    })
  }

  override fun getDps(devId: String, promise: Promise) {
    try {
      val bean: DeviceBean? = ThingHomeSdk.getDataInstance().getDeviceBean(devId)
      val dps = bean?.dps ?: emptyMap<String, Any>()
      promise.resolve(JSONObject(dps as Map<*, *>).toString())
    } catch (e: Throwable) {
      promise.reject("get_dps_error", e)
    }
  }

  override fun registerDeviceListener(devId: String) {
    deviceOf(devId).registerDevListener(object : IDevListener {
      override fun onDpUpdate(id: String?, dpStr: String?) {
        val m = Arguments.createMap()
        m.putString("devId", id ?: devId)
        m.putString("dpsJson", dpStr ?: "{}")
        emit(EVT_DEVICE, m)
      }
      override fun onRemoved(id: String?) {}
      override fun onStatusChanged(id: String?, online: Boolean) {
        val m = Arguments.createMap()
        m.putString("devId", id ?: devId)
        m.putBoolean("isOnline", online)
        emit(EVT_DEVICE, m)
      }
      override fun onNetworkStatusChanged(id: String?, status: Boolean) {}
      override fun onDevInfoUpdate(id: String?) {}
    })
  }

  override fun unregisterDeviceListener(devId: String) {
    devices[devId]?.unRegisterDevListener()
    devices[devId]?.onDestroy()
    devices.remove(devId)
  }

  // RN event emitter plumbing (no-op; bắt buộc có cho NativeEventEmitter)
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // ---------- helpers ----------
  private fun deviceOf(devId: String): IThingDevice =
    devices.getOrPut(devId) { ThingHomeSdk.newDeviceInstance(devId) }

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

  private fun homeToMap(bean: HomeBean?): WritableMap {
    val m = Arguments.createMap()
    m.putDouble("homeId", (bean?.homeId ?: 0L).toDouble())
    m.putString("name", bean?.name ?: "")
    m.putDouble("role", (bean?.role ?: 0).toDouble())
    m.putBoolean("admin", bean?.isAdmin ?: false)
    m.putDouble("lon", bean?.lon ?: 0.0)
    m.putDouble("lat", bean?.lat ?: 0.0)
    m.putString("geoName", bean?.geoName ?: "")
    return m
  }

  private fun deviceToMap(bean: DeviceBean?): WritableMap {
    val m = Arguments.createMap()
    m.putString("devId", bean?.devId ?: "")
    m.putString("name", bean?.name ?: "")
    m.putString("productId", bean?.productId ?: "")
    m.putBoolean("isOnline", bean?.isOnline ?: false)
    m.putString("iconUrl", bean?.iconUrl ?: "")
    return m
  }
}
