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
  // ⚠️ SDK Android 7.5.x: IThingPush KHÔNG có nhóm API DND (getDeviceDNDSetting/setDeviceDNDSetting/
  //    addDNDWithStartTime/addOnceDNDWithStartTime/modifyDNDWithTimerId/removeDNDWithTimerId).
  //    Các method này có ở iOS (ThingSmartMessagePush) / bản SDK khác. Trên Android → stub tới khi
  //    xác định được API DND tương đương (xem docs/research/tuya-android-sdk-missing-modules.md).
  override fun getDndStatus(promise: Promise) =
    todo(promise, "getDndStatus (Android IThingPush không có getDeviceDNDSetting)")
  override fun setDndStatus(open: Boolean, promise: Promise) =
    todo(promise, "setDndStatus (Android IThingPush không có setDeviceDNDSetting)")
  override fun getDndList(promise: Promise) =
    todo(promise, "getDndList")
  override fun getOnceDndList(promise: Promise) =
    todo(promise, "getOnceDndList")

  override fun addDnd(
    startTime: String,
    endTime: String,
    loops: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) = todo(promise, "addDnd (Android IThingPush không có addDNDWithStartTime)")

  override fun addOnceDnd(
    startTime: String,
    endTime: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) = todo(promise, "addOnceDnd (Android IThingPush không có addOnceDNDWithStartTime)")

  override fun modifyDnd(
    dndId: Double,
    startTime: String,
    endTime: String,
    loops: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) = todo(promise, "modifyDnd (Android IThingPush không có modifyDNDWithTimerId)")

  override fun removeDnd(dndId: Double, promise: Promise) =
    todo(promise, "removeDnd (Android IThingPush không có removeDNDWithTimerId)")
}
