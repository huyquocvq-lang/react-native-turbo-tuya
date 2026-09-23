package com.jimmyvu.turbotuya.timer

// Hẹn giờ / lịch cloud. Chữ ký + bean đã VERIFY bằng javap trên SDK thật (thingsmart 7.5.6, 2026-09-23):
//   IThingCommonTimer: addTimer(ThingTimerBuilder, IResultCallback) · updateTimer(...) ·
//     getTimerList(task, devId, TimerDeviceTypeEnum, IThingDataCallback<TimerTask>) ·
//     updateTimerStatus(devId, type, List<String> ids, TimerUpdateEnum, cb) ·
//     updateCategoryTimerStatus(task, devId, type, TimerUpdateEnum, cb)   ← xoá/đổi theo CẢ TASK
//   ThingTimerBuilder.Builder: taskName/devId/deviceType/actions/loops/status/appPush/aliasName/timerId
//   TimerTask.getTimerList() → ArrayList<Timer>; Timer{timerId, time, loops, status, dpId, value, remark, date}
//
// FORMAT `actions` (trước đây là best-guess): là JSON của DpTimerPointBean → `[{"time":"HH:mm","dps":{...}}]`.
// Căn cứ: bean nội bộ `com.thingclips.sdk.timer.bean.DpTimerPointBean{ String time; JSONObject dps; }` và API
// cũ `IThingTimer.addTimerWithTask(task, devId, time, Map<String,Object> dps, loops, …)` - cùng một cặp
// (time, dps). Vẫn phải xác nhận lần chạy thật đầu tiên trên thiết bị.
//
// Hợp đồng với JS (dùng chung cho iOS): thao tác theo TASK NAME. `timerIds` rỗng = áp dụng cho cả task
// (iOS chỉ xoá được theo task), có id thì áp dụng đúng các id đó.

import com.jimmyvu.turbotuya.NativeTuyaTimerSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.thingclips.smart.android.device.builder.ThingTimerBuilder
import com.thingclips.smart.android.device.enums.TimerDeviceTypeEnum
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.constant.TimerUpdateEnum
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDataCallback
import com.thingclips.smart.sdk.bean.Timer
import com.thingclips.smart.sdk.bean.TimerTask
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

  private fun ids(timerIds: ReadableArray): List<String> =
    (0 until timerIds.size()).mapNotNull { timerIds.getString(it) }

  /** Lắp ThingTimerBuilder từ inputJson (time + dps gói trong `actions`, xem ghi chú đầu file). */
  private fun builderFrom(inputJson: String, timerId: Long? = null): ThingTimerBuilder {
    val j = JSONObject(inputJson)
    val time = j.optString("time")
    val dps = j.optString("dpsJson", "{}")
    val actions = "[{\"time\":\"$time\",\"dps\":$dps}]"
    val b = ThingTimerBuilder.Builder()
      .taskName(j.optString("taskName"))
      .devId(j.optString("bizId"))
      .deviceType(deviceType(j.optString("bizType", "device")))
      .actions(actions)
      .loops(j.optString("loops", "0000000"))
      .status(if (j.optBoolean("status", true)) ThingTimerBuilder.STATUS_OPEN else ThingTimerBuilder.STATUS_CLOSE)
      .appPush(j.optBoolean("appPush", false))
      .aliasName(j.optString("aliasName", ""))
    if (timerId != null) b.timerId(timerId)
    return b.build()
  }

  /** `Timer.value` về dạng CHUỖI ("true"/"false"/"40") → trả đúng kiểu để JS so được với dps đã gửi. */
  private fun dpValue(raw: String?): Any {
    val v = raw?.trim().orEmpty()
    return when {
      v.equals("true", true) -> true
      v.equals("false", true) -> false
      v.toLongOrNull() != null -> v.toLong()
      v.toDoubleOrNull() != null -> v.toDouble()
      else -> v
    }
  }

  /**
   * Timer của Android mang dpId + value rời (iOS trả sẵn dps) → dựng lại `{dpId: value}` cho khớp hợp đồng.
   * `dpId`/`value` bị SDK đánh deprecated nhưng **không có field thay thế** trong bean `Timer` (javap 7.5.6),
   * và timer của app luôn chỉ mang ĐÚNG 1 DP nên vẫn đọc đủ. Đổi khi SDK cho bean mới có `dps`.
   */
  @Suppress("DEPRECATION")
  private fun dpsJsonOf(t: Timer): String = try {
    JSONObject().put(t.dpId.orEmpty(), dpValue(t.value)).toString()
  } catch (e: Throwable) {
    "{}"
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
      val id = timerId.toLongOrNull()
      if (id == null) {
        promise.reject("invalid_param", "updateTimer cần timerId dạng số")
        return
      }
      ThingHomeSdk.getTimerInstance()
        .updateTimer(builderFrom(inputJson, id), resultCb(promise, "update_timer_error"))
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
    val list = ids(timerIds)
    val timer = ThingHomeSdk.getTimerInstance()
    val cb = resultCb(promise, "remove_timer_error")
    // Không truyền id ⇒ xoá CẢ TASK (hợp đồng chung với iOS `removeTimerWithTask`).
    if (list.isEmpty()) {
      timer.updateCategoryTimerStatus(taskName, bizId, deviceType(bizType), TimerUpdateEnum.DELETE, cb)
    } else {
      timer.updateTimerStatus(bizId, deviceType(bizType), list, TimerUpdateEnum.DELETE, cb)
    }
  }

  override fun updateTimerStatus(
    taskName: String,
    bizId: String,
    bizType: String,
    timerIds: ReadableArray,
    op: String,
    promise: Promise,
  ) {
    val list = ids(timerIds)
    val timer = ThingHomeSdk.getTimerInstance()
    val cb = resultCb(promise, "update_timer_status_error")
    if (list.isEmpty()) {
      timer.updateCategoryTimerStatus(taskName, bizId, deviceType(bizType), updateOp(op), cb)
    } else {
      timer.updateTimerStatus(bizId, deviceType(bizType), list, updateOp(op), cb)
    }
  }

  override fun getTimerList(taskName: String, bizId: String, bizType: String, promise: Promise) {
    ThingHomeSdk.getTimerInstance().getTimerList(
      taskName,
      bizId,
      deviceType(bizType),
      object : IThingDataCallback<TimerTask> {
        override fun onSuccess(result: TimerTask?) {
          val arr = Arguments.createArray()
          result?.timerList?.forEach { t ->
            val m = Arguments.createMap()
            m.putString("timerId", t.timerId.orEmpty())
            m.putString("time", t.time.orEmpty())
            m.putString("loops", t.loops.orEmpty())
            m.putBoolean("status", t.isOpen)
            m.putString("dpsJson", dpsJsonOf(t))
            m.putString("aliasName", t.remark.orEmpty())
            arr.pushMap(m)
          }
          promise.resolve(arr)
        }

        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "timer_list_error", error)
      },
    )
  }
}
