package com.jimmyvu.turbotuya.pairing

import com.jimmyvu.turbotuya.NativeTuyaPairingSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.ble.api.BleScanResponse
import com.thingclips.smart.android.ble.api.LeScanSetting
import com.thingclips.smart.android.ble.api.ScanDeviceBean
import com.thingclips.smart.android.ble.api.ScanType
import com.thingclips.smart.android.hardware.bean.HgwBean
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.api.IGwSearchListener
import com.thingclips.smart.home.sdk.api.IThingGwSearcher
import com.thingclips.smart.sdk.api.IBleActivatorListener
import com.thingclips.smart.sdk.api.IThingActivator
import com.thingclips.smart.sdk.api.IThingActivatorGetToken
import com.thingclips.smart.sdk.api.IThingDataCallback
import com.thingclips.smart.sdk.api.IThingSmartActivatorListener
import com.thingclips.smart.sdk.api.IMultiModeActivatorListener
import com.thingclips.smart.home.sdk.builder.ActivatorBuilder
import com.thingclips.smart.home.sdk.builder.ThingGwActivatorBuilder
import com.thingclips.smart.home.sdk.builder.ThingGwSubDevActivatorBuilder
import com.thingclips.smart.home.sdk.builder.ThingQRCodeActivatorBuilder
import com.thingclips.smart.sdk.bean.BleActivatorBean
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.bean.MultiModeActivatorBean
import com.thingclips.smart.sdk.bean.QrScanBean
import com.thingclips.smart.sdk.enums.ActivatorModelEnum
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

// TuyaPairing - ghép nối Wi-Fi (EZ/AP) + BLE. Phát event onPairingProgress / onBleScan.
//
// LỖI: mọi reject đi qua TuyaReject → shape { code, message, domain } khớp src/errors.ts.
// `code` LUÔN là mã Tuya thật (onError/onFailure trả về); literal chỉ dùng khi SDK không cho mã nào.
// Xem dev-workflow/m1-fix-wifi-pairing/.
class TuyaPairingModule(reactContext: ReactApplicationContext) :
  NativeTuyaPairingSpec(reactContext) {

  private val ctx = reactContext
  private var wifiActivator: IThingActivator? = null
  // Cache ScanDeviceBean theo uuid để dựng BleActivatorBean lúc pairing (BLE pairing cần bean gốc).
  private val scannedBle = mutableMapOf<String, ScanDeviceBean>()

  // ---- Pairing nâng cao: mọi state dưới đây CHỈ đụng trên main thread (entry point post sang `main`). ----
  private val main = Handler(Looper.getMainLooper())
  // Sub-device (void, kết quả qua event) - slot riêng để không đá phiên gateway/QR/wired đang chạy.
  private var subDevActivator: IThingActivator? = null
  // Phiên gateway / QR / wired đang chờ promise (1 phiên tại 1 thời điểm; phiên mới huỷ phiên cũ).
  private var advFlow: AdvFlow? = null

  private class AdvFlow(val promise: Promise, val what: String) {
    val settled = AtomicBoolean(false)
    var activator: IThingActivator? = null
    var searcher: IThingGwSearcher? = null
    var timeout: Runnable? = null
  }

  companion object {
    const val NAME = NativeTuyaPairingSpec.NAME
    private const val EVT_PAIRING = "onPairingProgress"
    private const val EVT_BLE = "onBleScan"
    // Mặc định của SDK cho mọi builder nâng cao (docs: "Default value: 100. Unit: seconds").
    private const val DEFAULT_ADV_TIMEOUT_SEC = 100L
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
          TuyaReject.reject(promise, code ?: "token_error", error ?: "Không lấy được pairing token.")
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

  // Auto-token: tự getActivatorToken(homeId) rồi chạy EZ/AP - khỏi quản lý token thủ công.
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
          TuyaReject.reject(promise, code ?: "token_error", error ?: "Không lấy được pairing token.")
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
      if (mode.equals("AP", true)) ActivatorModelEnum.THING_AP else ActivatorModelEnum.THING_EZ
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
        // `code` = mã Tuya thật (vd "-55" token hết hạn). Literal chỉ dùng khi SDK trả null.
        override fun onError(code: String?, msg: String?) =
          TuyaReject.reject(promise, code ?: "pairing_error", msg ?: "Ghép nối Wi-Fi thất bại.")
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
    // object : BleScanResponse (verbatim note) thay trailing-lambda - tránh phụ thuộc SAM-conversion.
    ThingHomeSdk.getBleOperator().startLeScan(setting, object : BleScanResponse {
      override fun onResult(bean: ScanDeviceBean?) {
        // Giữ lại bean gốc để startBlePairing dựng BleActivatorBean(scanBean).
        bean?.uuid?.let { scannedBle[it] = bean }
        // configType (ScanDeviceBean.getConfigType, xác minh bằng javap trên thingsmart 7.5.6):
        //   config_type_wifi / config_type_wifi_p = combo (cần Wi-Fi); config_type_single/beacon/... = BLE thuần.
        // → isCombo để JS route (B8/B9). iOS dùng bleType enum; Android dùng chuỗi configType.
        val configType = bean?.configType ?: ""
        val isCombo = configType.contains("wifi", ignoreCase = true)
        val m = Arguments.createMap()
        m.putString("id", bean?.id ?: "")
        m.putString("name", bean?.name ?: "")
        m.putString("productId", bean?.productId ?: "")
        m.putString("uuid", bean?.uuid ?: "")
        m.putString("mac", bean?.mac ?: "")
        m.putString("address", bean?.address ?: "")
        m.putDouble("deviceType", (bean?.deviceType ?: 0).toDouble())
        m.putString("configType", configType)
        m.putString("providerName", bean?.providerName ?: "")
        m.putBoolean("isCombo", isCombo)
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
      TuyaReject.reject(
        promise,
        "ble_scan_required",
        "Chưa có kết quả scan cho uuid=$uuid - gọi startBleScan() trước startBlePairing().",
      )
      return
    }
    val bean = BleActivatorBean(scan).apply { this.homeId = homeId.toLong() }
    ThingHomeSdk.getActivator().newBleActivator().startActivator(
      bean,
      object : IBleActivatorListener {
        override fun onSuccess(deviceBean: DeviceBean?) = promise.resolve(deviceToMap(deviceBean))
        override fun onFailure(code: Int, msg: String?, handle: Any?) =
          TuyaReject.reject(promise, code.toString(), msg ?: "Ghép nối BLE thất bại.")
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
      TuyaReject.reject(
        promise,
        "ble_scan_required",
        "Chưa có kết quả scan cho uuid=$uuid - gọi startBleScan() trước startBleWifiPairing().",
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
                TuyaReject.reject(promise, code.toString(), msg ?: "Ghép nối BLE+Wi-Fi thất bại.")
            },
          )
        }
        override fun onFailure(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "token_error", error ?: "Không lấy được pairing token.")
      },
    )
  }

  override fun stopBleWifiPairing(uuid: String) {
    // Verbatim note §3: stopActivator(uuid) gọi trên newMultiModeActivator().
    ThingHomeSdk.getActivator().newMultiModeActivator().stopActivator(uuid)
  }

  // ---------- P3: pairing nâng cao (builder cổ điển của ThingHomeSdk.getActivatorInstance()) ----------
  // SDK 7.5.6 KHÔNG có ActivatorService hợp nhất (đã dò class index) → dùng API builder, verify bằng javap:
  //   sub-device: newGwSubDevActivator(ThingGwSubDevActivatorBuilder) · gateway/wired: newGwActivator(ThingGwActivatorBuilder)
  //   QR: deviceQrCodeParse(url) → uuid → newQRCodeDevActivator(ThingQRCodeActivatorBuilder). Timeout builder = GIÂY.
  // Step trung gian: onStep(step, data) đẩy NGUYÊN VĂN lên onPairingProgress (như Wi-Fi) - vd device_find/device_bind_success.

  // Sub-device (Zigbee/BLE qua gateway): gateway phải online cloud, KHÔNG cần token. onActiveSuccess gọi cho TỪNG
  // sub-device → onPairingProgress(step='subdevice_found', dataJson=devId); lỗi → step='subdevice_error' + errorCode.
  override fun startSubDevicePairing(gatewayDevId: String, timeoutSec: Double) {
    main.post {
      stopSubDevice()
      val builder = ThingGwSubDevActivatorBuilder()
        .setDevId(gatewayDevId)
        .setTimeOut(advTimeout(timeoutSec))
        .setListener(object : IThingSmartActivatorListener {
          override fun onActiveSuccess(devResp: DeviceBean?) {
            val id = devResp?.devId ?: ""
            emitProgress("subdevice_found", id, devId = id)
          }
          override fun onError(code: String?, msg: String?) =
            emitProgress(
              "subdevice_error",
              errorCode = code ?: "subdevice_error",
              errorMessage = msg ?: "Sub-device pairing failed.",
            )
          override fun onStep(step: String?, data: Any?) = emitProgress(step ?: "", data?.toString() ?: "")
        })
      // Lỗi đồng bộ của SDK (vd chưa init) → báo qua event thay vì crash main thread.
      try {
        subDevActivator = ThingHomeSdk.getActivatorInstance().newGwSubDevActivator(builder).also { it.start() }
      } catch (e: Throwable) {
        stopSubDevice()
        emitProgress("subdevice_error", errorCode = "subdevice_start_error", errorMessage = e.message ?: e.toString())
      }
    }
  }

  override fun stopSubDevicePairing(gatewayDevId: String) {
    main.post { stopSubDevice() }
  }

  // Gateway (wired/LAN) đã biết gwId: Android cần HgwBean (ip... do gateway broadcast trên LAN) → dò gwId bằng
  // searcher (thiết bị đã thấy trước đó được replay ngay), thấy thì activate bằng token. productId chỉ để chẩn đoán.
  override fun startGatewayPairing(
    gatewayDevId: String,
    productId: String,
    token: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    if (gatewayDevId.isBlank() || token.isBlank()) {
      TuyaReject.reject(promise, "invalid_argument", "gatewayDevId and token are required.")
      return
    }
    main.post {
      val flow = beginAdv(promise, "gateway")
      val t = advTimeout(timeoutSec)
      val timeout = Runnable {
        settleAdv(flow) {
          TuyaReject.reject(
            promise,
            "gateway_not_found",
            "Gateway $gatewayDevId was not found on the LAN within ${t}s (phone and gateway must share the network; gateway in pairing mode).",
          )
        }
      }
      flow.timeout = timeout
      main.postDelayed(timeout, t * 1000)
      try {
        val searcher = ThingHomeSdk.getActivatorInstance().newThingGwActivator().newSearcher()
        flow.searcher = searcher
        searcher.registerGwSearchListener(object : IGwSearchListener {
          override fun onDevFind(hgw: HgwBean?) {
            if (hgw == null || hgw.gwId != gatewayDevId) return
            main.post { activateFoundGateway(flow, hgw, productId, token, t) }
          }
        })
      } catch (e: Throwable) {
        settleAdv(flow) { TuyaReject.reject(promise, "pairing_start_error", e.message ?: e.toString()) }
      }
    }
  }

  private fun activateFoundGateway(flow: AdvFlow, hgw: HgwBean, productId: String, token: String, t: Long) {
    if (flow.settled.get() || flow.activator != null) return
    flow.timeout?.let { main.removeCallbacks(it) }
    flow.timeout = null
    runCatching { flow.searcher?.unRegisterGwSearchListener() }
    flow.searcher = null
    val info = JSONObject()
      .put("gwId", hgw.gwId ?: "")
      .put("productId", hgw.productKey ?: "")
      .put("expectedProductId", productId)
      .put("ip", hgw.ip ?: "")
    emitProgress("gateway_found", info.toString(), devId = hgw.gwId)
    startAdvActivator(flow) {
      ThingHomeSdk.getActivatorInstance().newGwActivator(
        ThingGwActivatorBuilder()
          .setToken(token)
          .setTimeOut(t)
          .setContext(ctx)
          .setHgwBean(hgw)
          .setListener(advListener(flow)),
      )
    }
  }

  // QR in trên thiết bị (thiết bị đã online internet, vd 4G/cellular): parse QR → uuid → activate theo homeId.
  // assetId: chỉ API hợp nhất (không có trong 7.5.6) mới dùng → bỏ qua; nhà đích = homeId.
  override fun startQrPairing(
    homeId: Double,
    assetId: String,
    code: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    if (code.isBlank()) {
      TuyaReject.reject(promise, "invalid_argument", "QR code content is empty.")
      return
    }
    main.post {
      val flow = beginAdv(promise, "qr")
      val t = advTimeout(timeoutSec)
      val parseCallback = object : IThingDataCallback<QrScanBean> {
        override fun onSuccess(result: QrScanBean?) {
          main.post {
            if (flow.settled.get()) return@post
            val uuid = qrUuidOf(result?.actionData)
            if (uuid.isNullOrEmpty()) {
              settleAdv(flow) {
                TuyaReject.reject(
                  promise,
                  "qr_uuid_missing",
                  "QR parsed (actionName=${result?.actionName}) but actionData has no uuid: ${result?.actionData}",
                )
              }
              return@post
            }
            val info = JSONObject().put("actionName", result?.actionName ?: "").put("uuid", uuid)
            emitProgress("qr_parsed", info.toString())
            startAdvActivator(flow) {
              ThingHomeSdk.getActivatorInstance().newQRCodeDevActivator(
                ThingQRCodeActivatorBuilder()
                  .setUuid(uuid)
                  .setHomeId(homeId.toLong())
                  .setContext(ctx)
                  .setTimeOut(t)
                  .setListener(advListener(flow)),
              )
            }
          }
        }
        // Mã thật của SDK, vd "QR_PROTOCOL_NOT_RECOGNIZED" (QR không phải của Tuya).
        override fun onError(errorCode: String?, errorMsg: String?) {
          main.post {
            settleAdv(flow) {
              TuyaReject.reject(promise, errorCode ?: "qr_parse_error", errorMsg ?: "deviceQrCodeParse failed.")
            }
          }
        }
      }
      try {
        ThingHomeSdk.getActivatorInstance().deviceQrCodeParse(code, parseCallback)
      } catch (e: Throwable) {
        settleAdv(flow) { TuyaReject.reject(promise, "pairing_start_error", e.message ?: e.toString()) }
      }
    }
  }

  // Wired: KHÔNG truyền HgwBean → SDK tự dò thiết bị nối dây trên LAN rồi activate bằng token (docs "without device
  // discovery"). Điện thoại + thiết bị phải cùng mạng. homeId không cần (token đã gắn nhà).
  override fun startWiredPairing(
    homeId: Double,
    token: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    if (token.isBlank()) {
      TuyaReject.reject(promise, "invalid_argument", "token is required (getPairingToken(homeId)).")
      return
    }
    main.post {
      val flow = beginAdv(promise, "wired")
      startAdvActivator(flow) {
        ThingHomeSdk.getActivatorInstance().newGwActivator(
          ThingGwActivatorBuilder()
            .setToken(token)
            .setTimeOut(advTimeout(timeoutSec))
            .setContext(ctx)
            .setListener(advListener(flow)),
        )
      }
    }
  }

  override fun destroyActivator() {
    // Dọn wifi + scan (như cũ) + activator nâng cao (phiên đang chờ bị reject 'pairing_cancelled').
    runCatching { wifiActivator?.stop(); wifiActivator?.onDestroy() }
    wifiActivator = null
    runCatching { ThingHomeSdk.getBleOperator().stopLeScan() }
    main.post {
      cancelAdv("destroyActivator() was called.")
      stopSubDevice()
    }
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
    // RN instance đang huỷ → chỉ dọn activator, không reject promise của JS đã chết.
    main.post {
      advFlow?.let { settleAdv(it) {} }
      stopSubDevice()
    }
  }

  // ---------- helpers: pairing nâng cao (gọi trên main thread) ----------
  private fun advTimeout(timeoutSec: Double): Long =
    if (timeoutSec > 0) timeoutSec.toLong() else DEFAULT_ADV_TIMEOUT_SEC

  // Event onPairingProgress cùng shape với iOS ({step, dataJson, devId?, errorCode?, errorMessage?}).
  // runCatching: callback SDK muộn sau khi RN instance huỷ thì bỏ qua thay vì crash.
  private fun emitProgress(
    step: String,
    dataJson: String = "",
    devId: String? = null,
    errorCode: String? = null,
    errorMessage: String? = null,
  ) {
    val m = Arguments.createMap()
    m.putString("step", step)
    m.putString("dataJson", dataJson)
    if (!devId.isNullOrEmpty()) m.putString("devId", devId)
    if (errorCode != null) m.putString("errorCode", errorCode)
    if (errorMessage != null) m.putString("errorMessage", errorMessage)
    runCatching { emit(EVT_PAIRING, m) }
  }

  private fun stopSubDevice() {
    val act = subDevActivator ?: return
    subDevActivator = null
    runCatching { act.stop(); act.onDestroy() }
  }

  // Mở phiên mới cho gateway/QR/wired; phiên cũ còn chờ → reject 'pairing_cancelled'.
  private fun beginAdv(promise: Promise, what: String): AdvFlow {
    cancelAdv("Superseded by a new $what pairing request.")
    return AdvFlow(promise, what).also { advFlow = it }
  }

  // Tạo + start activator cho phiên; nếu phiên đã bị huỷ trong lúc đó thì dọn ngay (không để activator mồ côi).
  // Lỗi đồng bộ của SDK (vd chưa init) → reject 'pairing_start_error' thay vì crash main thread.
  private fun startAdvActivator(flow: AdvFlow, create: () -> IThingActivator) {
    if (flow.settled.get()) return
    val act = try {
      create().also {
        flow.activator = it
        it.start()
      }
    } catch (e: Throwable) {
      settleAdv(flow) { TuyaReject.reject(flow.promise, "pairing_start_error", e.message ?: e.toString()) }
      return
    }
    if (flow.settled.get()) {
      flow.activator = null
      runCatching { act.stop(); act.onDestroy() }
    }
  }

  // Kết thúc phiên đúng 1 lần: gỡ timeout/searcher, stop+onDestroy activator SAU callback hiện tại
  // (tránh huỷ activator ngay trong listener của chính nó), rồi resolve/reject.
  private fun settleAdv(flow: AdvFlow, finish: () -> Unit) {
    if (!flow.settled.compareAndSet(false, true)) return
    flow.timeout?.let { main.removeCallbacks(it) }
    flow.timeout = null
    val searcher = flow.searcher
    val act = flow.activator
    flow.searcher = null
    flow.activator = null
    if (advFlow === flow) advFlow = null
    main.post {
      runCatching { searcher?.unRegisterGwSearchListener() }
      runCatching { act?.stop(); act?.onDestroy() }
    }
    finish()
  }

  private fun cancelAdv(reason: String) {
    val flow = advFlow ?: return
    settleAdv(flow) { TuyaReject.reject(flow.promise, "pairing_cancelled", reason) }
  }

  // Kết quả cuối của gateway/QR/wired → promise (DeviceResult); onError mang mã Tuya thật. Step → event nguyên văn.
  private fun advListener(flow: AdvFlow) = object : IThingSmartActivatorListener {
    override fun onActiveSuccess(devResp: DeviceBean?) {
      main.post { settleAdv(flow) { flow.promise.resolve(deviceToMap(devResp)) } }
    }
    override fun onError(code: String?, msg: String?) {
      main.post {
        settleAdv(flow) {
          TuyaReject.reject(flow.promise, code ?: "${flow.what}_pairing_error", msg ?: "Pairing (${flow.what}) failed.")
        }
      }
    }
    override fun onStep(step: String?, data: Any?) {
      if (flow.settled.get()) return
      emitProgress(step ?: "", data?.toString() ?: "")
    }
  }

  // QrScanBean.actionData là Object: thường là fastjson JSONObject (= Map) chứa "uuid"; dự phòng chuỗi JSON.
  private fun qrUuidOf(actionData: Any?): String? {
    val uuid = when (actionData) {
      null -> null
      is Map<*, *> -> actionData["uuid"]?.toString()
      is JSONObject -> actionData.optString("uuid")
      else -> runCatching { JSONObject(actionData.toString()).optString("uuid") }.getOrNull()
    }
    return uuid?.takeIf { it.isNotBlank() }
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
