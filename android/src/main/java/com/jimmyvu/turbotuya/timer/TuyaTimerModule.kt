package com.jimmyvu.turbotuya.timer

// Theo docs/research/tuya-home-sdk-device-control.md (mục timer, verbatim builder) - CHƯA build-verify.
// ⚠️ Verify package/import: ThingTimerBuilder, TimerDeviceTypeEnum, TimerUpdateEnum (com.thingclips.* có thể lệch);
//    và FORMAT của setActions(actionsJson) (note "Câu hỏi mở" - ThingTimerBuilder không có setTime, time nằm trong actions).
// getTimerList để TODO vì bean TimerTask chưa rõ field (map khi verify trên SDK thật).
//
// Intended: timer = ThingHomeSdk.getTimerInstance();
//   addTimer(ThingTimerBuilder, IResultCallback); updateTimer(ThingTimerBuilder, IResultCallback)
//   updateTimerStatus(devId, TimerDeviceTypeEnum, List<String> ids, TimerUpdateEnum, IResultCallback)
//   getTimerList(taskName, devId, TimerDeviceTypeEnum, IThingDataCallback<TimerTask>)

import com.jimmyvu.turbotuya.NativeTuyaTimerSpec
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.thingclips.smart.android.device.builder.ThingTimerBuilder
import com.thingclips.smart.android.device.enums.TimerDeviceTypeEnum
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.constant.TimerUpdateEnum
import com.thingclips.smart.sdk.api.IResultCallback
import org.json.JSONObject

// TuyaTimer - hẹn giờ / lịch cloud. Không phát event.
class TuyaTimerModule(reactContext: ReactApplicationContext) :
  NativeTuyaTimerSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaTimerSpec.NAME
  }

  private fun deviceType(bizType: String): TimerDeviceTypeEnum =
    if (bizType.equals("group", true)) TimerDeviceTypeEnum.GROUP else TimerDeviceTypeEnum.DEVICE

  private fun updateOp(op: String): TimerUpdateEnum = when (op.lowercase()) {
    "open" -> TimerUpdateEnum.OPEN
    "close" -> TimerUpdateEnum.CLOSE
    else -> TimerUpdateEnum.DELETE
  }

  private fun resultCb(promise: Promise, errCode: String) = object : IResultCallback {
    override fun onSuccess() = promise.resolve(null)
    override fun onError(code: String?, error: String?) = promise.reject(code ?: errCode, error)
  }

  // Lắp ThingTimerBuilder từ inputJson. ⚠️ actions format cần verify (time nằm trong actions).
  private fun builderFrom(inputJson: String): ThingTimerBuilder {
    val j = JSONObject(inputJson)
    val time = j.optString("time")
    val dps = j.optString("dpsJson", "{}")
    // Best-guess actions: [{ "time": "HH:mm", "dps": {...} }] - đổi theo format thật khi verify.
    val actions = "[{\"time\":\"$time\",\"dps\":$dps}]"
    return ThingTimerBuilder.Builder()
      .taskName(j.optString("taskName"))
      .devId(j.optString("bizId"))
      .deviceType(deviceType(j.optString("bizType", "device")))
      .actions(actions)
      .loops(j.optString("loops", "0000000"))
      .status(if (j.optBoolean("status", true)) 1 else 0)
      .appPush(j.optBoolean("appPush", false))
      .aliasName(j.optString("aliasName", ""))
      .build()
  }

  override fun addTimer(inputJson: String, promise: Promise) {
    try {
      ThingHomeSdk.getTimerInstance().addTimer(builderFrom(inputJson), resultCb(promise, "add_timer_error"))
    } catch (e: Throwable) {
      promise.reject("add_timer_error", e)
    }
  }

  override fun updateTimer(timerId: String, inputJson: String, promise: Promise) {
    try {
      // ⚠️ Gắn timerId vào builder cần verify (ThingTimerBuilder có setTimerId?); hiện build lại từ inputJson.
      ThingHomeSdk.getTimerInstance().updateTimer(builderFrom(inputJson), resultCb(promise, "update_timer_error"))
    } catch (e: Throwable) {
      promise.reject("update_timer_error", e)
    }
  }

  override fun removeTimer(
    taskName: String,
    bizId: String,
    bizType: String,
    timerIds: ReadableArray,
    promise: Promise,
  ) {
    val ids = (0 until timerIds.size()).mapNotNull { timerIds.getString(it) }
    ThingHomeSdk.getTimerInstance().updateTimerStatus(
      bizId, deviceType(bizType), ids, TimerUpdateEnum.DELETE, resultCb(promise, "remove_timer_error"),
    )
  }

  override fun updateTimerStatus(
    taskName: String,
    bizId: String,
    bizType: String,
    timerIds: ReadableArray,
    op: String,
    promise: Promise,
  ) {
    val ids = (0 until timerIds.size()).mapNotNull { timerIds.getString(it) }
    ThingHomeSdk.getTimerInstance().updateTimerStatus(
      bizId, deviceType(bizType), ids, updateOp(op), resultCb(promise, "update_timer_status_error"),
    )
  }

  override fun getTimerList(taskName: String, bizId: String, bizType: String, promise: Promise) {
    // Intended: getTimerInstance().getTimerList(taskName, bizId, deviceType, IThingDataCallback<TimerTask>)
    // → map TimerTask → TimerItem[]. Bean TimerTask field chưa rõ → TODO verify trên SDK thật.
    promise.reject(
      "not_implemented",
      "getTimerList chưa wire (bean TimerTask chưa verbatim) - xem docs/research/tuya-home-sdk-device-control.md.",
    )
  }
}
