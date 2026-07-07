package com.jimmyvu.turbotuya.scene

// ⚠️ B7 - SKELETON có chủ đích. Scene SDK của Tuya (getSceneServiceInstance + NormalScene/SceneCondition/
// SceneAction/SavedScene/SceneChangeCallback + IResultCallback<T> generic + builder DeviceConditionBuilder...)
// thuộc API mới, PACKAGE class + cách lắp NormalScene CHƯA verbatim (xem docs/research/tuya-home-sdk-smart-scenes.md
// "Câu hỏi mở"). Không import blind để tránh vỡ compile toàn module. Mỗi method ghi rõ INTENDED CALL để wire trên
// máy có SDK thật. Khi wire: thêm import com.thingclips.smart.scene.* tương ứng + đổi todo() thành impl.
//
// Intended (Android, từ note verbatim):
//   svc = ThingHomeSdk.getSceneServiceInstance(); base = svc.baseService(); exec = svc.executeService()
//   getSceneList        -> base.getSimpleSceneAll(homeId, IResultCallback<List<NormalScene>>)  (lọc ruleGenre 1/2)
//   getSceneDetail      -> base.getSceneDetail(homeId, sceneId, IResultCallback<NormalScene>)  (serialize conditions/actions -> JSON)
//   saveScene/modify    -> base.saveSceneV2(homeId, NormalScene, IResultCallback<SavedScene>) / modifySceneV2(homeId, needClean, sceneId, NormalScene, cb)
//                          (lắp NormalScene: setName/setRuleGenre/setMatchType/setConditions(List<SceneCondition>)/setActions(List<SceneAction>)/setEnabled/setPreConditions)
//   deleteScene         -> base.deleteSceneWithHomeId(homeId, sceneId, IResultCallback<Boolean>)
//   executeScene        -> getSceneDetail -> exec.executeScene(NormalScene, IResultCallback)
//   enable/disable      -> base.enableAutomation/disableAutomation(sceneId, IResultCallback<Boolean>); enableAutomationWithTime(sceneId, time, cb)
//   listener            -> exec.registerDeviceMqttListener(SceneChangeCallback{onAdd/Update/Delete/Enable/DisableScene}) -> emit onSceneChange; unRegisterDeviceMqttListener()
//   build*              -> DeviceConditionBuilder/WeatherConditionBuilder/TimingConditionBuilder/GeofenceConditionBuilder.build() as ConditionBase;
//                          DeviceActionBuilder/DelayActionBuilder/LinkageRuleActionBuilder/NotifyActionBuilder.build() as ActionBase -> serialize JSON
//   helpers            -> condition/action device list + city list (xác minh API Android trong scene SDK)

import com.jimmyvu.turbotuya.NativeTuyaSceneSpec
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

// TuyaScene - tap-to-run + automation. Phát event onSceneChange. (skeleton; wire trên SDK thật)
class TuyaSceneModule(reactContext: ReactApplicationContext) :
  NativeTuyaSceneSpec(reactContext) {

  private val ctx = reactContext

  companion object {
    const val NAME = NativeTuyaSceneSpec.NAME
    private const val EVT_SCENE = "onSceneChange"
  }

  // Dùng khi wire SceneChangeCallback: emit({ type, sceneId }) lên JS.
  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  private fun todo(promise: Promise, what: String) {
    promise.reject(
      "not_implemented",
      "$what chưa wire (scene SDK chưa verbatim) - xem docs/research/tuya-home-sdk-smart-scenes.md + comment intended-call.",
    )
  }

  // ---------- List / detail ----------
  override fun getSceneList(homeId: Double, promise: Promise) = todo(promise, "getSceneList")
  override fun getSceneDetail(homeId: Double, sceneId: String, promise: Promise) = todo(promise, "getSceneDetail")

  // ---------- Create / modify / delete ----------
  override fun saveScene(homeId: Double, paramsJson: String, promise: Promise) =
    todo(promise, "saveScene")
  override fun modifyScene(homeId: Double, sceneId: String, paramsJson: String, promise: Promise) =
    todo(promise, "modifyScene")
  override fun deleteScene(homeId: Double, sceneId: String, promise: Promise) = todo(promise, "deleteScene")

  // ---------- Execute / automation ----------
  override fun executeScene(homeId: Double, sceneId: String, promise: Promise) = todo(promise, "executeScene")
  override fun enableAutomation(sceneId: String, promise: Promise) = todo(promise, "enableAutomation")
  override fun disableAutomation(sceneId: String, promise: Promise) = todo(promise, "disableAutomation")
  override fun enableAutomationWithTime(sceneId: String, durationMs: Double, promise: Promise) =
    todo(promise, "enableAutomationWithTime")

  // ---------- Builders (condition/action → JSON) ----------
  override fun buildDeviceCondition(devId: String, dpId: String, op: String, value: String, promise: Promise) =
    todo(promise, "buildDeviceCondition")
  override fun buildWeatherCondition(
    cityId: String,
    cityName: String,
    weatherType: String,
    op: String,
    value: String,
    promise: Promise,
  ) = todo(promise, "buildWeatherCondition")
  override fun buildTimerCondition(timeZoneId: String, loops: String, time: String, date: String, promise: Promise) =
    todo(promise, "buildTimerCondition")
  override fun buildGeofenceCondition(
    geoType: String,
    latitude: Double,
    longitude: Double,
    radius: Double,
    title: String,
    promise: Promise,
  ) = todo(promise, "buildGeofenceCondition")
  override fun buildDeviceAction(devId: String, dpId: String, value: String, promise: Promise) =
    todo(promise, "buildDeviceAction")
  override fun buildDelayAction(hours: Double, minutes: Double, seconds: Double, promise: Promise) =
    todo(promise, "buildDelayAction")
  override fun buildTriggerSceneAction(sceneId: String, sceneName: String, promise: Promise) =
    todo(promise, "buildTriggerSceneAction")
  override fun buildAutomationToggleAction(sceneId: String, enable: Boolean, promise: Promise) =
    todo(promise, "buildAutomationToggleAction")
  override fun buildNotificationAction(channel: String, promise: Promise) =
    todo(promise, "buildNotificationAction")

  // ---------- Helpers ----------
  override fun getConditionDeviceList(homeId: Double, promise: Promise) = todo(promise, "getConditionDeviceList")
  override fun getActionDeviceList(homeId: Double, promise: Promise) = todo(promise, "getActionDeviceList")
  override fun getCityListByCountryCode(countryCode: String, promise: Promise) = todo(promise, "getCityListByCountryCode")
  override fun getCityByLocation(latitude: Double, longitude: Double, promise: Promise) = todo(promise, "getCityByLocation")

  // ---------- Realtime listener (TODO: registerDeviceMqttListener → emit onSceneChange) ----------
  override fun registerSceneChangeListener() {}
  override fun unregisterSceneChangeListener() {}

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}
}
