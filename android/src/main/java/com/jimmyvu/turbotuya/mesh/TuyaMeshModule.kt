package com.jimmyvu.turbotuya.mesh

// B15 (P3) theo docs/research/tuya-home-sdk-bluetooth.md §7 (SIG mesh) + §8 (Tuya mesh) — CHƯA build-verify.
// SKELETON có chủ đích (như B7/B13/B14): mesh là subsystem STATEFUL lớn (client proxy lifecycle + device instance +
// nhiều listener) + iOS sig/tuya mesh signature CHƯA verbatim (note "Câu hỏi mở") + note ghi "chỉ làm nếu có thiết bị
// mesh thật". Package CHƯA verbatim → TODO-reject + intended-call để wire trên SDK thật. Giữ event plumbing.
//
// Intended (Android SIG, note §7):
//   create: ThingHomeSdk.newHomeInstance(homeId).createSigMesh(IThingResultCallback<SigMeshBean>) → meshId
//   list:   ThingHomeSdk.getSigMeshInstance().getSigMeshList()
//   client: getThingSigMeshClient().initMesh(meshId)/startClient(SigMeshBean[,searchTime])/stopClient()/startSearch()/stopSearch()
//   search: SearchBuilder().setTimeOut(..).setThingBlueMeshSearchListener(onSearched(SearchDeviceBean)→emit onMeshDeviceFound)
//   active: ThingSigMeshActivatorBuilder().setSearchDeviceBeans(list).setSigMeshBean(..).setThingBlueMeshActivatorListener(onSuccess(mac,DeviceBean))
//   control: newSigMeshDeviceInstance(meshId).publishDps(nodeId,pcc,dps,IResultCallback)/multicastDps(localId,pcc,dps,..)
//   listener: registerMeshDevListener(IMeshDevListener{onDpUpdate(nodeId,dps,isFromLocal)→onMeshDpUpdate; onStatusChanged(online,offline,gwId)→onMeshStatusChanged})
// Tuya mesh (§8): createBlueMesh / getThingBlueMeshClient / newBlueMeshDeviceInstance / ThingBlueMeshActivatorBuilder (setVersion "1.0"/"2.2").

import com.jimmyvu.turbotuya.NativeTuyaMeshSpec
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

// TuyaMesh — BLE Mesh (skeleton). Phát event onMeshDeviceFound/onMeshDpUpdate/onMeshStatusChanged.
class TuyaMeshModule(reactContext: ReactApplicationContext) :
  NativeTuyaMeshSpec(reactContext) {

  private val ctx = reactContext

  companion object {
    const val NAME = NativeTuyaMeshSpec.NAME
    private const val EVT_FOUND = "onMeshDeviceFound"
    private const val EVT_DP = "onMeshDpUpdate"
    private const val EVT_STATUS = "onMeshStatusChanged"
  }

  @Suppress("unused")
  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit(event, params)
  }

  private fun todo(promise: Promise, what: String) {
    promise.reject(
      "not_implemented",
      "$what chưa wire (mesh subsystem chưa verbatim) — xem docs/research/tuya-home-sdk-bluetooth.md §7/§8 + intended-call.",
    )
  }

  override fun createSigMesh(homeId: Double, name: String, promise: Promise) = todo(promise, "createSigMesh")
  override fun createTuyaMesh(homeId: Double, name: String, promise: Promise) = todo(promise, "createTuyaMesh")
  override fun getMeshList(homeId: Double, promise: Promise) = todo(promise, "getMeshList")

  override fun startMeshClient(meshId: String, searchTimeSec: Double) { /* intended: getThingSigMeshClient().initMesh+startClient */ }
  override fun stopMeshClient(meshId: String) { /* intended: getThingSigMeshClient().stopClient() */ }
  override fun searchSubDevices(meshId: String, timeoutSec: Double) { /* intended: startSearch()+SearchBuilder→emit onMeshDeviceFound */ }

  override fun activateSubDevice(meshId: String, mac: String, timeoutSec: Double, promise: Promise) =
    todo(promise, "activateSubDevice")
  override fun publishMeshDps(meshId: String, nodeId: String, pcc: String, dpsJson: String, promise: Promise) =
    todo(promise, "publishMeshDps")
  override fun multicastMeshDps(meshId: String, localId: String, pcc: String, dpsJson: String, promise: Promise) =
    todo(promise, "multicastMeshDps")

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}
}
