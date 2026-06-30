package com.jimmyvu.turbotuya.ota

// Module mới theo docs/research/tuya-home-sdk-device-management.md (mục OTA) — CHƯA build-verify.
// ⚠️ Lần build đầu verify chữ ký + package: IThingOTAService, IGetOtaInfoCallback, IDevOTAListener,
// UpgradeInfoBean (note ghi rõ tên callback nhưng tham số chính xác cần đối chiếu Javadoc 7.5.x).

import com.jimmyvu.turbotuya.NativeTuyaOtaSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IDevOTAListener
import com.thingclips.smart.sdk.api.IGetOtaInfoCallback
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDataCallback
import com.thingclips.smart.sdk.api.IThingOTAService
import com.thingclips.smart.sdk.bean.UpgradeInfoBean

// TuyaOta — cập nhật firmware. Phát event onOtaProgress/onOtaStatusChanged/onOtaSuccess/onOtaFailure.
class TuyaOtaModule(reactContext: ReactApplicationContext) :
  NativeTuyaOtaSpec(reactContext) {

  private val ctx = reactContext
  private val services = mutableMapOf<String, IThingOTAService>()

  companion object {
    const val NAME = NativeTuyaOtaSpec.NAME
    private const val EVT_PROGRESS = "onOtaProgress"
    private const val EVT_STATUS = "onOtaStatusChanged"
    private const val EVT_SUCCESS = "onOtaSuccess"
    private const val EVT_FAILURE = "onOtaFailure"
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  // OTA service per device + đăng ký listener 1 lần (event bridge lên JS).
  private fun otaOf(devId: String): IThingOTAService =
    services.getOrPut(devId) {
      ThingHomeSdk.newOTAServiceInstance(devId).apply {
        // ⚠️ Chữ ký IDevOTAListener (đặc biệt onStatusChanged) cần verify trên SDK thật.
        registerDevOTAListener(object : IDevOTAListener {
          override fun onStatusChanged(otaType: Int, status: Int) {
            emit(EVT_STATUS, evt(devId).apply { putDouble("type", otaType.toDouble()); putDouble("status", status.toDouble()) })
          }
          override fun onProgress(otaType: Int, progress: Int) {
            emit(EVT_PROGRESS, evt(devId).apply { putDouble("type", otaType.toDouble()); putDouble("progress", progress.toDouble()) })
          }
          override fun onSuccess(otaType: Int) {
            emit(EVT_SUCCESS, evt(devId).apply { putDouble("type", otaType.toDouble()) })
          }
          override fun onFailure(otaType: Int, code: String?, error: String?) {
            emit(EVT_FAILURE, evt(devId).apply {
              putDouble("type", otaType.toDouble())
              putString("code", code ?: "ota_error")
              putString("message", error ?: "")
            })
          }
          override fun onTimeout(otaType: Int) {
            emit(EVT_FAILURE, evt(devId).apply {
              putDouble("type", otaType.toDouble())
              putString("code", "timeout")
              putString("message", "OTA timeout")
            })
          }
        })
      }
    }

  private fun evt(devId: String): WritableMap =
    Arguments.createMap().apply { putString("devId", devId) }

  override fun checkFirmwareUpgrade(devId: String, promise: Promise) {
    otaOf(devId).getFirmwareUpgradeInfo(object : IGetOtaInfoCallback {
      override fun onSuccess(list: MutableList<UpgradeInfoBean>?) {
        val arr = Arguments.createArray()
        list?.forEach { arr.pushMap(upgradeToMap(it)) }
        promise.resolve(arr)
      }
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "ota_info_error", error)
    })
  }

  override fun startFirmwareUpgrade(devId: String, types: ReadableArray, promise: Promise) {
    val wanted = (0 until types.size()).map { types.getDouble(it).toInt() }.toSet()
    val service = otaOf(devId)
    // Lấy danh sách bean rồi lọc theo type cần nâng (rỗng = tất cả type có thể nâng).
    service.getFirmwareUpgradeInfo(object : IGetOtaInfoCallback {
      override fun onSuccess(list: MutableList<UpgradeInfoBean>?) {
        val all = list ?: mutableListOf()
        val sel = if (wanted.isEmpty()) all else all.filter { wanted.contains(it.type) }
        if (sel.isEmpty()) { promise.reject("no_upgrade", "Không có firmware phù hợp để nâng"); return }
        service.startFirmwareUpgrade(ArrayList(sel)) // void → kết quả qua IDevOTAListener
        promise.resolve(null)
      }
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "ota_info_error", error)
    })
  }

  override fun cancelFirmwareUpgrade(devId: String, otaType: Double, promise: Promise) {
    otaOf(devId).cancelFirmwareUpgrade(otaType.toInt(), object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "ota_cancel_error", error)
    })
  }

  override fun confirmWarningUpgrade(devId: String, isContinue: Boolean, promise: Promise) {
    try {
      otaOf(devId).confirmWarningUpgradeTask(devId, isContinue) // void
      promise.resolve(null)
    } catch (e: Throwable) {
      promise.reject("ota_confirm_error", e)
    }
  }

  override fun getAutoUpgradeSwitch(devId: String, promise: Promise) {
    otaOf(devId).getAutoUpgradeSwitchState(object : IThingDataCallback<Int> {
      override fun onSuccess(result: Int?) = promise.resolve((result ?: 0).toDouble())
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "ota_switch_error", error)
    })
  }

  override fun setAutoUpgradeSwitch(devId: String, state: Double, promise: Promise) {
    otaOf(devId).changeAutoUpgradeSwitchState(state.toInt(), object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "ota_switch_error", error)
    })
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // Dọn OTA service + listener khi RN instance huỷ (reload/unmount) → tránh leak + crash
  // "JS module after React instance destroyed" (note device-management #8: OTA cần onDestroy).
  override fun invalidate() {
    super.invalidate()
    services.values.forEach { runCatching { it.onDestroy() } }
    services.clear()
  }

  // ---------- helpers ----------
  private fun upgradeToMap(b: UpgradeInfoBean): WritableMap {
    val m = Arguments.createMap()
    m.putDouble("type", b.type.toDouble())
    m.putString("typeDesc", b.typeDesc ?: "")
    m.putString("currentVersion", b.currentVersion ?: "")
    m.putString("version", b.version ?: "")
    m.putDouble("upgradeStatus", b.upgradeStatus.toDouble())
    m.putDouble("upgradeType", b.upgradeType.toDouble())
    m.putString("fileSize", b.fileSize ?: "")
    m.putDouble("controlType", b.controlType.toDouble())
    m.putBoolean("canUpgrade", b.isCanUpgrade)
    m.putString("desc", b.desc ?: "")
    return m
  }
}
