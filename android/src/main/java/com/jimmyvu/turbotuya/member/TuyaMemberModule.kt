package com.jimmyvu.turbotuya.member

// B12 (P3) theo docs/research/tuya-home-sdk-home-management.md section E + F (verbatim) — CHƯA build-verify.
// ⚠️ WIRE phần callback/param proven (query/remove/update/processInvitation/joinByCode/cancel/updateInvited).
//    TODO phần cần bean/Biz chưa verbatim: addMember (MemberWrapperBean construction chưa rõ),
//    createInvitation + getInvitationList (bean InvitationMessageBean field chưa rõ),
//    transferHomeOwner (Biz FamilyManagerCoreKit — package chưa verbatim).
// ⚠️ Verify import/getter: MemberBean (getMemberId/getAccount/getName/isAdmin/getRole/getHeadPic/getDealStatus/
//    getInvitationCode/getMobile), IThingGetMemberListCallback.

import com.jimmyvu.turbotuya.NativeTuyaMemberSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.bean.MemberBean
import com.thingclips.smart.home.sdk.callback.IThingGetMemberListCallback
import com.thingclips.smart.sdk.api.IResultCallback

// TuyaMember — thành viên home + lời mời + chuyển chủ. Không phát event.
class TuyaMemberModule(reactContext: ReactApplicationContext) :
  NativeTuyaMemberSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaMemberSpec.NAME
  }

  private fun todo(promise: Promise, what: String, why: String) {
    promise.reject("not_implemented", "$what chưa wire ($why) — xem docs/research/tuya-home-sdk-home-management.md")
  }

  private fun result(promise: Promise, errCode: String) = object : IResultCallback {
    override fun onSuccess() = promise.resolve(null)
    override fun onError(code: String?, error: String?) = promise.reject(code ?: errCode, error)
  }

  private fun memberToMap(bean: MemberBean): WritableMap {
    val m = Arguments.createMap()
    m.putDouble("memberId", bean.memberId.toDouble())
    m.putString("account", bean.account ?: "")
    m.putString("name", bean.name ?: "")
    m.putBoolean("admin", bean.isAdmin)
    m.putDouble("role", bean.role.toDouble())
    m.putDouble("status", bean.dealStatus.toDouble())
    m.putString("headPic", bean.headPic ?: "")
    m.putString("mobile", bean.mobile ?: "")
    m.putString("invitationCode", bean.invitationCode ?: "")
    return m
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
    // intended: getMemberInstance().addMember(MemberWrapperBean{homeId,account,countryCode,nickName=name,role,admin,
    //           autoAccept}, IThingDataCallback<MemberBean>) → memberToMap. Construction MemberWrapperBean chưa verbatim.
    todo(promise, "addMember", "MemberWrapperBean construction chưa rõ")
  }

  override fun updateMember(
    homeId: Double,
    memberId: Double,
    name: String,
    admin: Boolean,
    promise: Promise,
  ) {
    // Overload đơn giản: updateMember(memberId, name, admin, IResultCallback) — không đổi role.
    ThingHomeSdk.getMemberInstance()
      .updateMember(memberId.toLong(), name, admin, result(promise, "update_member_error"))
  }

  override fun removeMember(homeId: Double, memberId: Double, promise: Promise) {
    ThingHomeSdk.getMemberInstance()
      .removeMember(memberId.toLong(), result(promise, "remove_member_error"))
  }

  // ---------- Invitation ----------
  override fun createInvitation(homeId: Double, promise: Promise) {
    // intended: getInvitationMessage(homeId, IThingDataCallback) → InvitationMessageBean {invitationId, code}.
    todo(promise, "createInvitation", "bean InvitationMessageBean field chưa rõ")
  }

  override fun getInvitationList(homeId: Double, promise: Promise) {
    // intended: getInvitationList(homeId, IThingDataCallback) → serialize JSON. Bean field chưa rõ.
    todo(promise, "getInvitationList", "bean field chưa rõ")
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
    ThingHomeSdk.getMemberInstance()
      .joinHomeByInviteCode(code, result(promise, "join_home_error"))
  }

  override fun processInvitation(homeId: Double, accept: Boolean, promise: Promise) {
    ThingHomeSdk.getMemberInstance()
      .processInvitation(homeId.toLong(), accept, result(promise, "process_invitation_error"))
  }

  // ---------- Transfer owner ----------
  override fun transferHomeOwner(homeId: Double, memberId: Double, promise: Promise) {
    // intended (Biz): FamilyManagerCoreKit.getFamilyUseCase().transferOwner(homeId, memberId,
    //   IFamilyDataCallback<Boolean>). Package FamilyManagerCoreKit chưa verbatim → wire trên SDK thật.
    todo(promise, "transferHomeOwner", "Biz FamilyManagerCoreKit package chưa verbatim")
  }
}
