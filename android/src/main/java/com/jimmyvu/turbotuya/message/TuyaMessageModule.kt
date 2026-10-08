package com.jimmyvu.turbotuya.message

// TuyaMessage (Android) - verify trên SDK 7.5.6 (javap + bytecode jar). WIRED toàn bộ spec, trừ unregisterDevice
// (SDK không có API huỷ token - xem chỗ method).
//   msg  = ThingHomeSdk.getMessageInstance() (IThingMessage): list/detail/has-new/delete + TOÀN BỘ DND
//          (getDeviceDNDSetting/setDeviceDNDSetting/getDNDList/getOnceDNDList/add|modify(Once)DND/removeDNDWithTimerId).
//   push = ThingHomeSdk.getPushInstance() (IThingPush): registerDevice + push status (tổng + theo PushType).
// Enum (giá trị verbatim): MessageType MSG_REPORT=1 · MSG_FAMILY=2 · MSG_NOTIFY=3.
//   PushType PUSH_ALARM_SYSTEM=0 · PUSH_FAMILY=1 · PUSH_NOTIFY=2 · PUSH_MARKETING=4 (PUSH_ALARM=11/PHONE=9/SMS=10 là kênh mới).
// DND - cùng API cloud với iOS ThingSmartMessageSetting:
//   recurring = thing.m.device.alarm.nodisturb.{list,add,update,remove} v1.0 · startTime/endTime 'HH:mm', loops 7 ký tự.
//   once      = m.message.device.alarm.nodisturb.{list,add,update} v3.0 · 'YYYY-MM-DD HH:mm', SDK tự gán loops "0000000".
//   devIds gửi lên = chuỗi JSON {"devIds":[..],"allDevIds":bool}; list trả devIds = chuỗi JSON array.

import com.jimmyvu.turbotuya.NativeTuyaMessageSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.thingclips.smart.android.user.api.IBooleanCallback
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.bean.MessageHasNew
import com.thingclips.smart.home.sdk.callback.IThingResultCallback
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDataCallback
import com.thingclips.smart.sdk.bean.message.DeviceAlarmNotDisturbVO
import com.thingclips.smart.sdk.bean.message.MessageListBean
import com.thingclips.smart.sdk.bean.message.MessageType
import com.thingclips.smart.sdk.bean.push.PushStatusBean
import com.thingclips.smart.sdk.bean.push.PushType
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

// TuyaMessage - message center + push status + DND. Không phát event.
class TuyaMessageModule(reactContext: ReactApplicationContext) :
  NativeTuyaMessageSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaMessageSpec.NAME
    private const val ONCE_LOOPS = "0000000" // loops của DND một lần
  }

  // ---------- Callback helpers (reject = mã lỗi Tuya thật qua TuyaReject) ----------
  // Getter: resolve giá trị SDK trả.
  private fun boolCb(promise: Promise, errCode: String) = object : IThingDataCallback<Boolean> {
    override fun onSuccess(result: Boolean?) = promise.resolve(result ?: false)
    override fun onError(code: String?, message: String?) = TuyaReject.reject(promise, code ?: errCode, message)
  }

  // Setter/modify/remove: Boolean SDK trả chỉ là cờ thành công (true khi không lỗi), SDK iOS bỏ qua nó
  // → resolve giá trị cố định (trạng thái vừa set / true) để 2 nền tảng trả giống nhau.
  private fun doneCb(promise: Promise, value: Boolean, errCode: String) = object : IThingDataCallback<Boolean> {
    override fun onSuccess(result: Boolean?) = promise.resolve(value)
    override fun onError(code: String?, message: String?) = TuyaReject.reject(promise, code ?: errCode, message)
  }

  // add(Once)DNDWithStartTime: Long = timerId.
  private fun timerIdCb(promise: Promise, errCode: String) = object : IThingDataCallback<Long> {
    override fun onSuccess(result: Long?) = promise.resolve((result ?: 0L).toDouble())
    override fun onError(code: String?, message: String?) = TuyaReject.reject(promise, code ?: errCode, message)
  }

  private fun stringList(arr: ReadableArray): List<String> =
    (0 until arr.size()).mapNotNull { arr.getString(it) }.filter { it.isNotEmpty() }

  // ---------- Type mapping (không phân biệt hoa thường; giá trị lạ → fallback giống iOS) ----------
  private fun toMessageType(type: String): MessageType = when (type.lowercase()) {
    "alarm" -> MessageType.MSG_REPORT
    "family" -> MessageType.MSG_FAMILY
    else -> MessageType.MSG_NOTIFY
  }

  private fun msgTypeString(value: Int): String = when (value) {
    1, 4 -> "alarm" // 4 = MessageBean.MSG_TYPE_PRD_WARN - iOS cũng map 4 → alarm
    2 -> "family"
    else -> "notification"
  }

  // 'alarm' = PUSH_ALARM_SYSTEM (value 0): iOS getDevicePushStatus gửi type=0, docs Tuya ghi "0: Alert".
  // SDK 7.5.6 dời PUSH_ALARM sang 11 (kênh alarm mới) → KHÔNG dùng PUSH_ALARM để giữ khớp iOS.
  private fun toPushType(pushType: String): PushType = when (pushType.lowercase()) {
    "family" -> PushType.PUSH_FAMILY
    "notification" -> PushType.PUSH_NOTIFY
    "marketing" -> PushType.PUSH_MARKETING
    else -> PushType.PUSH_ALARM_SYSTEM
  }

  // ---------- Message page ----------
  // MessageListBean → TuyaMessagePage. fallbackType: list lọc theo type → gán type đã chuẩn hoá (giống iOS).
  private fun messagePage(result: MessageListBean?, off: Int, lim: Int, fallbackType: String?): WritableMap {
    val datas = result?.datas.orEmpty().filterNotNull()
    val list = Arguments.createArray()
    datas.forEach { m ->
      list.pushMap(
        Arguments.createMap().apply {
          putString("id", m.id ?: "")
          putString("msgType", fallbackType ?: msgTypeString(m.msgType))
          putString("msgSrcId", m.msgSrcId ?: "")
          putString("title", m.msgTypeContent ?: "") // Tuya: msgTypeContent = tiêu đề hiển thị
          putString("content", m.msgContent ?: "")
          putString("typeContent", m.msgTypeContent ?: "")
          putString("icon", m.icon ?: "")
          putString("dateTime", m.dateTime ?: "")
          putBoolean("hasNotRead", m.isHasNotRead)
        },
      )
    }
    val total = result?.totalCount ?: 0
    return Arguments.createMap().apply {
      putArray("list", list)
      putInt("offset", off)
      putInt("limit", lim)
      // Có totalCount thì dùng; không có (0) → suy ra như iOS: trang đủ limit = còn nữa.
      putBoolean("hasMore", if (total > 0) off + datas.size < total else datas.size >= lim)
    }
  }

  private fun pageCb(promise: Promise, off: Int, lim: Int, fallbackType: String?, errCode: String) =
    object : IThingDataCallback<MessageListBean> {
      override fun onSuccess(result: MessageListBean?) =
        promise.resolve(messagePage(result, off, lim, fallbackType))

      override fun onError(errorCode: String?, errorMessage: String?) =
        TuyaReject.reject(promise, errorCode ?: errCode, errorMessage)
    }

  // ---------- DND helpers ----------
  private fun isOnceLoops(loops: String?): Boolean = loops.isNullOrEmpty() || loops == ONCE_LOOPS

  // devIds đúng format SDK iOS gửi (disassemble ThingSmartMessageSetting) + docs Android:
  // {"devIds":[..],"allDevIds":bool}. omitEmptyIds: add once của iOS bỏ key devIds khi rỗng.
  private fun devIdsJson(allDevices: Boolean, devIds: ReadableArray, omitEmptyIds: Boolean = false): String {
    val ids = stringList(devIds)
    return JSONObject().apply {
      if (!(omitEmptyIds && ids.isEmpty())) put("devIds", JSONArray(ids))
      put("allDevIds", allDevices)
    }.toString()
  }

  // DeviceAlarmNotDisturbVO.devIds = chuỗi JSON array (iOS model parse bằng NSJSONSerialization);
  // phòng hờ object {"devIds":[..]} / chuỗi phân cách dấu phẩy.
  private fun parseDevIds(raw: String?): List<String> {
    val s = raw?.trim().orEmpty()
    if (s.isEmpty()) return emptyList()
    val arr = try {
      when {
        s.startsWith("[") -> JSONArray(s)
        s.startsWith("{") -> JSONObject(s).optJSONArray("devIds") ?: JSONArray()
        else -> null
      }
    } catch (e: JSONException) {
      null
    }
    if (arr != null) return (0 until arr.length()).map { arr.optString(it) }.filter { it.isNotEmpty() }
    return s.split(',').map { it.trim().trim('"') }.filter { it.isNotEmpty() }
  }

  // DeviceAlarmNotDisturbVO → TuyaDndPeriod (loops '' nếu once).
  private fun dndPeriod(vo: DeviceAlarmNotDisturbVO): WritableMap = Arguments.createMap().apply {
    val loops = vo.loops
    putDouble("id", vo.id.toDouble())
    putString("startTime", vo.startTime ?: "")
    putString("endTime", vo.endTime ?: "")
    putString("loops", if (isOnceLoops(loops)) "" else loops)
    putBoolean("allDevices", vo.isAllDevIds)
    putArray("devIds", Arguments.createArray().apply { parseDevIds(vo.devIds).forEach { pushString(it) } })
  }

  // once=false: bỏ entry loops "0000000" (phòng hờ list v1 lẫn once); once=true: getOnceDNDList đã lọc sẵn.
  private fun dndListCb(promise: Promise, once: Boolean) =
    object : IThingDataCallback<ArrayList<DeviceAlarmNotDisturbVO>> {
      override fun onSuccess(result: ArrayList<DeviceAlarmNotDisturbVO>?) {
        val arr = Arguments.createArray()
        result.orEmpty().filterNotNull().filter { isOnceLoops(it.loops) == once }.forEach { arr.pushMap(dndPeriod(it)) }
        promise.resolve(arr)
      }

      override fun onError(code: String?, message: String?) =
        TuyaReject.reject(promise, code ?: "get_dnd_list_error", message)
    }

  // ---------- Push token ----------
  override fun registerDevice(token: String, provider: String, promise: Promise) {
    // provider: "fcm" (Android) - iOS gán deviceToken.
    ThingHomeSdk.getPushInstance().registerDevice(token, provider, object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) = promise.reject(code ?: "register_device_error", error)
    })
  }

  // STUB có chủ đích: SDK 7.5.6 không có API huỷ đăng ký token (IThingPush chỉ có registerDevice →
  // b.m.device.register, và registerDevice("") bị chặn PUSH_ID_ERROR). iOS dùng setDeviceToken:nil.
  override fun unregisterDevice(promise: Promise) =
    TuyaReject.reject(
      promise,
      "not_implemented",
      "unregisterDevice is not available on Android: Tuya Android SDK 7.5.6 (IThingPush) has no API to " +
        "unregister a push token (only registerDevice, which rejects an empty token with PUSH_ID_ERROR). " +
        "Delete the FCM token on the app side (FirebaseMessaging.deleteToken()) instead.",
    )

  // ---------- Message list / detail ----------
  // thing.m.msg.list: getMessageList v3.0 · ByMsgType v4.0 · ByMsgSrcId v5.0 (iOS detail dùng 5.1 + keepOrig,
  // chỉ khác phần ảnh đính kèm - spec không trả attachment).
  override fun getMessageList(offset: Double, limit: Double, promise: Promise) {
    val off = maxOf(0, offset.toInt())
    val lim = maxOf(1, limit.toInt())
    ThingHomeSdk.getMessageInstance().getMessageList(
      off, lim, pageCb(promise, off, lim, null, "get_message_list_error"),
    )
  }

  override fun getMessageListByType(type: String, offset: Double, limit: Double, promise: Promise) {
    val off = maxOf(0, offset.toInt())
    val lim = maxOf(1, limit.toInt())
    val msgType = toMessageType(type)
    ThingHomeSdk.getMessageInstance().getMessageListByMsgType(
      off, lim, msgType, pageCb(promise, off, lim, msgTypeString(msgType.value), "get_message_list_error"),
    )
  }

  // Docs Tuya: chi tiết theo msgSrcId (devId) chỉ hỗ trợ MSG_REPORT (alarm).
  override fun getMessageDetailList(type: String, msgSrcId: String, offset: Double, limit: Double, promise: Promise) {
    val off = maxOf(0, offset.toInt())
    val lim = maxOf(1, limit.toInt())
    val msgType = toMessageType(type)
    ThingHomeSdk.getMessageInstance().getMessageListByMsgSrcId(
      off, lim, msgType, msgSrcId,
      pageCb(promise, off, lim, msgTypeString(msgType.value), "get_message_detail_error"),
    )
  }

  // ---------- Has-new / read / delete ----------
  // Verbatim SDK 7.5.6 (javap): requestMessageNew(IThingDataCallback<MessageHasNew>); MessageHasNew.isAlarm/isFamily/isNotification.
  override fun getMessageHasNew(promise: Promise) {
    ThingHomeSdk.getMessageInstance().requestMessageNew(
      object : IThingDataCallback<MessageHasNew> {
        override fun onSuccess(result: MessageHasNew?) {
          promise.resolve(
            Arguments.createMap().apply {
              putBoolean("alarm", result?.isAlarm ?: false)
              putBoolean("family", result?.isFamily ?: false)
              putBoolean("notification", result?.isNotification ?: false)
            },
          )
        }

        override fun onError(errorCode: String?, errorMessage: String?) =
          promise.reject(errorCode ?: "get_message_has_new_error", errorMessage)
      },
    )
  }
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

  // thing.m.msg.remove v2.0. Docs: srcIds = xoá cả nhóm alarm theo thiết bị, ids = xoá từng tin chi tiết
  // ("không dùng chung") → truyền nguyên như JS gửi; SDK bỏ list rỗng. Cả hai rỗng → no-op như iOS.
  override fun deleteMessagesByType(type: String, ids: ReadableArray, srcIds: ReadableArray, promise: Promise) {
    val msgIds = stringList(ids)
    val msgSrcIds = stringList(srcIds)
    if (msgIds.isEmpty() && msgSrcIds.isEmpty()) {
      promise.resolve(true)
      return
    }
    ThingHomeSdk.getMessageInstance().deleteMessageWithType(
      toMessageType(type).value, msgIds, msgSrcIds,
      object : IBooleanCallback {
        override fun onSuccess() = promise.resolve(true)
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "delete_messages_error", error)
      },
    )
  }

  // ---------- Push status ----------
  // thing.m.device.push.status.get (theo deviceId máy) → PushStatusBean.isPushEnable là String;
  // iOS đọc integerValue != 0 → coi "1"/số khác 0/"true" là bật.
  override fun getPushStatus(promise: Promise) {
    ThingHomeSdk.getPushInstance().getPushStatus(object : IThingResultCallback<PushStatusBean> {
      override fun onSuccess(result: PushStatusBean?) {
        val v = result?.isPushEnable?.trim().orEmpty()
        promise.resolve(v.equals("true", ignoreCase = true) || (v.toIntOrNull() ?: 0) != 0)
      }

      override fun onError(errorCode: String?, errorMessage: String?) =
        TuyaReject.reject(promise, errorCode ?: "push_status_error", errorMessage)
    })
  }

  override fun setPushStatus(open: Boolean, promise: Promise) {
    ThingHomeSdk.getPushInstance().setPushStatus(open, doneCb(promise, open, "set_push_status_error"))
  }

  // thing.m.msg.notice.switch.status / .setting (type = PushType.value) - y hệt iOS get/set*PushStatus.
  override fun getPushStatusByType(pushType: String, promise: Promise) {
    ThingHomeSdk.getPushInstance().getPushStatusByType(toPushType(pushType), boolCb(promise, "push_status_error"))
  }

  override fun setPushStatusByType(pushType: String, open: Boolean, promise: Promise) {
    ThingHomeSdk.getPushInstance().setPushStatusByType(
      toPushType(pushType), open, doneCb(promise, open, "push_status_error"),
    )
  }

  // ---------- Do-Not-Disturb ----------
  // Nhóm DND nằm ở IThingMessage (KHÔNG phải IThingPush).
  override fun getDndStatus(promise: Promise) {
    ThingHomeSdk.getMessageInstance().getDeviceDNDSetting(boolCb(promise, "dnd_status_error"))
  }

  override fun setDndStatus(open: Boolean, promise: Promise) {
    ThingHomeSdk.getMessageInstance().setDeviceDNDSetting(open, doneCb(promise, open, "dnd_status_error"))
  }

  override fun getDndList(promise: Promise) {
    ThingHomeSdk.getMessageInstance().getDNDList(dndListCb(promise, once = false))
  }

  override fun getOnceDndList(promise: Promise) {
    ThingHomeSdk.getMessageInstance().getOnceDNDList(dndListCb(promise, once = true))
  }

  override fun addDnd(
    startTime: String,
    endTime: String,
    loops: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) {
    // loops rỗng/"0000000" = DND một lần → entry lạc sang getOnceDndList. Chặn sớm như iOS.
    if (isOnceLoops(loops)) {
      TuyaReject.reject(
        promise,
        "invalid_param",
        "addDnd needs a weekly loops pattern (7 chars, at least one day set); use addOnceDnd for a one-time period.",
      )
      return
    }
    ThingHomeSdk.getMessageInstance().addDNDWithStartTime(
      startTime, endTime, devIdsJson(allDevices, devIds), loops, timerIdCb(promise, "add_dnd_error"),
    )
  }

  // SDK tự gán loops "0000000" + noDisturbType=1 (API v3).
  override fun addOnceDnd(
    startTime: String,
    endTime: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) {
    ThingHomeSdk.getMessageInstance().addOnceDNDWithStartTime(
      startTime, endTime, devIdsJson(allDevices, devIds, omitEmptyIds = true), timerIdCb(promise, "add_dnd_error"),
    )
  }

  // loops '' | "0000000" → sửa DND một lần (v3); còn lại → recurring (v1). Giống iOS.
  override fun modifyDnd(
    dndId: Double,
    startTime: String,
    endTime: String,
    loops: String,
    allDevices: Boolean,
    devIds: ReadableArray,
    promise: Promise,
  ) {
    val msg = ThingHomeSdk.getMessageInstance()
    val ids = devIdsJson(allDevices, devIds)
    val cb = doneCb(promise, true, "modify_dnd_error")
    if (isOnceLoops(loops)) {
      msg.modifyOnceDNDWithTimerId(dndId.toLong(), startTime, endTime, ids, cb)
    } else {
      msg.modifyDNDWithTimerId(dndId.toLong(), startTime, endTime, ids, loops, cb)
    }
  }

  // thing.m.device.alarm.nodisturb.remove - SDK chỉ có 1 API xoá, dùng cho cả recurring lẫn once.
  override fun removeDnd(dndId: Double, promise: Promise) {
    ThingHomeSdk.getMessageInstance().removeDNDWithTimerId(dndId.toLong(), doneCb(promise, true, "remove_dnd_error"))
  }
}
