package com.jimmyvu.turbotuya.device

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
import org.json.JSONObject

// TuyaDevice — điều khiển Data Points (DP) + lắng nghe trạng thái. Phát event onDeviceStatus.
class TuyaDeviceModule(reactContext: ReactApplicationContext) :
  NativeTuyaDeviceSpec(reactContext) {

  private val ctx = reactContext
  private val devices = mutableMapOf<String, IThingDevice>()

  companion object {
    const val NAME = NativeTuyaDeviceSpec.NAME
    private const val EVT_DEVICE = "onDeviceStatus"
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

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

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // ---------- helpers ----------
  private fun deviceOf(devId: String): IThingDevice =
    devices.getOrPut(devId) { ThingHomeSdk.newDeviceInstance(devId) }
}
