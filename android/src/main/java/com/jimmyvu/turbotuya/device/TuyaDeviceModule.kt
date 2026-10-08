package com.jimmyvu.turbotuya.device

// Mở rộng theo docs/research/tuya-home-sdk-device-control.md + device-management (verbatim).
// Chữ ký SDK 7.5.6 đã verify bằng javap: publishDps(dps, ordersJson, cb) · requestWifiSignal(WifiSignalListener) ·
// getRequestInstance().sendCacheDps(devId, dps, validity, type, IThingDataCallback<Boolean>) ·
// getBleManager().connectBleDevice/disconnectBleDevice(List<BleConnectBuilder>) + isBleLocalOnline(devId).

import com.jimmyvu.turbotuya.NativeTuyaDeviceSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.ble.IThingBleManager
import com.thingclips.smart.android.ble.api.BleConnectStatusListener
import com.thingclips.smart.android.ble.builder.BleConnectBuilder
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IDevListener
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDataCallback
import com.thingclips.smart.sdk.api.IThingDevice
import com.thingclips.smart.sdk.api.WifiSignalListener
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.enums.ThingDevicePublishModeEnum
import org.json.JSONArray
import org.json.JSONObject
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean

// TuyaDevice - điều khiển DP + status + quản lý thiết bị (B4 mở rộng). Phát event onDeviceStatus.
class TuyaDeviceModule(reactContext: ReactApplicationContext) :
  NativeTuyaDeviceSpec(reactContext) {

  private val ctx = reactContext
  private val devices = mutableMapOf<String, IThingDevice>()

  companion object {
    const val NAME = NativeTuyaDeviceSpec.NAME
    private const val EVT_DEVICE = "onDeviceStatus"
    private const val DEFAULT_ACK_TIMEOUT = 8000L
    // Thiết bị trả signal qua MQTT, SDK KHÔNG tự timeout → tự chặn để promise không treo.
    private const val WIFI_SIGNAL_TIMEOUT_MS = 10_000L
    // connectBleDevice là void (không callback) → chờ CONNECTED/isBleLocalOnline tối đa chừng này.
    private const val BLE_CONNECT_TIMEOUT_MS = 30_000L
    private const val BLE_POLL_MS = 1_000L
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
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
    channels: ReadableArray,
    promise: Promise,
  ) {
    // channels (thứ tự ưu tiên) → mã CommunicationEnum (LAN=0, MQTT=1, HTTP=2, BLE=3, ...; cùng số với iOS
    // ThingCommunicationType). SDK nhận chuỗi JSON mảng int, vd "[3,1]"; mã SDK không biết → bị bỏ,
    // bỏ hết → onError("301001", "communication_types_illegal").
    val orders = JSONArray()
    for (i in 0 until channels.size()) {
      val raw = when (channels.getType(i)) {
        ReadableType.Number -> channels.getDouble(i).toInt().toString()
        ReadableType.String -> channels.getString(i) ?: ""
        else -> ""
      }
      val type = channelType(raw)
      if (type == null) {
        TuyaReject.reject(
          promise,
          "invalid_channel",
          "Unknown channel '$raw'. Use lan, mqtt|cloud, http, ble, sigmesh, mesh, beacon, matter, yumqtt, cloudmode or a numeric CommunicationEnum type.",
        )
        return
      }
      orders.put(type)
    }
    if (orders.length() == 0) {
      TuyaReject.reject(promise, "invalid_channel", "channels is empty - pass at least one channel, e.g. ['ble','cloud'].")
      return
    }
    deviceOf(devId).publishDps(dpsJson, orders.toString(), object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        TuyaReject.reject(promise, code ?: "publish_dps_error", error ?: "publishDps with channel orders failed.")
    })
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
      m.putString("schemaJson", bean.schema?.toString() ?: "") // raw - verify format khi render
      m.putString("dpCodesJson", JSONObject((bean.dpCodes ?: emptyMap<String, Any>()) as Map<*, *>).toString())
      // Toàn bộ thông tin DeviceBean SDK trả về - CHỈ để log/chẩn đoán (getter verify bằng javap 7.5.6).
      val raw = JSONObject()
        .put("devId", bean.devId ?: "")
        .put("name", bean.name ?: "")
        .put("iconUrl", bean.iconUrl ?: "")
        .put("productId", bean.productId ?: "")
        .put("productVer", bean.productVer ?: "")
        .put("verSw", bean.verSw ?: "")
        .put("mac", bean.mac ?: "")
        .put("uiType", bean.uiType ?: "")
        .put("ownerId", bean.ownerId ?: "")
        .put("parentDevId", bean.parentDevId ?: "")
        .put("devAttribute", bean.devAttribute)
        .put("sharedTime", bean.sharedTime)
        .put("isOnline", bean.isOnline)
        .put("isLocalOnline", bean.isLocalOnline)
        .put("isShare", bean.isShare ?: false)
        .put("dps", JSONObject((bean.dps ?: emptyMap<String, Any>()) as Map<*, *>))
        .put("dpsTime", JSONObject((bean.dpsTime ?: emptyMap<String, Any>()) as Map<*, *>))
      m.putString("rawJson", raw.toString())
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
    // Thiết bị low-power: DP nằm cache cloud chờ thiết bị thức. SDK tự kẹp validity ≤ 172800s;
    // dps sai → "1500", devId/dps rỗng → "10010" (mã thật trả qua onError).
    val request = ThingHomeSdk.getRequestInstance()
    if (request == null) {
      TuyaReject.reject(promise, "sdk_unavailable", "ThingHomeSdk.getRequestInstance() returned null (device plugin not loaded).")
      return
    }
    request.sendCacheDps(
      devId,
      dpsJson,
      validitySec.toLong(),
      dpCacheType.toInt(),
      object : IThingDataCallback<Boolean> {
        // onSuccess = API thành công; null (hiếm) coi như true.
        override fun onSuccess(result: Boolean?) = promise.resolve(result ?: true)
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "send_cache_dps_error", error ?: "sendCacheDps failed.")
      },
    )
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
    // SDK gửi {"reqType":"sigQry"} qua MQTT, thiết bị trả "signal" (RSSI dBm, vd "-45") → onSignalValueFind.
    // Instance RIÊNG (như publishDpsAwaitAck) → onDestroy gỡ MQTT listener của lần hỏi này.
    // Không có Wi-Fi → onError("20001", "the device has no wifi capability").
    val dev = ThingHomeSdk.newDeviceInstance(devId)
    if (dev == null) {
      TuyaReject.reject(promise, "no_device", "Device not found: $devId")
      return
    }
    val handler = Handler(Looper.getMainLooper())
    val settled = AtomicBoolean(false)
    fun finish(block: () -> Unit) {
      if (!settled.compareAndSet(false, true)) return
      handler.removeCallbacksAndMessages(null)
      handler.post { runCatching { dev.onDestroy() } }
      block()
    }
    handler.postDelayed({
      finish {
        TuyaReject.reject(promise, "wifi_signal_timeout", "Device did not report its Wi-Fi signal within ${WIFI_SIGNAL_TIMEOUT_MS}ms.")
      }
    }, WIFI_SIGNAL_TIMEOUT_MS)
    dev.requestWifiSignal(object : WifiSignalListener {
      override fun onSignalValueFind(signal: String?) {
        val value = signal?.trim()?.toDoubleOrNull()
        finish {
          if (value != null) {
            promise.resolve(value)
          } else {
            TuyaReject.reject(promise, "wifi_signal_invalid", "Device reported a non-numeric signal: '$signal'.")
          }
        }
      }
      override fun onError(code: String?, error: String?) =
        finish { TuyaReject.reject(promise, code ?: "wifi_signal_error", error ?: "requestWifiSignal failed.") }
    })
  }

  // ---------- BLE local control ----------
  // ThingHomeSdk.getBleManager(): connect/disconnect là VOID (không callback) và SDK lặng lẽ bỏ qua nếu thiếu
  // quyền BLUETOOTH_CONNECT (Android 12+) → tự kiểm quyền trước để báo lỗi rõ thay vì treo tới timeout.
  override fun bleConnect(devId: String, promise: Promise) {
    val ble = bleManagerOrReject(promise) ?: return
    if (!hasBleConnectPermission()) {
      rejectBlePermission(promise, "connectBleDevice")
      return
    }
    if (ble.isBleLocalOnline(devId)) {
      promise.resolve(null)
      return
    }
    val handler = Handler(Looper.getMainLooper())
    val settled = AtomicBoolean(false)
    var lastStatus = ""
    lateinit var statusListener: BleConnectStatusListener
    fun finish(block: () -> Unit) {
      if (!settled.compareAndSet(false, true)) return
      handler.removeCallbacksAndMessages(null)
      runCatching { ble.unregisterDeviceConnectStatus(devId, statusListener) }
      block()
    }
    // Resolve khi SDK báo CONNECTED; CONNECT_BREAK/DISCONNECT giữa chừng chỉ ghi lại (SDK còn đang thử),
    // hết giờ mới reject kèm trạng thái cuối. Poll isBleLocalOnline làm lưới an toàn nếu lỡ event.
    statusListener = object : BleConnectStatusListener {
      override fun onConnectStatusChanged(id: String?, status: String?) {
        lastStatus = status ?: ""
        if (status == BleConnectStatusListener.STATE_CONNECT_SUCCESS) {
          handler.post { finish { promise.resolve(null) } }
        }
      }
    }
    ble.registerDeviceConnectStatus(devId, statusListener)
    val poll = object : Runnable {
      override fun run() {
        if (settled.get()) return
        if (ble.isBleLocalOnline(devId)) {
          finish { promise.resolve(null) }
        } else {
          handler.postDelayed(this, BLE_POLL_MS)
        }
      }
    }
    handler.postDelayed(poll, BLE_POLL_MS)
    handler.postDelayed({
      finish {
        TuyaReject.reject(
          promise,
          "ble_connect_timeout",
          "BLE not connected within ${BLE_CONNECT_TIMEOUT_MS}ms (last status: ${lastStatus.ifEmpty { "none" }}).",
        )
      }
    }, BLE_CONNECT_TIMEOUT_MS)
    ble.connectBleDevice(listOf(BleConnectBuilder().setDevId(devId)))
  }

  override fun bleDisconnect(devId: String, promise: Promise) {
    val ble = bleManagerOrReject(promise) ?: return
    if (!hasBleConnectPermission()) {
      rejectBlePermission(promise, "disconnectBleDevice")
      return
    }
    // SDK void → resolve = "đã gửi lệnh ngắt"; xác nhận bằng isBleLocalOnline / onDeviceStatus.
    ble.disconnectBleDevice(listOf(BleConnectBuilder().setDevId(devId)))
    promise.resolve(null)
  }

  override fun isBleLocalOnline(devId: String, promise: Promise) {
    val ble = bleManagerOrReject(promise) ?: return
    promise.resolve(ble.isBleLocalOnline(devId))
  }

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

  // Tên kênh JS → mã CommunicationEnum (getType()). Chuỗi số ("3") đi thẳng để SDK tự kiểm.
  private fun channelType(name: String): Int? {
    val n = name.trim().lowercase()
    n.toIntOrNull()?.let { return it }
    return when (n) {
      "lan", "local" -> 0
      "mqtt", "cloud", "internet" -> 1
      "http" -> 2
      "ble", "bluetooth" -> 3
      "sigmesh", "sig_mesh" -> 4
      "mesh", "blemesh", "ble_mesh", "thing_mesh" -> 5
      "beacon" -> 6
      "matter" -> 8
      "yumqtt", "yu_mqtt" -> 12
      "cloudmode", "cloud_mode" -> 100
      else -> null
    }
  }

  private fun bleManagerOrReject(promise: Promise): IThingBleManager? {
    val ble = ThingHomeSdk.getBleManager()
    if (ble == null) {
      TuyaReject.reject(promise, "ble_unavailable", "ThingHomeSdk.getBleManager() returned null (BLE plugin not loaded).")
    }
    return ble
  }

  private fun hasBleConnectPermission(): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
      ctx.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

  private fun rejectBlePermission(promise: Promise, what: String) =
    TuyaReject.reject(
      promise,
      "ble_permission_denied",
      "BLUETOOTH_CONNECT permission not granted - the SDK silently skips $what without it.",
    )
}
