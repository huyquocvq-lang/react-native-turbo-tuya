package com.jimmyvu.turbotuya.pairing

import com.jimmyvu.turbotuya.NativeTuyaPairingSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.ble.api.LeScanSetting
import com.thingclips.smart.android.ble.api.ScanDeviceBean
import com.thingclips.smart.android.ble.api.ScanType
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IBleActivatorListener
import com.thingclips.smart.sdk.api.IThingActivator
import com.thingclips.smart.sdk.api.IThingActivatorGetToken
import com.thingclips.smart.sdk.api.IThingSmartActivatorListener
import com.thingclips.smart.sdk.bean.ActivatorBuilder
import com.thingclips.smart.sdk.bean.BleActivatorBean
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.enums.ActivatorModelEnum

// TuyaPairing — ghép nối Wi-Fi (EZ/AP) + BLE. Phát event onPairingProgress / onBleScan.
class TuyaPairingModule(reactContext: ReactApplicationContext) :
  NativeTuyaPairingSpec(reactContext) {

  private val ctx = reactContext
  private var wifiActivator: IThingActivator? = null
  // Cache ScanDeviceBean theo uuid để dựng BleActivatorBean lúc pairing (BLE pairing cần bean gốc).
  private val scannedBle = mutableMapOf<String, ScanDeviceBean>()

  companion object {
    const val NAME = NativeTuyaPairingSpec.NAME
    private const val EVT_PAIRING = "onPairingProgress"
    private const val EVT_BLE = "onBleScan"
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  // ---------- Wi-Fi token ----------
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

  // ---------- Wi-Fi pairing (EZ/AP) ----------
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

  // ---------- BLE scan + pairing ----------
  override fun startBleScan(timeoutSec: Double) {
    val setting = LeScanSetting.Builder()
      .setTimeout(timeoutSec.toLong() * 1000)
      .addScanType(ScanType.SINGLE)
      .build()
    ThingHomeSdk.getBleOperator().startLeScan(setting) { bean ->
      // Giữ lại bean gốc để startBlePairing dựng BleActivatorBean(scanBean).
      bean?.uuid?.let { scannedBle[it] = bean }
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
    // Dựng BleActivatorBean từ ScanDeviceBean đã cache lúc scan (research §5, dòng 144-150).
    // ⚠️ Field BleActivatorBean (ngoài homeId) cần verify trên SDK 7.5.6 ở lần build đầu;
    //    chỉ set homeId vì constructor đã copy productId/uuid/address/deviceType từ scan bean.
    val scan = scannedBle[uuid]
    if (scan == null) {
      promise.reject(
        "ble_scan_required",
        "Chưa có kết quả scan cho uuid=$uuid — gọi startBleScan() trước startBlePairing().",
      )
      return
    }
    val bean = BleActivatorBean(scan).apply { this.homeId = homeId.toLong() }
    ThingHomeSdk.getActivator().newBleActivator().startActivator(
      bean,
      object : IBleActivatorListener {
        override fun onSuccess(deviceBean: DeviceBean?) = promise.resolve(deviceToMap(deviceBean))
        override fun onFailure(code: Int, msg: String?, handle: Any?) =
          promise.reject(code.toString(), msg)
      },
    )
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // ---------- helpers ----------
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
