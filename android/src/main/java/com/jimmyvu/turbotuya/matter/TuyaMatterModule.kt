package com.jimmyvu.turbotuya.matter

// TuyaMatter (Android) - WIRED trên SDK 7.5.6 (thingsmart-matterlib-api), API riêng IMatterActivator.
// Đã verify bằng javap (KHÔNG theo trí nhớ):
//   ThingHomeSdk.getMatterDevActivatorInstance(): IMatterActivator (null nếu plugin Matter vắng; SDK tạo
//     instance MỚI mỗi lần gọi → GIỮ 1 instance, vì cancelActivator/continueCommissioningDevice phải gọi
//     đúng instance đang commission).
//   parseSetupCode(String): SetupPayload? (null = code sai) · connectDevice(ConnectDeviceBuilder) ·
//   commissionDevice(CommissioningParameters, MatterActivatorCallback) · continueCommissioningDevice(long,long,bool)
//   ThingHomeSdk.getDiscoveryActivatorInstance(): IMatterDiscoveryActivator (cũng new mỗi lần → giữ lại).
// Timeout của ConnectDeviceBuilder.setTimeout / CommissioningParameters.timeOut là MILLISECOND
//   (bytecode: CountdownUtil.startCountdown(ms), còn tự đổi 180 → 180000 cho ai lỡ truyền giây).
// Runtime: matterlib AAR đã kèm CHIPController.jar + libCHIPController.so (arm64-v8a/armeabi-v7a) → không
//   cần thêm dependency. App phải xin quyền BLE/location (+ NEARBY_WIFI_DEVICES Android 13+) trước khi gọi.
// Luồng STATEFUL: parseSetupCode → connectDevice → commissionDevice. Native GIỮ SetupPayload + ConnectResult.

import com.jimmyvu.turbotuya.NativeTuyaMatterSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.sdk.matter.activator.IDynamicDiscoveryListener
import com.thingclips.sdk.matter.activator.IMatterActivator
import com.thingclips.sdk.matter.activator.IMatterDiscoveryActivator
import com.thingclips.sdk.matter.activator.SetupPayload
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IThingConnectDeviceCallback
import com.thingclips.smart.sdk.api.MatterActivatorCallback
import com.thingclips.smart.sdk.bean.CommissioningParameters
import com.thingclips.smart.sdk.bean.ConnectDeviceBuilder
import com.thingclips.smart.sdk.bean.ConnectResult
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.bean.ThingMatterDiscovery
import com.thingclips.smart.sdk.enums.MatterDeviceTypeEnum
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

// TuyaMatter - pairing Matter (API riêng). Phát event onMatterDeviceFound/onMatterAttestation/onMatterError.
class TuyaMatterModule(reactContext: ReactApplicationContext) :
  NativeTuyaMatterSpec(reactContext) {

  private val ctx = reactContext

  // State giữ giữa các call (KHÔNG round-trip object native qua JS).
  @Volatile private var activator: IMatterActivator? = null
  @Volatile private var discovery: IMatterDiscoveryActivator? = null
  @Volatile private var setupPayload: SetupPayload? = null
  @Volatile private var connectResult: ConnectResult? = null
  @Volatile private var pendingConnect: Once? = null
  @Volatile private var pendingCommission: Once? = null
  // Con trỏ native từ onDeviceAttestationFailed → dùng lại cho continueCommissioningDevice.
  @Volatile private var attestPending = false
  @Volatile private var attestCtrlPtr = 0L
  @Volatile private var attestDevPtr = 0L

  companion object {
    const val NAME = NativeTuyaMatterSpec.NAME
    private const val EVT_FOUND = "onMatterDeviceFound"
    private const val EVT_ATTEST = "onMatterAttestation"
    private const val EVT_ERROR = "onMatterError"
    private const val DEFAULT_TIMEOUT_MS = 180_000L
  }

  // Promise chỉ settle 1 lần: SDK có thể bắn onError sau onConnected / timeout / cancel.
  private class Once(private val promise: Promise) {
    private val done = AtomicBoolean(false)
    fun resolve(value: Any?) {
      if (done.compareAndSet(false, true)) promise.resolve(value)
    }
    fun reject(code: String?, message: String?) {
      if (done.compareAndSet(false, true)) TuyaReject.reject(promise, code, message)
    }
  }

  private fun emit(event: String, params: WritableMap?) {
    if (!ctx.hasActiveReactInstance()) return
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit(event, params)
  }

  private fun emitError(code: String?, message: String?) {
    val m = Arguments.createMap()
    m.putString("code", code ?: "matter_error")
    m.putString("message", message ?: "")
    emit(EVT_ERROR, m)
  }

  private fun emitFound(data: JSONObject) {
    val m = Arguments.createMap()
    m.putString("dataJson", data.toString())
    emit(EVT_FOUND, m)
  }

  private fun matterActivator(): IMatterActivator? =
    activator ?: ThingHomeSdk.getMatterDevActivatorInstance()?.also { activator = it }

  private fun rejectUnavailable(promise: Promise) = TuyaReject.reject(
    promise,
    "matter_unavailable",
    "Tuya Matter plugin is not available: ThingHomeSdk.getMatterDevActivatorInstance() returned null.",
  )

  private fun toMs(timeoutSec: Double): Long =
    if (timeoutSec > 0) (timeoutSec * 1000).toLong() else DEFAULT_TIMEOUT_MS

  private fun clearAttestation() {
    attestPending = false
    attestCtrlPtr = 0L
    attestDevPtr = 0L
  }

  // ---------- 1) Parse "MT:..." / manual code → payload (giữ SetupPayload) ----------
  override fun parseSetupCode(code: String, promise: Promise) {
    val m = matterActivator() ?: return rejectUnavailable(promise)
    val p = try {
      m.parseSetupCode(code.trim())
    } catch (e: Throwable) {
      return TuyaReject.reject(promise, "matter_invalid_setup_code", e.message ?: e.toString())
    }
    if (p == null) {
      TuyaReject.reject(
        promise,
        "matter_invalid_setup_code",
        "Invalid Matter setup code: expected a QR payload ('MT:...') or an 11/21-digit manual pairing code.",
      )
      return
    }
    setupPayload = p
    connectResult = null
    clearAttestation()
    promise.resolve(payloadToMap(p))
  }

  // ---------- 2) Connect (BLE/mDNS) bằng payload đã giữ → ConnectResult (giữ lại) ----------
  override fun connectDevice(homeId: Double, timeoutSec: Double, promise: Promise) {
    val m = matterActivator() ?: return rejectUnavailable(promise)
    val payload = setupPayload
      ?: return TuyaReject.reject(promise, "matter_setup_code_required", "Call parseSetupCode first.")
    pendingConnect?.reject("matter_superseded", "connectDevice was called again before the previous call finished.")
    val once = Once(promise)
    pendingConnect = once
    connectResult = null
    val builder = ConnectDeviceBuilder()
      .setSetupPayload(payload)
      .setSpaceId(homeId.toLong())
      .setTimeout(toMs(timeoutSec))
      .setConnectCallback(object : IThingConnectDeviceCallback {
        // Đã tìm thấy thiết bị (BLE/mDNS) - JS dùng deviceType để biết có cần hỏi Wi-Fi không (wifi vs thread).
        override fun onFound(isThingMatter: Boolean, deviceType: MatterDeviceTypeEnum?) {
          emitFound(
            JSONObject()
              .put("source", "connect")
              .put("isThingMatter", isThingMatter)
              .put("deviceType", typeName(deviceType)),
          )
        }

        override fun onConnected(result: ConnectResult?) {
          if (pendingConnect === once) pendingConnect = null
          if (result == null) {
            once.reject("matter_connect_error", "Matter connect succeeded without a ConnectResult.")
            return
          }
          connectResult = result
          once.resolve(connectResultToMap(result))
        }

        override fun onError(code: String?, msg: String?) {
          if (pendingConnect === once) pendingConnect = null
          once.reject(code ?: "matter_connect_error", msg ?: "Matter connect failed.")
        }
      })
    try {
      m.connectDevice(builder)
    } catch (e: Throwable) {
      if (pendingConnect === once) pendingConnect = null
      once.reject("matter_connect_error", e.message ?: e.toString())
    }
  }

  // ---------- 3) Commission bằng payload + ConnectResult đã giữ ----------
  // Thread: gwId lấy từ ConnectResult.gwId (SDK tự fallback khi params.gwId rỗng - đã thấy trong bytecode).
  override fun commissionDevice(
    homeId: Double,
    token: String,
    ssid: String,
    password: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    val m = matterActivator() ?: return rejectUnavailable(promise)
    val payload = setupPayload
      ?: return TuyaReject.reject(promise, "matter_setup_code_required", "Call parseSetupCode first.")
    val cr = connectResult
      ?: return TuyaReject.reject(promise, "matter_connect_required", "Call connectDevice first (no ConnectResult held).")
    pendingCommission?.reject("matter_superseded", "commissionDevice was called again before the previous call finished.")
    val once = Once(promise)
    pendingCommission = once
    clearAttestation()
    val params = CommissioningParameters.Builder()
      .setupPayload(payload)
      .connectDeviceResult(cr)
      .spaceId(homeId.toLong())
      .token(token)
      .ssid(ssid)
      .password(password)
      .timeOut(toMs(timeoutSec))
      .build()
    val callback = object : MatterActivatorCallback {
      override fun onActivatorSuccess(bean: DeviceBean?) {
        finishCommission(once)
        once.resolve(pairedToMap(bean))
      }

      override fun onError(code: String?, msg: String?) {
        finishCommission(once)
        once.reject(code ?: "matter_commission_error", msg ?: "Matter commissioning failed.")
      }

      // Thiết bị chưa cert → JS hỏi user rồi gọi continueCommissioning(ignore).
      override fun onDeviceAttestationFailed(ctrlPtr: Long, devPtr: Long, errorCode: Int) {
        attestCtrlPtr = ctrlPtr
        attestDevPtr = devPtr
        attestPending = true
        val e = Arguments.createMap()
        e.putInt("code", errorCode)
        emit(EVT_ATTEST, e)
      }
    }
    try {
      m.commissionDevice(params, callback)
    } catch (e: Throwable) {
      finishCommission(once)
      once.reject("matter_commission_error", e.message ?: e.toString())
    }
  }

  // ConnectResult chỉ dùng được 1 lần (phiên PASE kết thúc) → bỏ; giữ payload để JS connect lại không cần parse.
  private fun finishCommission(once: Once) {
    if (pendingCommission === once) pendingCommission = null
    connectResult = null
    clearAttestation()
  }

  // ---------- Auto-discovery (kết quả qua onMatterDeviceFound) ----------
  override fun startDiscovery() {
    val d = discovery ?: ThingHomeSdk.getDiscoveryActivatorInstance()?.also { discovery = it }
    if (d == null) {
      emitError("matter_unavailable", "Tuya Matter plugin is not available: getDiscoveryActivatorInstance() returned null.")
      return
    }
    try {
      d.startDiscovery(object : IDynamicDiscoveryListener {
        override fun onFound(device: ThingMatterDiscovery?) {
          if (device != null) emitFound(discoveryToJson(device))
        }

        override fun onError(code: String?, msg: String?) = emitError(code, msg)
      })
    } catch (e: Throwable) {
      emitError("matter_discovery_error", e.message ?: e.toString())
    }
  }

  override fun stopDiscovery() {
    runCatching { discovery?.stopDiscovery() }
  }

  // ---------- Attestation / cancel ----------
  override fun continueCommissioning(ignoreAttestationFailure: Boolean) {
    val m = activator
    if (m == null || !attestPending) {
      emitError("matter_no_attestation_pending", "continueCommissioning called without a pending onMatterAttestation.")
      return
    }
    val ctrl = attestCtrlPtr
    val dev = attestDevPtr
    clearAttestation()
    try {
      m.continueCommissioningDevice(ctrl, dev, ignoreAttestationFailure)
    } catch (e: Throwable) {
      emitError("matter_continue_error", e.message ?: e.toString())
    }
  }

  override fun cancelActivator() {
    runCatching { activator?.cancelActivator() }
    clearAttestation()
    connectResult = null
    pendingConnect?.reject("matter_cancelled", "Matter activation cancelled by cancelActivator().")
    pendingCommission?.reject("matter_cancelled", "Matter activation cancelled by cancelActivator().")
    pendingConnect = null
    pendingCommission = null
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // Dọn discovery + activator khi RN instance huỷ (reload/unmount).
  override fun invalidate() {
    super.invalidate()
    runCatching { discovery?.stopDiscovery(); discovery?.onDestroy() }
    discovery = null
    if (pendingConnect != null || pendingCommission != null) runCatching { activator?.cancelActivator() }
    pendingConnect = null
    pendingCommission = null
    activator = null
    setupPayload = null
    connectResult = null
    clearAttestation()
  }

  // ---------- helpers ----------
  private fun payloadToMap(p: SetupPayload): WritableMap {
    val m = Arguments.createMap()
    m.putInt("version", p.version)
    m.putInt("vendorId", p.vendorId)
    m.putInt("productId", p.productId)
    m.putDouble("setupPinCode", p.setupPinCode.toDouble())
    m.putInt("discriminator", p.discriminator?.value ?: 0)
    return m
  }

  // accessType: Android ConnectResult không có field này → suy từ isThingMatter (0 = Tuya, 1 = bên thứ 3).
  private fun connectResultToMap(r: ConnectResult): WritableMap {
    val m = Arguments.createMap()
    m.putString(
      "discoveryType",
      when (r.discoveryType) {
        ConnectResult.DiscoveryType.BLE -> "BLE"
        ConnectResult.DiscoveryType.MDNS -> "mDNS"
        else -> ""
      },
    )
    m.putString("ipAddress", r.ipAddress ?: "")
    m.putInt("port", r.port)
    m.putString("thingProductId", r.thingProductId ?: "")
    m.putInt("accessType", if (r.isThingMatter) 0 else 1)
    m.putBoolean("isThingMatter", r.isThingMatter)
    m.putDouble("nodeId", r.nodeId.toDouble())
    m.putString("gwId", r.gwId ?: "")
    return m
  }

  private fun pairedToMap(bean: DeviceBean?): WritableMap {
    val m = Arguments.createMap()
    m.putString("devId", bean?.devId ?: "")
    m.putString("name", bean?.name ?: "")
    m.putString("productId", bean?.productId ?: "")
    return m
  }

  private fun discoveryToJson(d: ThingMatterDiscovery): JSONObject {
    val p = d.payload
    return JSONObject()
      .put("source", "discovery")
      .put("name", d.productName ?: "")
      .put("iconUrl", d.iconUrlStr ?: "")
      .put("deviceType", typeName(d.deviceType))
      .put("isThingMatter", d.isThingMatter)
      .put("vendorId", p?.vendorId ?: 0)
      .put("matterProductId", p?.productId ?: 0)
      .put("discriminator", p?.discriminator?.value ?: 0)
  }

  // Tên kiểu thiết bị thống nhất với iOS: unknown | wifi | thread | softAP | onNetwork.
  private fun typeName(t: MatterDeviceTypeEnum?): String = when (t) {
    MatterDeviceTypeEnum.WIFI -> "wifi"
    MatterDeviceTypeEnum.THREAD -> "thread"
    MatterDeviceTypeEnum.SOFT_AP -> "softAP"
    MatterDeviceTypeEnum.ON_NETWORK -> "onNetwork"
    else -> "unknown"
  }
}
