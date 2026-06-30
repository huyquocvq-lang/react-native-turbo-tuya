package com.jimmyvu.turbotuya.message

// Theo docs/research/tuya-home-sdk-message-management.md + push-notifications (verbatim) — CHƯA build-verify.
// ⚠️ WIRE phần callback proven (registerDevice/setPushStatus/DND-write/deleteMessages). TODO phần cần enum/bean
//    chưa verbatim entry: MessageType(1/2/3), PushType(0/1/2/4), MessageListBean/MessageBean/MessageHasNew/PushStatusBean/
//    DeviceAlarmNotDisturbVO — ghi intended-call để wire trên SDK thật.
// Intended (Android): push = ThingHomeSdk.getPushInstance(); msg = ThingHomeSdk.getMessageInstance().
//   getMessageList(offset,limit, IThingDataCallback<MessageListBean>); getMessageListByMsgType(offset,limit,MessageType,cb)
//   requestMessageNew(IThingDataCallback<MessageHasNew>); getPushStatus(IThingResultCallback<PushStatusBean>)
//   getPushStatusByType(PushType,cb)/setPushStatusByType(PushType,bool,cb)
//   getDNDList/getOnceDNDList(IThingDataCallback<ArrayList<DeviceAlarmNotDisturbVO>>)

import com.jimmyvu.turbotuya.NativeTuyaMessageSpec
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.thingclips.smart.android.user.api.IBooleanCallback
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDataCallback

// TuyaMessage — message center + push status + DND. Không phát event.
class TuyaMessageModule(reactContext: ReactApplicationContext) :
  NativeTuyaMessageSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaMessageSpec.NAME
  }

  private fun todo(promise: Promise, what: String) {
    promise.reject(
      "not_implemented",
      "$what chưa wire (enum/bean chưa verbatim) — xem docs/research/tuya-home-sdk-message-management.md + intended-call.",
    )
  }

  // devIds → JSON Tuya: {"allDevIds":bool,"devIds":["id",...]}
  private fun devIdsJson(allDevices: Boolean, devIds: ReadableArray): String {
    val ids = (0 until devIds.size()).mapNotNull { devIds.getString(it) }
      .joinToString(",") { "\"$it\"" }
    return "{\"allDevIds\":$allDevices,\"devIds\":[$ids]}"
  }

  private fun boolCb(promise: Promise, errCode: String) = object : IThingDataCallback<Boolean> {
    override fun onSuccess(result: Boolean?) = promise.resolve(result ?: false)
    override fun onError(code: String?, message: String?) = promise.reject(code ?: errCode, message)
  }

  // ---------- Push token ----------
  override fun registerDevice(token: String, provider: String, promise: Promise) {
    // provider: "fcm" (Android) — iOS gán deviceToken. unregister: TODO.
    ThingHomeSdk.getPushInstance().registerDevice(token, provider, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) = promise.reject(code ?: "register_device_error", error)
    })
  }

  override fun unregisterDevice(promise: Promise) = todo(promise, "unregisterDevice")

  // ---------- Message list / detail ----------
  override fun getMessageList(offset: Double, limit: Double, promise: Promise) =
    todo(promise, "getMessageList") // intended: getMessageInstance().getMessageList(offset,limit,IThingDataCallback<MessageListBean>) → map
  override fun getMessageListByType(type: String, offset: Double, limit: Double, promise: Promise) =
    todo(promise, "getMessageListByType") // cần MessageType enum
  override fun getMessageDetailList(type: String, msgSrcId: String, offset: Double, limit: Double, promise: Promise) =
    todo(promise, "getMessageDetailList") // cần MessageType enum

  // ---------- Has-new / read / delete ----------
  override fun getMessageHasNew(promise: Promise) =
    todo(promise, "getMessageHasNew") // intended: requestMessageNew(IThingDataCallback<MessageHasNew>) → {alarm,family,notification}
  override fun markMessagesRead(type: String, ids: ReadableArray, promise: Promise) {
    // Android general message KHÔNG có markRead công khai (note) → no-op; iOS có readMessageWithReadRequestModel.
    promise.resolve(true)
  }
  override fun deleteMessages(ids: ReadableArray, promise: Promise) {
    val list = (0 until ids.size()).mapNotNull { ids.getString(it) }
    ThingHomeSdk.getMessageInstance().deleteMessages(list, object : IBooleanCallback {
      // IBooleanCallback.onSuccess() KHÔNG tham số (giống Auth login/logout) → resolve(true) khi xoá xong.
      override fun onSuccess() = promise.resolve(true)
      override fun onError(code: String?, error: String?) = promise.reject(code ?: "delete_messages_error", error)
    })
  }
  override fun deleteMessagesByType(type: String, ids: ReadableArray, srcIds: ReadableArray, promise: Promise) =
    todo(promise, "deleteMessagesByType") // cần msgType int

  // ---------- Push status ----------
  override fun getPushStatus(promise: Promise) =
    todo(promise, "getPushStatus") // intended: getPushStatus(IThingResultCallback<PushStatusBean>) — field tổng chưa rõ
  override fun setPushStatus(open: Boolean, promise: Promise) {
    ThingHomeSdk.getPushInstance().setPushStatus(open, boolCb(promise, "set_push_status_error"))
  }
  override fun getPushStatusByType(pushType: String, promise: Promise) =
    todo(promise, "getPushStatusByType") // cần PushType enum (0 alarm/1 family/2 notice/4 marketing)
  override fun setPushStatusByType(pushType: String, open: Boolean, promise: Promise) =
    todo(promise, "setPushStatusByType") // cần PushType enum

  // ---------- Do-Not-Disturb ----------
  override fun getDndStatus(promise: Promise) {
    ThingHomeSdk.getPushInstance().getDeviceDNDSetting(boolCb(promise, "get_dnd_error"))
  }
  override fun setDndStatus(open: Boolean, promise: Promise) {
    ThingHomeSdk.getPushInstance().setDeviceDNDSetting(open, boolCb(promise, "set_dnd_error"))
  }
  override fun getDndList(promise: Promise) =
    todo(promise, "getDndList") // intended: getDNDList(IThingDataCallback<ArrayList<DeviceAlarmNotDisturbVO>>) → map
  override fun getOnceDndList(promise: Promise) =
    todo(promise, "getOnceDndList")

  override fun addDnd(
    startTime: String,
    endTime: String,
    loops: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) {
    ThingHomeSdk.getPushInstance().addDNDWithStartTime(
      startTime, endTime, devIdsJson(allDevices, devIds), loops,
      object : IThingDataCallback<Long> {
        override fun onSuccess(result: Long?) = promise.resolve((result ?: 0L).toDouble())
        override fun onError(code: String?, message: String?) = promise.reject(code ?: "add_dnd_error", message)
      },
    )
  }

  override fun addOnceDnd(
    startTime: String,
    endTime: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) {
    ThingHomeSdk.getPushInstance().addOnceDNDWithStartTime(
      startTime, endTime, devIdsJson(allDevices, devIds),
      object : IThingDataCallback<Long> {
        override fun onSuccess(result: Long?) = promise.resolve((result ?: 0L).toDouble())
        override fun onError(code: String?, message: String?) = promise.reject(code ?: "add_once_dnd_error", message)
      },
    )
  }

  override fun modifyDnd(
    dndId: Double,
    startTime: String,
    endTime: String,
    loops: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) {
    ThingHomeSdk.getPushInstance().modifyDNDWithTimerId(
      dndId.toLong(), startTime, endTime, devIdsJson(allDevices, devIds), loops,
      boolCb(promise, "modify_dnd_error"),
    )
  }

  override fun removeDnd(dndId: Double, promise: Promise) {
    ThingHomeSdk.getPushInstance().removeDNDWithTimerId(dndId.toLong(), boolCb(promise, "remove_dnd_error"))
  }
}
