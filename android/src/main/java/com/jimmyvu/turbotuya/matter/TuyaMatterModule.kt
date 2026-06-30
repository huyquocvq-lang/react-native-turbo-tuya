package com.jimmyvu.turbotuya.matter

// B14 (P3) theo docs/research/tuya-home-sdk-device-pairing.md §5 (Matter, verbatim Android) — CHƯA build-verify.
// SKELETON có chủ đích (như B7/B13): Matter dùng API RIÊNG + nhiều bean native giữ trạng thái giữa các call
// (SetupPayload, ConnectResult, controllerPtr/devicePtr) + cần init Matter SDK + entitlement (iOS) + KHÔNG obfuscate.
// Package CHƯA verbatim → TODO-reject + intended-call để wire trên SDK thật. Giữ event plumbing cho tương lai.
//
// Intended (Android, note §5):
//   val m = ThingHomeSdk.getMatterDevActivatorInstance()
//   parseSetupCode: m.parseSetupCode("MT:...") -> SetupPayload {version,vendorId,productId,setupPinCode,discriminator} (GIỮ lại)
//   connectDevice:  ConnectDeviceBuilder().setSetupPayload(payload).setSpaceId(homeId).setTimeout(ms)
//                   .setConnectCallback(IThingConnectDeviceCallback{onFound(bool,MatterDeviceTypeEnum)/onConnected(ConnectResult)/onError});
//                   m.connectDevice(builder)  (GIỮ ConnectResult)
//   commissionDevice: CommissioningParameters.Builder().connectDeviceResult(cr).setupPayload(p).spaceId(homeId)
//                     .token(token).ssid(ssid).password(pwd).timeOut(ms).build();
//                     m.commissionDevice(params, MatterActivatorCallback{onActivatorSuccess(DeviceBean)/onError/onDeviceAttestationFailed(ctrlPtr,devPtr,code)→emit onMatterAttestation})
//   discovery: ThingHomeSdk.getDiscoveryActivatorInstance().startDiscovery(IDynamicDiscoveryListener{onFound(ThingMatterDiscovery)→emit onMatterDeviceFound/onError}); stopDiscovery()
//   attestation: m.continueCommissioningDevice(ctrlPtr, devPtr, ignoreAttestationFailure); m.cancelActivator()

import com.jimmyvu.turbotuya.NativeTuyaMatterSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

// TuyaMatter — pairing Matter (skeleton, API riêng). Phát event onMatterDeviceFound/onMatterAttestation/onMatterError.
class TuyaMatterModule(reactContext: ReactApplicationContext) :
  NativeTuyaMatterSpec(reactContext) {

  private val ctx = reactContext

  companion object {
    const val NAME = NativeTuyaMatterSpec.NAME
    private const val EVT_FOUND = "onMatterDeviceFound"
    private const val EVT_ATTEST = "onMatterAttestation"
    private const val EVT_ERROR = "onMatterError"
  }

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit(event, params)
  }

  private fun todo(promise: Promise, what: String) {
    promise.reject(
      "not_implemented",
      "$what chưa wire (Matter API riêng chưa verbatim) — xem docs/research/tuya-home-sdk-device-pairing.md §5 + intended-call.",
    )
  }

  override fun parseSetupCode(code: String, promise: Promise) = todo(promise, "parseSetupCode")
  override fun connectDevice(homeId: Double, timeoutSec: Double, promise: Promise) = todo(promise, "connectDevice")
  override fun commissionDevice(
    homeId: Double,
    token: String,
    ssid: String,
    password: String,
    timeoutSec: Double,
    promise: Promise,
  ) = todo(promise, "commissionDevice")

  override fun startDiscovery() {
    val m = Arguments.createMap()
    m.putString("code", "not_implemented")
    m.putString("message", "Matter discovery chưa wire (API riêng chưa verbatim)")
    emit(EVT_ERROR, m)
  }

  override fun stopDiscovery() { /* intended: getDiscoveryActivatorInstance().stopDiscovery() */ }
  override fun continueCommissioning(ignoreAttestationFailure: Boolean) { /* intended: continueCommissioningDevice(ctrlPtr,devPtr,ignore) */ }
  override fun cancelActivator() { /* intended: getMatterDevActivatorInstance().cancelActivator() */ }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}
}
