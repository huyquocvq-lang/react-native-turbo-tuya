package com.jimmyvu.turbotuya.device

// Mở rộng theo docs/research/tuya-home-sdk-device-control.md + device-management (verbatim) — CHƯA build-verify.
// ⚠️ Verify import: ThingDevicePublishModeEnum (package .sdk.enums có thể lệch). WiFi-signal/BLE/orders/cache để TODO.

import com.jimmyvu.turbotuya.NativeTuyaDeviceSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IDevListener
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDevice
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.enums.ThingDevicePublishModeEnum
import org.json.JSONObject
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean

// TuyaDevice — điều khiển DP + status + quản lý thiết bị (B4 mở rộng). Phát event onDeviceStatus.
class TuyaDeviceModule(reactContext: ReactApplicationContext) :
  NativeTuyaDeviceSpec(reactContext) {

  private val ctx = reactContext
  private val devices = mutableMapOf<String, IThingDevice>()

  companion object {
    const val NAME = NativeTuyaDeviceSpec.NAME
    private const val EVT_DEVICE = "onDeviceStatus"
    private const val DEFAULT_ACK_TIMEOUT = 8000L
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  private fun todo(promise: Promise, what: String) {
    promise.reject(
      "not_implemented",
      "$what chưa wire (cần verify chữ ký native) — xem docs/research/tuya-home-sdk-device-control.md",
    )
  }

  // ---------- DP control ----------
  override fun publishDps(devId: String, dpsJson: String, promise: Promise) {
    deviceOf(devId).publishDps(dpsJson, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "publish_dps_error", error)
    })
  }

  override fun publishDpsWithMode(devId: String, dpsJson: String, mode: String, promise: Promise) {
    val m = when (mode.lowercase()) {
      "local" -> ThingDevicePublishModeEnum.ThingDevicePublishModeLocal
      "internet" -> ThingDevicePublishModeEnum.ThingDevicePublishModeInternet
      else -> ThingDevicePublishModeEnum.ThingDevicePublishModeAuto
    }
    deviceOf(devId).publishDps(dpsJson, m, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "publish_dps_error", error)
    })
  }

  override fun publishDpsWithChannels(
    devId: String,
    dpsJson: String,
    channels: com.facebook.react.bridge.ReadableArray,
    promise: Promise,
  ) {
    // publishDps(dps, orders, cb) với orders theo CommunicationEnum (giá trị int chưa rõ) — TODO verify.
    todo(promise, "publishDpsWithChannels (CommunicationEnum)")
  }

  override fun publishDpsAwaitAck(devId: String, dpsJson: String, timeoutMs: Double, promise: Promise) {
    // Dùng instance riêng để không clobber listener bền ở registerDeviceListener.
    val dev = ThingHomeSdk.newDeviceInstance(devId)
    val handler = Handler(Looper.getMainLooper())
    val settled = AtomicBoolean(false)
    fun cleanup() {
      handler.removeCallbacksAndMessages(null)
      dev.unRegisterDevListener()
      dev.onDestroy()
    }
    // Resolve khi onDpUpdate KHỚP dpId vừa publish (publishDps.onSuccess chỉ = "đã gửi").
    val wantedKeys = runCatching { JSONObject(dpsJson).keys().asSequence().toSet() }.getOrDefault(emptySet())
    dev.registerDevListener(object : IDevListener {
      override fun onDpUpdate(id: String?, dpStr: String?) {
        val matched = wantedKeys.isEmpty() || runCatching {
          JSONObject(dpStr ?: "{}").keys().asSequence().any { wantedKeys.contains(it) }
        }.getOrDefault(true)
        if (matched && settled.compareAndSet(false, true)) { cleanup(); promise.resolve(null) }
      }
      override fun onRemoved(id: String?) {}
      override fun onStatusChanged(id: String?, online: Boolean) {}
      override fun onNetworkStatusChanged(id: String?, status: Boolean) {}
      override fun onDevInfoUpdate(id: String?) {}
    })
    val timeout = if (timeoutMs <= 0) DEFAULT_ACK_TIMEOUT else timeoutMs.toLong()
    handler.postDelayed({
      if (settled.compareAndSet(false, true)) { cleanup(); promise.reject("ack_timeout", "Không nhận onDpUpdate trong ${timeout}ms") }
    }, timeout)
    dev.publishDps(dpsJson, object : IResultCallback {
      override fun onSuccess() { /* chờ onDpUpdate */ }
      override fun onError(code: String?, error: String?) {
        if (settled.compareAndSet(false, true)) { cleanup(); promise.reject(code ?: "publish_dps_error", error) }
      }
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

  override fun queryDp(devId: String, dpId: String, promise: Promise) {
    // Kết quả về qua event onDeviceStatus (onDpUpdate), KHÔNG trả ở callback này.
    deviceOf(devId).getDp(dpId, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "query_dp_error", error)
    })
  }

  override fun getDeviceSnapshot(devId: String, promise: Promise) {
    try {
      val bean = ThingHomeSdk.getDataInstance().getDeviceBean(devId)
      if (bean == null) { promise.reject("no_device", "Không tìm thấy thiết bị $devId"); return }
      val m = Arguments.createMap()
      m.putString("devId", bean.devId ?: devId)
      m.putString("productId", bean.productId ?: "")
      m.putString("dpsJson", JSONObject((bean.dps ?: emptyMap<String, Any>()) as Map<*, *>).toString())
      m.putBoolean("isOnline", bean.isOnline) // getIsOnline(): LAN hoặc cloud
      m.putBoolean("isLocalOnline", bean.isLocalOnline)
      m.putString("schemaJson", bean.schema?.toString() ?: "") // raw — verify format khi render
      m.putString("dpCodesJson", JSONObject((bean.dpCodes ?: emptyMap<String, Any>()) as Map<*, *>).toString())
      promise.resolve(m)
    } catch (e: Throwable) {
      promise.reject("snapshot_error", e)
    }
  }

  override fun isDeviceOnline(devId: String, promise: Promise) {
    val bean = ThingHomeSdk.getDataInstance().getDeviceBean(devId)
    promise.resolve(bean?.isOnline ?: false)
  }

  override fun isCloudConnected(promise: Promise) {
    promise.resolve(ThingHomeSdk.getServerInstance().isServerConnect)
  }

  override fun sendCacheDps(
    devId: String,
    dpsJson: String,
    validitySec: Double,
    dpCacheType: Double,
    promise: Promise,
  ) {
    // sendCacheDps(devId, dps, validity, dpCacheType, IThingDataCallback<Boolean>) — chữ ký cần verify; low-value cho ice-bath.
    todo(promise, "sendCacheDps")
  }

  // ---------- Device listener ----------
  override fun registerDeviceListener(devId: String) {
    val dev = deviceOf(devId)
    dev.unRegisterDevListener() // idempotent: tránh đăng trùng listener khi gọi lại
    dev.registerDevListener(object : IDevListener {
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

  // ---------- Device management ----------
  override fun renameDevice(devId: String, name: String, promise: Promise) {
    deviceOf(devId).renameDevice(name, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "rename_error", error)
    })
  }

  override fun removeDevice(devId: String, promise: Promise) {
    deviceOf(devId).removeDevice(object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "remove_error", error)
    })
  }

  override fun resetFactory(devId: String, promise: Promise) {
    deviceOf(devId).resetFactory(object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "reset_factory_error", error)
    })
  }

  override fun getWifiSignal(devId: String, promise: Promise) {
    // requestWifiSignal(WifiSignalListener) — listener chưa verbatim → TODO verify.
    todo(promise, "getWifiSignal")
  }

  // ---------- BLE local control ----------
  override fun bleConnect(devId: String, promise: Promise) =
    todo(promise, "bleConnect (getBleManager/BleConnectBuilder)")

  override fun bleDisconnect(devId: String, promise: Promise) =
    todo(promise, "bleDisconnect")

  override fun isBleLocalOnline(devId: String, promise: Promise) =
    todo(promise, "isBleLocalOnline")

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // Dọn device instance + listener khi RN instance huỷ (reload/unmount) → tránh leak.
  override fun invalidate() {
    super.invalidate()
    devices.values.forEach { runCatching { it.unRegisterDevListener(); it.onDestroy() } }
    devices.clear()
  }

  // ---------- helpers ----------
  private fun deviceOf(devId: String): IThingDevice =
    devices.getOrPut(devId) { ThingHomeSdk.newDeviceInstance(devId) }
}
