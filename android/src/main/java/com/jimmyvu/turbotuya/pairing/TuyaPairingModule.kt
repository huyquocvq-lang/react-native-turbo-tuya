package com.jimmyvu.turbotuya.pairing

import com.jimmyvu.turbotuya.NativeTuyaPairingSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.ble.api.BleScanResponse
import com.thingclips.smart.android.ble.api.LeScanSetting
import com.thingclips.smart.android.ble.api.ScanDeviceBean
import com.thingclips.smart.android.ble.api.ScanType
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IBleActivatorListener
import com.thingclips.smart.sdk.api.IThingActivator
import com.thingclips.smart.sdk.api.IThingActivatorGetToken
import com.thingclips.smart.sdk.api.IThingSmartActivatorListener
import com.thingclips.smart.sdk.api.IMultiModeActivatorListener
import com.thingclips.smart.sdk.bean.ActivatorBuilder
import com.thingclips.smart.sdk.bean.BleActivatorBean
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.bean.MultiModeActivatorBean
import com.thingclips.smart.sdk.bean.PauseStateData
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
  ) = doWifiPairing(mode, ssid, password, token, timeoutSec, promise)

  // Auto-token: tự getActivatorToken(homeId) rồi chạy EZ/AP — khỏi quản lý token thủ công.
  override fun startWifiPairingAuto(
    homeId: Double,
    mode: String,
    ssid: String,
    password: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    ThingHomeSdk.getActivatorInstance().getActivatorToken(
      homeId.toLong(),
      object : IThingActivatorGetToken {
        override fun onSuccess(token: String?) =
          doWifiPairing(mode, ssid, password, token ?: "", timeoutSec, promise)
        override fun onFailure(code: String?, error: String?) =
          promise.reject(code ?: "token_error", error)
      },
    )
  }

  private fun doWifiPairing(
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
    // object : BleScanResponse (verbatim note) thay trailing-lambda — tránh phụ thuộc SAM-conversion.
    ThingHomeSdk.getBleOperator().startLeScan(setting, object : BleScanResponse {
      override fun onResult(bean: ScanDeviceBean?) {
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
    })
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

  // ---------- Combo / dual-mode (BLE + Wi-Fi) ----------
  // Auto-token: tự getActivatorToken(homeId) rồi startActivator(MultiModeActivatorBean) dựng từ scan bean đã cache.
  override fun startBleWifiPairing(
    homeId: Double,
    uuid: String,
    ssid: String,
    password: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    val scan = scannedBle[uuid]
    if (scan == null) {
      promise.reject(
        "ble_scan_required",
        "Chưa có kết quả scan cho uuid=$uuid — gọi startBleScan() trước startBleWifiPairing().",
      )
      return
    }
    ThingHomeSdk.getActivatorInstance().getActivatorToken(
      homeId.toLong(),
      object : IThingActivatorGetToken {
        override fun onSuccess(token: String?) {
          // MultiModeActivatorBean copy uuid/deviceType từ scan bean; set thêm ssid/pwd/token/homeId (verbatim note §3).
          val bean = MultiModeActivatorBean(scan).apply {
            this.uuid = uuid
            this.deviceType = scan.deviceType
            this.ssid = ssid
            this.pwd = password
            this.token = token ?: ""
            this.homeId = homeId.toLong()
            this.timeout = timeoutSec.toLong() * 1000
          }
          ThingHomeSdk.getActivator().newMultiModeActivator().startActivator(
            bean,
            object : IMultiModeActivatorListener {
              override fun onSuccess(deviceBean: DeviceBean?) = promise.resolve(deviceToMap(deviceBean))
              override fun onFailure(code: Int, msg: String?, handle: Any?) =
                promise.reject(code.toString(), msg)
              override fun onActivatorStatePauseCallback(stateData: PauseStateData?) {
                // Stage trung gian: 0 activation,1 delegation,2 network,3 cloud activation (PauseStateData getters cần verify).
                val m = Arguments.createMap()
                m.putString("step", "combo_stage")
                m.putString("dataJson", stateData?.toString() ?: "")
                emit(EVT_PAIRING, m)
              }
            },
          )
        }
        override fun onFailure(code: String?, error: String?) =
          promise.reject(code ?: "token_error", error)
      },
    )
  }

  override fun stopBleWifiPairing(uuid: String) {
    // Verbatim note §3: stopActivator(uuid) gọi trên newMultiModeActivator().
    ThingHomeSdk.getActivator().newMultiModeActivator().stopActivator(uuid)
  }

  // ---------- P3: pairing nâng cao (unified ActivatorService — package CHƯA verbatim) ----------
  // SKELETON có chủ đích (như B7 Scene): API hợp nhất ActivatorService/ActivatorMode/Zigbee|QRScanActivator(+Params)/
  // IActivatorListener/IDevice CHƯA lấy verbatim package + note cảnh báo KHÔNG trộn 2 thế hệ → wire trên SDK thật.
  private fun todoPairing(promise: Promise, what: String, intended: String) {
    promise.reject("not_implemented", "$what chưa wire (unified ActivatorService chưa verbatim). Intended: $intended")
  }

  override fun startSubDevicePairing(gatewayDevId: String, timeoutSec: Double) {
    // intended: ZigbeeActivator=ActivatorService.activator(ActivatorMode.Zigbee);
    //   setParams(ZigbeeActivatorParams.Builder().setGwDeviceId(gatewayDevId).setTimeout(ms).build());
    //   setListener(IActivatorListener{onSuccess(IDevice)→emit onPairingProgress step='subdevice_found' devId; onError}); start().
    val m = Arguments.createMap()
    m.putString("step", "subdevice_error")
    m.putString("dataJson", "not_implemented (unified ActivatorService chưa wire)")
    emit(EVT_PAIRING, m)
  }

  override fun stopSubDevicePairing(gatewayDevId: String) {
    // intended: zigbeeActivator.stop() (giữ tham chiếu khi wire thật).
  }

  override fun startGatewayPairing(
    gatewayDevId: String,
    productId: String,
    token: String,
    timeoutSec: Double,
    promise: Promise,
  ) = todoPairing(
    promise, "startGatewayPairing",
    "Android activator gateway/token; iOS activeGatewayDeviceWithGwId:productId:token:timeout:",
  )

  override fun startQrPairing(
    homeId: Double,
    assetId: String,
    code: String,
    timeoutSec: Double,
    promise: Promise,
  ) = todoPairing(
    promise, "startQrPairing",
    "QRScanActivator=ActivatorService.activator(ActivatorMode.QRScan)+QRScanActivatorParams.Builder().setAssetId().setCode().build()",
  )

  override fun startWiredPairing(
    homeId: Double,
    token: String,
    timeoutSec: Double,
    promise: Promise,
  ) = todoPairing(
    promise, "startWiredPairing",
    "Android search+token (ActivatorMode.Auto?); iOS startConfigWiFiWithToken:timeout:",
  )

  override fun destroyActivator() {
    // intended: activator nâng cao .destroy()/.onDestroy() (giữ tham chiếu khi wire thật). Hiện dọn wifi+scan.
    runCatching { wifiActivator?.stop(); wifiActivator?.onDestroy() }
    wifiActivator = null
    runCatching { ThingHomeSdk.getBleOperator().stopLeScan() }
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // Dọn activator + scan khi RN instance huỷ (reload/unmount) → tránh leak scan nền + listener.
  override fun invalidate() {
    super.invalidate()
    runCatching { wifiActivator?.stop(); wifiActivator?.onDestroy() }
    wifiActivator = null
    runCatching { ThingHomeSdk.getBleOperator().stopLeScan() }
    scannedBle.clear()
  }

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
