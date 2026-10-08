package com.jimmyvu.turbotuya.mesh

// TuyaMesh (Android) - WIRED trên SDK 7.5.6 (thingsmart-bluetooth*). Signature verify bằng javap + sample chính chủ
// (tuya-home-android-sdk-sample-java: SubConfigAppActivity / DeviceMgtListActivity):
//   create : ThingHomeSdk.newHomeInstance(homeId).createSigMesh(IThingResultCallback<SigMeshBean>)
//            / createBlueMesh(name, IThingResultCallback<BlueMeshBean>)  (SIG KHÔNG nhận tên → `name` bị bỏ qua)
//   list   : getSigMeshInstance().requestSigMeshList(homeId, ..) + getMeshInstance().requestMeshList(homeId, ..)
//            (long = gid/homeId - bytecode: ApiParams.setGid). Bean cache: getSigMeshBean / getBlueMeshBean(meshId).
//   client : getThingSigMeshClient() / getThingBlueMeshClient(): initMesh(meshId) + startClient(bean[, searchMs])
//            (searchTime = ms - bytecode: Handler.sendEmptyMessageDelayed) / stopClient()
//   search : getThingBlueMeshConfig().newThingBlueMeshSearch(SearchBuilder) - SIG: service UUID 0x1827,
//            Tuya: meshName "out_of_mesh" (tên mặc định của thiết bị chưa pair). SearchBuilder.setTimeOut = giây.
//   active : newSigActivator(ThingSigMeshActivatorBuilder) / newActivator(ThingBlueMeshActivatorBuilder,
//            version "1.0" = sub-device; "2.2" là gateway Wi-Fi - cần ssid/pwd, spec không có → không hỗ trợ).
//   control: newSigMeshDeviceInstance / newBlueMeshDeviceInstance(meshId).publishDps(nodeId,pcc,dpsJson,cb)
//            / multicastDps(localId,pcc,dpsJson,cb) + registerMeshDevListener(IMeshDevListener) → event.
// LƯU Ý: SDK tra mesh + sub-device từ CACHE home → gọi TuyaHome.getHomeDetail(homeId) trước khi điều khiển.
// Mọi factory của ThingHomeSdk ở đây trả null nếu plugin BLE mesh vắng → xử lý nullable.

import android.util.Log
import com.jimmyvu.turbotuya.NativeTuyaMeshSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.android.blemesh.api.IThingBlueMeshActivatorListener
import com.thingclips.smart.android.blemesh.api.IThingBlueMeshDevice
import com.thingclips.smart.android.blemesh.api.IThingBlueMeshSearch
import com.thingclips.smart.android.blemesh.api.IThingBlueMeshSearchListener
import com.thingclips.smart.android.blemesh.bean.SearchDeviceBean
import com.thingclips.smart.android.blemesh.builder.SearchBuilder
import com.thingclips.smart.android.blemesh.builder.ThingBlueMeshActivatorBuilder
import com.thingclips.smart.android.blemesh.builder.ThingSigMeshActivatorBuilder
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.callback.IThingResultCallback
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.bluemesh.IMeshDevListener
import com.thingclips.smart.sdk.api.bluemesh.IRequestMeshListCallback
import com.thingclips.smart.sdk.api.bluemesh.IRequestSigMeshListCallback
import com.thingclips.smart.sdk.api.bluemesh.IThingBlueMeshActivator
import com.thingclips.smart.sdk.bean.BlueMeshBean
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.bean.SigMeshBean
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

// TuyaMesh - BLE Mesh SIG + Tuya. Phát event onMeshDeviceFound/onMeshDpUpdate/onMeshStatusChanged.
class TuyaMeshModule(reactContext: ReactApplicationContext) :
  NativeTuyaMeshSpec(reactContext) {

  private val ctx = reactContext

  // mac (upper-case) → bean scan được (activate cần bean gốc).
  private val scanned = ConcurrentHashMap<String, SearchDeviceBean>()
  // "sig:<meshId>" / "tuya:<meshId>" → device instance (đã gắn IMeshDevListener).
  private val meshDevices = ConcurrentHashMap<String, IThingBlueMeshDevice>()
  @Volatile private var meshSearch: IThingBlueMeshSearch? = null
  @Volatile private var meshActivator: IThingBlueMeshActivator? = null
  @Volatile private var pendingActivate: Once? = null
  @Volatile private var sigClientStarted = false
  @Volatile private var tuyaClientStarted = false

  companion object {
    const val NAME = NativeTuyaMeshSpec.NAME
    private const val TAG = "TuyaMesh"
    private const val EVT_FOUND = "onMeshDeviceFound"
    private const val EVT_DP = "onMeshDpUpdate"
    private const val EVT_STATUS = "onMeshStatusChanged"
    // UUID provisioning cố định của SIG mesh (sample chính chủ).
    private val SIG_PROVISIONING_UUID: UUID = UUID.fromString("00001827-0000-1000-8000-00805f9b34fb")
    // Tên mesh mặc định của thiết bị Tuya mesh chưa pair.
    private const val TUYA_UNPAIRED_MESH_NAME = "out_of_mesh"
    private const val DEFAULT_SEARCH_SEC = 100
    private const val DEFAULT_ACTIVE_SEC = 100
  }

  // Promise chỉ settle 1 lần (onSuccess/onError rồi onFinish).
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

  private fun isSig(meshType: String) = meshType.equals("sig", ignoreCase = true)

  private fun meshUnavailable(promise: Promise) = TuyaReject.reject(
    promise,
    "mesh_unavailable",
    "Tuya BLE mesh plugin is not available (ThingHomeSdk mesh factory returned null).",
  )

  // ---------- Bean lookup: cache trước, rồi hỏi cloud theo homeId ----------
  private fun withSigMesh(homeId: Double, meshId: String, done: (SigMeshBean?, String?, String?) -> Unit) {
    val mgr = ThingHomeSdk.getSigMeshInstance() ?: return done(null, "mesh_unavailable", "SIG mesh manager unavailable.")
    mgr.getSigMeshBean(meshId)?.let { return done(it, null, null) }
    mgr.requestSigMeshList(
      homeId.toLong(),
      object : IRequestSigMeshListCallback {
        override fun onSuccess(list: ArrayList<SigMeshBean>?) {
          val bean = list?.firstOrNull { it.meshId == meshId }
          if (bean != null) done(bean, null, null)
          else done(null, "mesh_not_found", "SIG mesh $meshId not found in home ${homeId.toLong()}.")
        }

        override fun onError(code: String?, msg: String?) = done(null, code, msg)
      },
    )
  }

  private fun withBlueMesh(homeId: Double, meshId: String, done: (BlueMeshBean?, String?, String?) -> Unit) {
    val mgr = ThingHomeSdk.getMeshInstance() ?: return done(null, "mesh_unavailable", "Tuya mesh manager unavailable.")
    mgr.getBlueMeshBean(meshId)?.let { return done(it, null, null) }
    mgr.requestMeshList(
      homeId.toLong(),
      object : IRequestMeshListCallback {
        override fun onSuccess(list: ArrayList<BlueMeshBean>?) {
          val bean = list?.firstOrNull { it.meshId == meshId }
          if (bean != null) done(bean, null, null)
          else done(null, "mesh_not_found", "Tuya mesh $meshId not found in home ${homeId.toLong()}.")
        }

        override fun onError(code: String?, msg: String?) = done(null, code, msg)
      },
    )
  }

  // Device instance theo mesh (SDK new instance mỗi lần gọi → cache) + gắn listener DP/online.
  private fun meshDevice(meshId: String, meshType: String): IThingBlueMeshDevice? {
    val sig = isSig(meshType)
    val key = (if (sig) "sig:" else "tuya:") + meshId
    meshDevices[key]?.let { return it }
    val dev = (if (sig) ThingHomeSdk.newSigMeshDeviceInstance(meshId) else ThingHomeSdk.newBlueMeshDeviceInstance(meshId))
      ?: return null
    dev.registerMeshDevListener(devListener())
    return meshDevices.putIfAbsent(key, dev)?.also { runCatching { dev.unRegisterMeshDevListener(); dev.onDestroy() } } ?: dev
  }

  private fun releaseMeshDevice(meshId: String, meshType: String) {
    val key = (if (isSig(meshType)) "sig:" else "tuya:") + meshId
    meshDevices.remove(key)?.let { runCatching { it.unRegisterMeshDevListener(); it.onDestroy() } }
  }

  private fun devListener() = object : IMeshDevListener {
    override fun onDpUpdate(nodeId: String?, dps: String?, isFromLocal: Boolean) {
      val m = Arguments.createMap()
      m.putString("nodeId", nodeId ?: "")
      m.putString("dpsJson", dps ?: "{}")
      m.putBoolean("isFromLocal", isFromLocal)
      emit(EVT_DP, m)
    }

    override fun onStatusChanged(online: List<String>?, offline: List<String>?, gwId: String?) {
      val m = Arguments.createMap()
      m.putString("onlineJson", JSONArray(online ?: emptyList<String>()).toString())
      m.putString("offlineJson", JSONArray(offline ?: emptyList<String>()).toString())
      m.putString("gwId", gwId ?: "")
      emit(EVT_STATUS, m)
    }

    override fun onNetworkStatusChanged(devId: String?, status: Boolean) {}
    override fun onRawDataUpdate(bytes: ByteArray?) {}
    override fun onDevInfoUpdate(devId: String?) {}
    override fun onRemoved(devId: String?) {}
  }

  // ---------- Create / list ----------
  override fun createSigMesh(homeId: Double, name: String, promise: Promise) {
    val home = ThingHomeSdk.newHomeInstance(homeId.toLong()) ?: return meshUnavailable(promise)
    home.createSigMesh(object : IThingResultCallback<SigMeshBean> {
      override fun onSuccess(result: SigMeshBean?) {
        val meshId = result?.meshId
        if (meshId.isNullOrEmpty()) {
          TuyaReject.reject(promise, "create_sig_mesh_error", "SDK reported success without a meshId.")
        } else {
          promise.resolve(meshId)
        }
      }

      override fun onError(code: String?, msg: String?) =
        TuyaReject.reject(promise, code ?: "create_sig_mesh_error", msg ?: "Create SIG mesh failed.")
    })
  }

  override fun createTuyaMesh(homeId: Double, name: String, promise: Promise) {
    val home = ThingHomeSdk.newHomeInstance(homeId.toLong()) ?: return meshUnavailable(promise)
    home.createBlueMesh(name, object : IThingResultCallback<BlueMeshBean> {
      override fun onSuccess(result: BlueMeshBean?) {
        val meshId = result?.meshId
        if (meshId.isNullOrEmpty()) {
          TuyaReject.reject(promise, "create_tuya_mesh_error", "SDK reported success without a meshId.")
        } else {
          promise.resolve(meshId)
        }
      }

      override fun onError(code: String?, msg: String?) =
        TuyaReject.reject(promise, code ?: "create_tuya_mesh_error", msg ?: "Create Tuya mesh failed.")
    })
  }

  // Gộp SIG + Tuya (2 request); lỗi 1 loại → vẫn trả loại kia; lỗi TẤT CẢ → reject mã thật (ưu tiên SIG).
  override fun getMeshList(homeId: Double, promise: Promise) {
    val sigMgr = ThingHomeSdk.getSigMeshInstance()
    val tuyaMgr = ThingHomeSdk.getMeshInstance()
    if (sigMgr == null && tuyaMgr == null) return meshUnavailable(promise)
    val out = ArrayList<Triple<String, String, String>>()
    val errors = ArrayList<Pair<String?, String?>>()
    val total = if (sigMgr != null && tuyaMgr != null) 2 else 1
    val pending = AtomicInteger(total)
    val finish = {
      if (pending.decrementAndGet() == 0) {
        synchronized(out) {
          if (errors.size == total) {
            val (code, msg) = errors.first()
            TuyaReject.reject(promise, code ?: "mesh_list_error", msg ?: "Get mesh list failed.")
          } else {
            val arr = Arguments.createArray()
            out.forEach { (id, n, t) ->
              val m = Arguments.createMap()
              m.putString("meshId", id)
              m.putString("name", n)
              m.putString("type", t)
              arr.pushMap(m)
            }
            promise.resolve(arr)
          }
        }
      }
    }
    sigMgr?.requestSigMeshList(
      homeId.toLong(),
      object : IRequestSigMeshListCallback {
        override fun onSuccess(list: ArrayList<SigMeshBean>?) {
          synchronized(out) { list?.forEach { out.add(Triple(it.meshId ?: "", it.name ?: "", "sig")) } }
          finish()
        }

        override fun onError(code: String?, msg: String?) {
          synchronized(out) { errors.add(0, code to msg) }
          finish()
        }
      },
    )
    tuyaMgr?.requestMeshList(
      homeId.toLong(),
      object : IRequestMeshListCallback {
        override fun onSuccess(list: ArrayList<BlueMeshBean>?) {
          synchronized(out) { list?.forEach { out.add(Triple(it.meshId ?: "", it.name ?: "", "tuya")) } }
          finish()
        }

        override fun onError(code: String?, msg: String?) {
          synchronized(out) { errors.add(code to msg) }
          finish()
        }
      },
    )
  }

  // ---------- Client lifecycle (connect proxy) ----------
  // void theo spec → lỗi chỉ log được (không có event lỗi cho mesh).
  override fun startMeshClient(homeId: Double, meshId: String, meshType: String, searchTimeSec: Double) {
    val searchMs = if (searchTimeSec > 0) (searchTimeSec * 1000).toLong() else 0L
    if (isSig(meshType)) {
      withSigMesh(homeId, meshId) { bean, code, msg ->
        val client = ThingHomeSdk.getThingSigMeshClient()
        if (bean == null || client == null) {
          Log.w(TAG, "startMeshClient(sig) failed: ${code ?: "mesh_unavailable"} ${msg ?: ""}")
          return@withSigMesh
        }
        runCatching {
          client.initMesh(meshId)
          if (searchMs > 0) client.startClient(bean, searchMs) else client.startClient(bean)
          sigClientStarted = true
          meshDevice(meshId, meshType)
        }.onFailure { Log.w(TAG, "startMeshClient(sig) failed", it) }
      }
    } else {
      withBlueMesh(homeId, meshId) { bean, code, msg ->
        val client = ThingHomeSdk.getThingBlueMeshClient()
        if (bean == null || client == null) {
          Log.w(TAG, "startMeshClient(tuya) failed: ${code ?: "mesh_unavailable"} ${msg ?: ""}")
          return@withBlueMesh
        }
        runCatching {
          client.initMesh(meshId)
          if (searchMs > 0) client.startClient(bean, searchMs) else client.startClient(bean)
          tuyaClientStarted = true
          meshDevice(meshId, meshType)
        }.onFailure { Log.w(TAG, "startMeshClient(tuya) failed", it) }
      }
    }
  }

  override fun stopMeshClient(homeId: Double, meshId: String, meshType: String) {
    stopSearch()
    runCatching { meshActivator?.stopActivator() }
    meshActivator = null
    pendingActivate?.reject("mesh_active_cancelled", "Mesh client stopped during activation.")
    pendingActivate = null
    if (isSig(meshType)) {
      runCatching { ThingHomeSdk.getThingSigMeshClient()?.stopClient() }
      sigClientStarted = false
    } else {
      runCatching { ThingHomeSdk.getThingBlueMeshClient()?.stopClient() }
      tuyaClientStarted = false
    }
    releaseMeshDevice(meshId, meshType)
  }

  // ---------- Tìm sub-device chưa pair → onMeshDeviceFound ----------
  override fun searchSubDevices(homeId: Double, meshId: String, meshType: String, timeoutSec: Double) {
    stopSearch()
    scanned.clear()
    val sig = isSig(meshType)
    val config = ThingHomeSdk.getThingBlueMeshConfig()
    if (config == null) {
      Log.w(TAG, "searchSubDevices failed: mesh_unavailable")
      return
    }
    val builder = SearchBuilder()
      .setTimeOut(if (timeoutSec > 0) timeoutSec.toInt().coerceAtLeast(1) else DEFAULT_SEARCH_SEC)
      .setThingBlueMeshSearchListener(object : IThingBlueMeshSearchListener {
        override fun onSearched(bean: SearchDeviceBean?) {
          if (bean == null) return
          val mac = bean.macAdress ?: return
          scanned[mac.uppercase()] = bean
          val m = Arguments.createMap()
          m.putString("dataJson", searchBeanToJson(bean, if (sig) "sig" else "tuya").toString())
          emit(EVT_FOUND, m)
        }

        override fun onSearchFinish() {}
      })
    if (sig) builder.setServiceUUIDs(arrayOf(SIG_PROVISIONING_UUID)) else builder.setMeshName(TUYA_UNPAIRED_MESH_NAME)
    runCatching {
      val search = config.newThingBlueMeshSearch(builder.build())
      meshSearch = search
      search.startSearch()
    }.onFailure { Log.w(TAG, "searchSubDevices failed", it) }
  }

  private fun stopSearch() {
    runCatching { meshSearch?.stopSearch() }
    meshSearch = null
  }

  // ---------- Active sub-device đã scan (theo mac) ----------
  override fun activateSubDevice(
    homeId: Double,
    meshId: String,
    meshType: String,
    mac: String,
    timeoutSec: Double,
    promise: Promise,
  ) {
    val key = mac.uppercase()
    val bean = scanned[key]
      ?: return TuyaReject.reject(promise, "mesh_scan_required", "Device $mac was not found by searchSubDevices - scan first.")
    val config = ThingHomeSdk.getThingBlueMeshConfig() ?: return meshUnavailable(promise)
    pendingActivate?.reject("mesh_superseded", "activateSubDevice was called again before the previous call finished.")
    runCatching { meshActivator?.stopActivator() }
    meshActivator = null
    stopSearch() // scan song song với provisioning làm nhiễu BLE
    val once = Once(promise)
    pendingActivate = once
    val timeout = if (timeoutSec > 0) timeoutSec.toInt().coerceAtLeast(1) else DEFAULT_ACTIVE_SEC
    val listener = object : IThingBlueMeshActivatorListener {
      override fun onSuccess(devMac: String?, dev: DeviceBean?) {
        scanned.remove(key)
        settleActivate(once)
        once.resolve(subDeviceToMap(dev))
      }

      override fun onError(devMac: String?, code: String?, msg: String?) {
        settleActivate(once)
        once.reject(code ?: "mesh_active_error", msg ?: "Mesh sub-device activation failed.")
      }

      override fun onFinish() {
        settleActivate(once)
        once.reject("mesh_active_error", "Activation finished without a result for $mac.")
      }
    }
    val start: (IThingBlueMeshActivator?) -> Unit = { act ->
      if (act == null) {
        settleActivate(once)
        once.reject("mesh_unavailable", "Tuya BLE mesh activator unavailable.")
      } else if (pendingActivate === once) {
        meshActivator = act
        runCatching { act.startActivator() }.onFailure {
          settleActivate(once)
          once.reject("mesh_active_error", it.message ?: it.toString())
        }
      }
    }
    if (isSig(meshType)) {
      withSigMesh(homeId, meshId) { sigBean, code, msg ->
        if (sigBean == null) {
          settleActivate(once)
          once.reject(code ?: "mesh_not_found", msg ?: "SIG mesh $meshId not found.")
          return@withSigMesh
        }
        val b = ThingSigMeshActivatorBuilder()
          .setSearchDeviceBeans(arrayListOf(bean))
          .setSigMeshBean(sigBean)
          .setHomeId(homeId.toLong())
          .setTimeOut(timeout)
          .setThingBlueMeshActivatorListener(listener)
        start(config.newSigActivator(b))
      }
    } else {
      withBlueMesh(homeId, meshId) { blueBean, code, msg ->
        if (blueBean == null) {
          settleActivate(once)
          once.reject(code ?: "mesh_not_found", msg ?: "Tuya mesh $meshId not found.")
          return@withBlueMesh
        }
        val b = ThingBlueMeshActivatorBuilder()
          .setSearchDeviceBeans(arrayListOf(bean))
          .setVersion("1.0")
          .setBlueMeshBean(blueBean)
          .setHomeId(homeId.toLong())
          .setTimeOut(timeout)
          .setThingBlueMeshActivatorListener(listener)
        start(config.newActivator(b))
      }
    }
  }

  private fun settleActivate(once: Once) {
    if (pendingActivate === once) {
      pendingActivate = null
      meshActivator = null
    }
  }

  // ---------- Điều khiển DP qua mesh (dps = chuỗi JSON object, SDK nhận nguyên chuỗi) ----------
  override fun publishMeshDps(
    homeId: Double,
    meshId: String,
    meshType: String,
    nodeId: String,
    pcc: String,
    dpsJson: String,
    promise: Promise,
  ) {
    if (!isJsonObject(dpsJson)) return TuyaReject.reject(promise, "invalid_dps_json", "dpsJson must be a JSON object string.")
    val dev = meshDevice(meshId, meshType) ?: return meshUnavailable(promise)
    try {
      dev.publishDps(nodeId, pcc, dpsJson, resultCallback(promise, "publish_mesh_dps_error", "Publish mesh DPs failed."))
    } catch (e: Throwable) {
      TuyaReject.reject(promise, "publish_mesh_dps_error", e.message ?: e.toString())
    }
  }

  override fun multicastMeshDps(
    homeId: Double,
    meshId: String,
    meshType: String,
    localId: String,
    pcc: String,
    dpsJson: String,
    promise: Promise,
  ) {
    if (!isJsonObject(dpsJson)) return TuyaReject.reject(promise, "invalid_dps_json", "dpsJson must be a JSON object string.")
    val dev = meshDevice(meshId, meshType) ?: return meshUnavailable(promise)
    try {
      dev.multicastDps(localId, pcc, dpsJson, resultCallback(promise, "multicast_mesh_dps_error", "Multicast mesh DPs failed."))
    } catch (e: Throwable) {
      TuyaReject.reject(promise, "multicast_mesh_dps_error", e.message ?: e.toString())
    }
  }

  private fun resultCallback(promise: Promise, fallbackCode: String, fallbackMsg: String) = object : IResultCallback {
    override fun onSuccess() = promise.resolve(null)
    override fun onError(code: String?, msg: String?) = TuyaReject.reject(promise, code ?: fallbackCode, msg ?: fallbackMsg)
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // Dọn scan/activator/listener/client khi RN instance huỷ (reload/unmount).
  override fun invalidate() {
    super.invalidate()
    stopSearch()
    runCatching { meshActivator?.stopActivator() }
    meshActivator = null
    pendingActivate = null
    meshDevices.values.forEach { runCatching { it.unRegisterMeshDevListener(); it.onDestroy() } }
    meshDevices.clear()
    if (sigClientStarted) runCatching { ThingHomeSdk.getThingSigMeshClient()?.stopClient() }
    if (tuyaClientStarted) runCatching { ThingHomeSdk.getThingBlueMeshClient()?.stopClient() }
    sigClientStarted = false
    tuyaClientStarted = false
    scanned.clear()
  }

  // ---------- helpers ----------
  private fun isJsonObject(s: String) = runCatching { JSONObject(s) }.isSuccess

  private fun subDeviceToMap(dev: DeviceBean?): WritableMap {
    val m = Arguments.createMap()
    m.putString("devId", dev?.devId ?: "")
    m.putString("name", dev?.name ?: "")
    m.putString("productId", dev?.productId ?: "")
    m.putString("nodeId", dev?.nodeId ?: "")
    return m
  }

  // `mac` là khoá để JS truyền lại vào activateSubDevice (giữ nguyên chuỗi SDK trả).
  private fun searchBeanToJson(b: SearchDeviceBean, meshType: String): JSONObject = JSONObject()
    .put("mac", b.macAdress ?: "")
    .put("meshType", meshType)
    .put("name", b.meshName ?: "")
    .put("rssi", b.rssi)
    .put("productId", b.productId?.joinToString("") { "%02x".format(it) } ?: "")
    .put("vendorId", b.vendorId)
    .put("type", b.type)
}
