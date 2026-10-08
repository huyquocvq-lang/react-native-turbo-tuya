package com.jimmyvu.turbotuya.member

// B12 (P3) theo docs/research/tuya-home-sdk-home-management.md section E + F (verbatim).
// Toàn bộ method đã wire; chữ ký + API cloud verify trên bytecode jar SDK 7.5.6 (IThingHomeMember,
// IThingHomeManager.joinHomeByInviteCode, MemberWrapperBean.Builder). MemberBean KHÔNG có mobile/invitationCode
// → trả '' cho 2 field này. Bean lời mời (InviteMessageBean/InviteListResponseBean) nằm ở package nội bộ
// com.thingclips.sdk.home.bean và callback là IThingDataCallback raw → đọc qua fastjson (getter → key JSON).

import com.alibaba.fastjson.JSON
import com.jimmyvu.turbotuya.NativeTuyaMemberSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.bean.MemberBean
import com.thingclips.smart.home.sdk.bean.MemberWrapperBean
import com.thingclips.smart.home.sdk.callback.IThingGetMemberListCallback
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.api.IThingDataCallback
import org.json.JSONArray
import org.json.JSONObject

// TuyaMember - thành viên home + lời mời + chuyển chủ. Không phát event.
class TuyaMemberModule(reactContext: ReactApplicationContext) :
  NativeTuyaMemberSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaMemberSpec.NAME
  }

  private fun result(promise: Promise, errCode: String) = object : IResultCallback {
    override fun onSuccess() = promise.resolve(null)
    override fun onError(code: String?, error: String?) = promise.reject(code ?: errCode, error)
  }

  // Method mới: reject qua TuyaReject (shape {code, message, domain}), giữ nguyên mã/lời lỗi SDK.
  private fun sdkResult(promise: Promise, errCode: String) = object : IResultCallback {
    override fun onSuccess() = promise.resolve(null)
    override fun onError(code: String?, error: String?) = TuyaReject.reject(promise, code ?: errCode, error)
  }

  private fun memberToMap(bean: MemberBean): WritableMap {
    val m = Arguments.createMap()
    m.putDouble("memberId", bean.memberId.toDouble())
    m.putString("account", bean.account ?: "")
    m.putString("name", bean.nickName ?: "")
    m.putBoolean("admin", bean.isAdmin)
    m.putDouble("role", bean.role.toDouble())
    m.putDouble("status", bean.memberStatus.toDouble())
    m.putString("headPic", bean.headPic ?: "")
    m.putString("mobile", "") // MemberBean (7.5.6) không có mobile
    m.putString("invitationCode", "") // MemberBean (7.5.6) không có invitationCode
    m.putString("uid", bean.uid ?: "")
    return m
  }

  // Bean nội bộ SDK → org.json qua fastjson (key = tên getter: invitationCode, invitationId, dealStatus...).
  private fun beanToJson(bean: Any?): JSONObject =
    runCatching { JSONObject(JSON.toJSONString(bean)) }.getOrDefault(JSONObject())

  private fun beansToJson(list: Any?): List<JSONObject> {
    val arr = runCatching { JSONArray(JSON.toJSONString(list)) }.getOrDefault(JSONArray())
    return (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
  }

  // Shape lời mời chuẩn hoá 2 nền tảng (iOS map từ ThingSmartHomeInvitationRecordModel cùng key).
  // validTime: hiệu lực mã mời (giờ); dealStatus: 1 chờ / 2 đồng ý / 3 từ chối.
  private fun invitationToJson(j: JSONObject): JSONObject = JSONObject()
    .put("invitationId", j.optLong("invitationId"))
    .put("invitationCode", j.optString("invitationCode"))
    .put("name", j.optString("name"))
    .put("role", j.optInt("role"))
    .put("dealStatus", j.optInt("dealStatus"))
    .put("validTime", j.optLong("validTime"))

  private fun invitationResult(invitationId: Long, code: String): WritableMap =
    Arguments.createMap().apply {
      putDouble("invitationId", invitationId.toDouble())
      putString("code", code)
    }

  // ---------- Member CRUD ----------
  override fun queryMembers(homeId: Double, promise: Promise) {
    ThingHomeSdk.getMemberInstance().queryMemberList(
      homeId.toLong(),
      object : IThingGetMemberListCallback {
        override fun onSuccess(members: MutableList<MemberBean>?) {
          val arr = Arguments.createArray()
          members?.forEach { arr.pushMap(memberToMap(it)) }
          promise.resolve(arr)
        }
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "member_list_error", error)
      },
    )
  }

  override fun addMember(
    homeId: Double,
    account: String,
    countryCode: String,
    name: String,
    role: Double,
    admin: Boolean,
    autoAccept: Boolean,
    promise: Promise,
  ) {
    // MemberWrapperBean.Builder → m.life.group.member.add v7.0 (verify bytecode 7.5.6). SDK chỉ gửi groupId, name,
    // role (≠ -999), autoAccept, userAccount+countryCode (khi cả 2 khác rỗng); cờ `admin` KHÔNG được gửi.
    // Server chỉ trả memberId → role/admin/status trong kết quả suy từ request (admin = role ≥ 1;
    // status = autoAccept ? 2 đã nhận : 1 chờ xác nhận).
    val wrapper = MemberWrapperBean.Builder()
      .setHomeId(homeId.toLong())
      .setAccount(account)
      .setCountryCode(countryCode)
      .setNickName(name)
      .setRole(role.toInt())
      .setAdmin(admin)
      .setAutoAccept(autoAccept)
      .build()
    ThingHomeSdk.getMemberInstance().addMember(
      wrapper,
      object : IThingDataCallback<MemberBean> {
        override fun onSuccess(result: MemberBean?) {
          val m = memberToMap(result ?: MemberBean())
          m.putString("account", account)
          m.putString("name", name)
          m.putDouble("role", role)
          m.putBoolean("admin", role.toInt() >= 1)
          m.putDouble("status", if (autoAccept) 2.0 else 1.0)
          promise.resolve(m)
        }
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "add_member_error", error)
      },
    )
  }

  override fun updateMember(
    homeId: Double,
    memberId: Double,
    name: String,
    admin: Boolean,
    promise: Promise,
  ) {
    // Overload đơn giản: updateMember(memberId, name, admin, IResultCallback) - không đổi role.
    ThingHomeSdk.getMemberInstance()
      .updateMember(memberId.toLong(), name, admin, result(promise, "update_member_error"))
  }

  override fun removeMember(homeId: Double, memberId: Double, promise: Promise) {
    ThingHomeSdk.getMemberInstance()
      .removeMember(memberId.toLong(), result(promise, "remove_member_error"))
  }

  // ---------- Invitation ----------
  override fun createInvitation(homeId: Double, promise: Promise) {
    val id = homeId.toLong()
    // Overload có role → m.life.group.invitation.code.add v2.0 (cùng API iOS dùng); mời với vai trò member (0).
    // SDK chỉ trả InviteMessageBean {invitationCode, invitationMsgContent} - KHÔNG có invitationId.
    ThingHomeSdk.getMemberInstance().getInvitationMessage(
      id, 0, null,
      object : IThingDataCallback<Any?> {
        override fun onSuccess(result: Any?) {
          val code = beanToJson(result).optString("invitationCode")
          if (code.isEmpty()) {
            TuyaReject.reject(promise, "create_invitation_error", "SDK returned no invitation code")
            return
          }
          resolveInvitationId(id, code, promise)
        }
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "create_invitation_error", error)
      },
    )
  }

  // Lấy invitationId bằng cách tra danh sách lời mời theo mã vừa tạo. Mã đã tạo thành công nên KHÔNG reject
  // khi tra lỗi/không thấy → invitationId = 0 (JS gọi getInvitationList để lấy lại).
  private fun resolveInvitationId(homeId: Long, code: String, promise: Promise) {
    ThingHomeSdk.getMemberInstance().getInvitationList(
      homeId,
      object : IThingDataCallback<Any?> {
        override fun onSuccess(result: Any?) {
          val match = beansToJson(result).firstOrNull { it.optString("invitationCode") == code }
          promise.resolve(invitationResult(match?.optLong("invitationId") ?: 0L, code))
        }
        override fun onError(errCode: String?, error: String?) =
          promise.resolve(invitationResult(0L, code))
      },
    )
  }

  override fun getInvitationList(homeId: Double, promise: Promise) {
    // → m.life.group.invitation.list v2.0 (ArrayList<InviteListResponseBean>) → JSON mảng shape chuẩn hoá.
    ThingHomeSdk.getMemberInstance().getInvitationList(
      homeId.toLong(),
      object : IThingDataCallback<Any?> {
        override fun onSuccess(result: Any?) {
          val out = JSONArray()
          beansToJson(result).forEach { out.put(invitationToJson(it)) }
          promise.resolve(out.toString())
        }
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "invitation_list_error", error)
      },
    )
  }

  override fun cancelInvitation(invitationId: Double, promise: Promise) {
    ThingHomeSdk.getMemberInstance()
      .cancelMemberInvitationCode(invitationId.toLong(), result(promise, "cancel_invitation_error"))
  }

  override fun updateInvitedMember(
    invitationId: Double,
    memberName: String,
    memberRole: Double,
    promise: Promise,
  ) {
    ThingHomeSdk.getMemberInstance().updateInvitedMember(
      invitationId.toLong(), memberName, memberRole.toInt(),
      result(promise, "update_invited_error"),
    )
  }

  override fun joinHomeByCode(code: String, promise: Promise) {
    // 7.5.6: joinHomeByInviteCode nằm trên IThingHomeManager (KHÔNG phải IThingHomeMember)
    // → thing.m.group.invitation.member.add {invitationCode} - tương đương iOS joinHomeWithInvitationCode:.
    ThingHomeSdk.getHomeManagerInstance().joinHomeByInviteCode(code, sdkResult(promise, "join_home_error"))
  }

  override fun processInvitation(homeId: Double, accept: Boolean, promise: Promise) {
    ThingHomeSdk.getMemberInstance()
      .processInvitation(homeId.toLong(), accept, result(promise, "process_invitation_error"))
  }

  // ---------- Transfer owner ----------
  override fun transferHomeOwner(homeId: Double, memberId: Double, promise: Promise) {
    // 7.5.6 có sẵn IThingHomeMember.transferOwner(homeId, memberId) (không cần Biz FamilyManagerCoreKit)
    // → m.life.group.owner.transfer {gid = homeId, memberId} (thứ tự param verify bytecode).
    ThingHomeSdk.getMemberInstance()
      .transferOwner(homeId.toLong(), memberId.toLong(), sdkResult(promise, "transfer_owner_error"))
  }
}
