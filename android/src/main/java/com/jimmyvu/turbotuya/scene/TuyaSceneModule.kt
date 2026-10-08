package com.jimmyvu.turbotuya.scene

// TuyaScene (Android) - tap-to-run + automation qua scene SDK mới (ThingHomeSdk.getSceneServiceInstance()).
// Chữ ký VERIFY bằng javap trên SDK thật (thingsmart 7.5.6) + doc Tuya "Smart Scenes"/"Create Scene" (Android):
//   baseService(): getSimpleSceneAll · getSceneDetail · saveSceneV2 → SavedScene · modifySceneV2(homeId, needCleanGidSid,
//     sceneId, NormalScene) · deleteSceneWithHomeId · enableAutomation / disableAutomation / enableAutomationWithTime
//   executeService(): executeScene(NormalScene, sdk IResultCallback) · registerDeviceMqttListener(SceneChangeCallback)
//   deviceService(): getConditionDeviceAll → List<DeviceBean> · getActionDeviceAll → ActionDeviceGroup
//   conditionService(): getLocalCityAll(countryCode) · getLocalByCoordinate(lon, lat)  ← chú ý thứ tự lon trước
//   Builder: Device/Weather/Timing/GeofenceConditionBuilder → ConditionBase; Device/Delay/LinkageRule/NotifyActionBuilder → ActionBase
//
// HỢP ĐỒNG JSON (build* ↔ save/modify ↔ getSceneDetail): mỗi phần tử = JSON fastjson của chính bean SDK
// (SceneCondition / SceneAction / PreCondition). Đây cũng là định dạng SDK post lên cloud (saveSceneV2 đặt nguyên NormalScene
// vào `ruleExpr`; bean có @JSONType(ignores=...) cho đúng mục đích này). Round-trip toJSONString → parseObject đã test trên JVM.
// conditionsJson/actionsJson/preConditionsJson = JSON array; phần tử là object HOẶC chính chuỗi build* trả về (cả hai đều nhận).
// JS coi chuỗi là opaque: JSON iOS (YYModel) KHÁC Android - không trộn chuỗi giữa 2 nền tảng.
//
// Giá trị DP (op/value): kiểu lấy theo schema cache của thiết bị (bool/value/enum/string/raw); chưa có schema (home chưa load)
// thì đoán từ chuỗi: "true"/"false" → bool, số nguyên → value, còn lại → enum. Value = số nguyên THÔ (chưa chia scale).

import com.alibaba.fastjson.JSON
import com.alibaba.fastjson.JSONArray
import com.alibaba.fastjson.JSONObject
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.jimmyvu.turbotuya.NativeTuyaSceneSpec
import com.jimmyvu.turbotuya.common.TuyaReject
import com.thingclips.scene.core.bean.ActionBase
import com.thingclips.scene.core.bean.ConditionBase
import com.thingclips.scene.core.enumerate.CondType
import com.thingclips.scene.core.enumerate.ExprType
import com.thingclips.scene.core.protocol.b.usualimpl.DelayActionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.DeviceActionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.DeviceConditionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.GeofenceConditionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.LinkageRuleActionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.NotifyActionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.TimingConditionBuilder
import com.thingclips.scene.core.protocol.b.usualimpl.WeatherConditionBuilder
import com.thingclips.scene.core.protocol.expr.Rule
import com.thingclips.scene.core.protocol.expr.usualimpl.BoolRule
import com.thingclips.scene.core.protocol.expr.usualimpl.EnumRule
import com.thingclips.scene.core.protocol.expr.usualimpl.RawRule
import com.thingclips.scene.core.protocol.expr.usualimpl.ValueRule
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.scene.api.IResultCallback
import com.thingclips.smart.scene.api.ISceneService
import com.thingclips.smart.scene.api.service.SceneChangeCallback
import com.thingclips.smart.scene.model.NormalScene
import com.thingclips.smart.scene.model.SavedScene
import com.thingclips.smart.scene.model.action.SceneAction
import com.thingclips.smart.scene.model.condition.LocationCity
import com.thingclips.smart.scene.model.condition.SceneCondition
import com.thingclips.smart.scene.model.constant.WeatherType
import com.thingclips.smart.scene.model.device.ActionDeviceGroup
import com.thingclips.smart.scene.model.edit.PreCondition
import com.thingclips.smart.sdk.bean.DeviceBean
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt
import com.thingclips.smart.sdk.api.IResultCallback as SdkResultCallback

// TuyaScene - tap-to-run + automation. Phát event onSceneChange ({ type, sceneId }).
class TuyaSceneModule(reactContext: ReactApplicationContext) :
  NativeTuyaSceneSpec(reactContext) {

  private val ctx = reactContext
  private var sceneListener: SceneChangeCallback? = null

  companion object {
    const val NAME = NativeTuyaSceneSpec.NAME
    private const val EVT_SCENE = "onSceneChange"
    private const val RULE_TAP_TO_RUN = 1
    private const val RULE_AUTOMATION = 2
    private val VALUE_OPS = setOf("==", "<", ">", "<=", ">=")
  }

  /** Lỗi tham số phía JS → reject `invalid_param` (không phải lỗi SDK). */
  private class InvalidParam(message: String) : Exception(message)

  private fun bad(message: String): Nothing = throw InvalidParam(message)

  private fun svc(): ISceneService = ThingHomeSdk.getSceneServiceInstance()
    ?: throw IllegalStateException("Scene service unavailable (Tuya SDK not initialized?)")

  private fun emit(event: String, params: WritableMap?) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  /** Exception đồng bộ (parse JSON, SDK chưa init...) → reject thay vì crash bridge. */
  private inline fun guard(promise: Promise, code: String, block: () -> Unit) {
    try {
      block()
    } catch (e: InvalidParam) {
      TuyaReject.reject(promise, "invalid_param", e.message)
    } catch (e: Throwable) {
      TuyaReject.reject(promise, code, e.message ?: e.javaClass.simpleName)
    }
  }

  /**
   * Callback scene SDK → Promise. Lỗi SDK giữ nguyên code/message thật. T là type param (erased) nên
   * onSuccess(null) không bị Kotlin unbox/null-check → lambda nhận Any? và tự ép kiểu.
   */
  private fun <T> sceneCb(promise: Promise, fallbackCode: String, onOk: (Any?) -> Unit): IResultCallback<T> =
    object : IResultCallback<T> {
      override fun onSuccess(result: T) {
        try {
          onOk(result)
        } catch (e: InvalidParam) {
          TuyaReject.reject(promise, "invalid_param", e.message)
        } catch (e: Throwable) {
          TuyaReject.reject(promise, fallbackCode, e.message ?: e.javaClass.simpleName)
        }
      }

      override fun onError(errorCode: String?, errorMessage: String?) =
        TuyaReject.reject(promise, errorCode ?: fallbackCode, errorMessage ?: "Tuya SDK error ($fallbackCode)")
    }

  // ---------- Mapping kết quả ----------
  /** ruleGenre thiếu (0) → suy ra như doc Tuya: không có condition = tap-to-run. */
  private fun genreOf(s: NormalScene): Int = when (s.ruleGenre) {
    RULE_TAP_TO_RUN, RULE_AUTOMATION -> s.ruleGenre
    else -> if (s.conditions.isNullOrEmpty()) RULE_TAP_TO_RUN else RULE_AUTOMATION
  }

  /** 1 = any (mặc định khi list rút gọn không mang matchType), 2 = all. */
  private fun matchTypeOf(s: NormalScene): Int = if (s.matchType == 2) 2 else 1

  private fun summaryOf(s: NormalScene): WritableMap = Arguments.createMap().apply {
    putString("sceneId", s.id ?: "")
    putString("name", s.name ?: "")
    putInt("ruleGenre", genreOf(s))
    putBoolean("enabled", s.isEnabled)
    putInt("matchType", matchTypeOf(s))
    putString("displayColor", s.displayColor ?: "")
    putString("coverIcon", s.coverIcon ?: "")
  }

  private fun detailOf(s: NormalScene, fallbackId: String): WritableMap = Arguments.createMap().apply {
    putString("sceneId", s.id?.takeIf { it.isNotEmpty() } ?: fallbackId)
    putString("name", s.name ?: "")
    putInt("ruleGenre", genreOf(s))
    putBoolean("enabled", s.isEnabled)
    putInt("matchType", matchTypeOf(s))
    putString("conditionsJson", JSON.toJSONString(s.conditions ?: emptyList<SceneCondition>()))
    putString("actionsJson", JSON.toJSONString(s.actions ?: emptyList<SceneAction>()))
    putString("preConditionsJson", JSON.toJSONString(s.preConditions ?: emptyList<PreCondition>()))
  }

  private fun savedOf(saved: SavedScene?, fallbackId: String, fallbackName: String?, fallbackGenre: Int): WritableMap =
    Arguments.createMap().apply {
      putString("sceneId", saved?.ruleId?.takeIf { it.isNotEmpty() } ?: fallbackId)
      putString("name", saved?.name ?: fallbackName ?: "")
      putInt("ruleGenre", saved?.ruleGenre?.takeIf { it == RULE_TAP_TO_RUN || it == RULE_AUTOMATION } ?: fallbackGenre)
    }

  private fun deviceItems(list: List<*>?): WritableArray = Arguments.createArray().apply {
    list.orEmpty().filterIsInstance<DeviceBean>().forEach { d ->
      pushMap(Arguments.createMap().apply {
        putString("devId", d.getDevId() ?: "")
        putString("name", d.getName() ?: "")
      })
    }
  }

  private fun cityOf(c: LocationCity): WritableMap = Arguments.createMap().apply {
    putString("cityId", c.cityId ?: "")
    putString("cityName", c.city ?: "")
  }

  // ---------- paramsJson (save/modify) ----------
  /** Key vắng mặt = null → modify giữ nguyên giá trị cũ của scene. */
  private class SceneParams(
    val name: String?,
    val ruleGenre: Int?,
    val matchType: Int?,
    val background: String?,
    val conditions: List<SceneCondition>?,
    val actions: List<SceneAction>?,
    val preConditions: List<PreCondition>?,
  )

  private fun parseParams(paramsJson: String): SceneParams {
    val j: JSONObject = try {
      JSON.parseObject(paramsJson)
    } catch (e: Throwable) {
      null
    } ?: bad("paramsJson must be a JSON object")
    // null = vắng mặt (giống iOS NSNull).
    fun int(key: String): Int? = when (val v = j[key]) {
      null -> null
      is Number -> v.toInt()
      else -> v.toString().trim().toIntOrNull() ?: bad("$key must be a number")
    }
    fun str(key: String): String? = j[key] as? String
    val p = SceneParams(
      name = str("name"),
      ruleGenre = int("ruleGenre"),
      matchType = int("matchType"),
      background = str("background"),
      conditions = if (j.containsKey("conditionsJson")) parseList(j["conditionsJson"], SceneCondition::class.java, "conditionsJson") else null,
      actions = if (j.containsKey("actionsJson")) parseList(j["actionsJson"], SceneAction::class.java, "actionsJson") else null,
      preConditions = if (j.containsKey("preConditionsJson")) parseList(j["preConditionsJson"], PreCondition::class.java, "preConditionsJson") else null,
    )
    if (p.ruleGenre != null && p.ruleGenre != RULE_TAP_TO_RUN && p.ruleGenre != RULE_AUTOMATION) bad("ruleGenre must be 1 (tap-to-run) or 2 (automation)")
    if (p.matchType != null && p.matchType != 1 && p.matchType != 2) bad("matchType must be 1 (any) or 2 (all)")
    return p
  }

  /** Nhận chuỗi JSON array (hoặc array thật); phần tử là object hoặc chuỗi JSON do build* trả về. */
  private fun <T> parseList(raw: Any?, clazz: Class<T>, field: String): List<T> {
    val arr: List<Any?> = when (raw) {
      null -> emptyList()
      is JSONArray -> raw
      is String -> if (raw.isBlank()) emptyList() else try {
        JSON.parseArray(raw) ?: JSONArray()
      } catch (e: Throwable) {
        bad("$field is not a valid JSON array")
      }
      else -> bad("$field must be a JSON array string")
    }
    return arr.mapIndexed { i, e ->
      try {
        when (e) {
          is String -> JSON.parseObject(e, clazz)
          is JSONObject -> JSON.parseObject(e.toJSONString(), clazz)
          else -> null
        }
      } catch (t: Throwable) {
        null
      } ?: bad("$field[$i] is not a valid object")
    }
  }

  /** Gán các field có mặt trong params; tap-to-run không mang condition (iOS SDK cũng tự bỏ). */
  @Suppress("DEPRECATION") // NormalScene.background bị SDK đánh deprecated nhưng vẫn serialize key `background` (spec cần).
  private fun applyParams(s: NormalScene, p: SceneParams) {
    p.name?.let { s.name = it }
    p.ruleGenre?.let { s.ruleGenre = it }
    p.matchType?.let { s.matchType = it }
    p.background?.takeIf { it.isNotEmpty() }?.let { s.background = it }
    p.conditions?.let { s.conditions = ArrayList(it) }
    p.actions?.let { s.actions = ArrayList(it) }
    p.preConditions?.let { s.preConditions = ArrayList(it) }
    if (s.ruleGenre == RULE_TAP_TO_RUN) s.conditions = ArrayList()
  }

  private fun validateScene(s: NormalScene) {
    if (s.name.isNullOrBlank()) bad("name is required")
    if (s.actions.isNullOrEmpty()) bad("actionsJson needs at least 1 action")
    if (s.ruleGenre == RULE_AUTOMATION && s.conditions.isNullOrEmpty()) bad("automation (ruleGenre 2) needs at least 1 condition")
  }

  // ---------- Giá trị DP ----------
  private fun deviceOf(devId: String): DeviceBean? = try {
    ThingHomeSdk.getDataInstance().getDeviceBean(devId)
  } catch (e: Throwable) {
    null
  }

  /** Kiểu DP theo schema cache: bool/value/enum/string/raw/bitmap; null khi chưa có schema. */
  private fun dpTypeOf(dev: DeviceBean?, dpId: String): String? {
    val schema = try {
      dev?.getSchemaMap()?.get(dpId)
    } catch (e: Throwable) {
      null
    } ?: return null
    if (schema.getType().equals("raw", ignoreCase = true)) return "raw"
    return schema.getSchemaType()?.lowercase(Locale.ROOT)?.takeIf { it.isNotEmpty() }
  }

  private fun sniffType(value: String): String = when {
    value.trim().equals("true", true) || value.trim().equals("false", true) -> "bool"
    value.trim().toLongOrNull() != null -> "value"
    else -> "enum"
  }

  private fun parseBool(v: String): Boolean = when (v.trim().lowercase(Locale.ROOT)) {
    "true", "1" -> true
    "false", "0" -> false
    else -> bad("invalid bool value '$v'")
  }

  private fun parseInt(v: String): Int =
    v.trim().toIntOrNull() ?: bad("value must be an integer (raw DP value, before scale): '$v'")

  private fun opOf(op: String): String = op.trim().ifEmpty { "==" }

  private fun requireEq(op: String, kind: String) {
    if (op != "==") bad("$kind only supports op '==' (got '$op')")
  }

  private fun requireValueOp(op: String) {
    if (op !in VALUE_OPS) bad("op must be one of ${VALUE_OPS.joinToString()} (got '$op')")
  }

  private fun json(o: Any): String = JSON.toJSONString(o)

  // ---------- List / detail ----------
  override fun getSceneList(homeId: Double, promise: Promise) = guard(promise, "scene_list_error") {
    svc().baseService().getSimpleSceneAll(homeId.toLong(), sceneCb(promise, "scene_list_error") { r ->
      val arr = Arguments.createArray()
      (r as? List<*>).orEmpty().filterIsInstance<NormalScene>().forEach { arr.pushMap(summaryOf(it)) }
      promise.resolve(arr)
    })
  }

  override fun getSceneDetail(homeId: Double, sceneId: String, promise: Promise) = guard(promise, "scene_detail_error") {
    if (sceneId.isBlank()) bad("sceneId is required")
    svc().baseService().getSceneDetail(homeId.toLong(), sceneId, sceneCb(promise, "scene_detail_error") { r ->
      val s = r as? NormalScene
      if (s == null) {
        TuyaReject.reject(promise, "scene_not_found", "Scene $sceneId not found")
      } else {
        promise.resolve(detailOf(s, sceneId))
      }
    })
  }

  // ---------- Create / modify / delete ----------
  override fun saveScene(homeId: Double, paramsJson: String, promise: Promise) = guard(promise, "save_scene_error") {
    val p = parseParams(paramsJson)
    val genre = p.ruleGenre ?: if (p.conditions.isNullOrEmpty()) RULE_TAP_TO_RUN else RULE_AUTOMATION
    val scene = NormalScene()
    scene.ruleGenre = genre
    scene.matchType = p.matchType ?: 1
    scene.isEnabled = true // automation mới phải bật sẵn
    scene.conditions = ArrayList()
    scene.preConditions = ArrayList()
    applyParams(scene, p)
    validateScene(scene)
    svc().baseService().saveSceneV2(homeId.toLong(), scene, sceneCb(promise, "save_scene_error") { r ->
      promise.resolve(savedOf(r as? SavedScene, "", scene.name, genre))
    })
  }

  // Sửa trên bản chi tiết mới nhất (giữ enabled/displayColor/statusConditions...), chỉ đè key có trong paramsJson.
  override fun modifyScene(homeId: Double, sceneId: String, paramsJson: String, promise: Promise) =
    guard(promise, "modify_scene_error") {
      if (sceneId.isBlank()) bad("sceneId is required")
      val p = parseParams(paramsJson)
      val hid = homeId.toLong()
      svc().baseService().getSceneDetail(hid, sceneId, sceneCb(promise, "modify_scene_error") { r ->
        val s = r as? NormalScene
        if (s == null) {
          TuyaReject.reject(promise, "scene_not_found", "Scene $sceneId not found")
          return@sceneCb
        }
        applyParams(s, p)
        validateScene(s)
        svc().baseService().modifySceneV2(hid, false, sceneId, s, sceneCb(promise, "modify_scene_error") { r2 ->
          promise.resolve(savedOf(r2 as? SavedScene, sceneId, s.name, genreOf(s)))
        })
      })
    }

  override fun deleteScene(homeId: Double, sceneId: String, promise: Promise) = guard(promise, "delete_scene_error") {
    svc().baseService().deleteSceneWithHomeId(homeId.toLong(), sceneId, sceneCb(promise, "delete_scene_error") { r ->
      promise.resolve((r as? Boolean) ?: true)
    })
  }

  // ---------- Execute / automation ----------
  // executeScene cần NormalScene đầy đủ (SDK tự chọn chạy local/LAN hay cloud) → lấy chi tiết trước.
  override fun executeScene(homeId: Double, sceneId: String, promise: Promise) = guard(promise, "execute_scene_error") {
    svc().baseService().getSceneDetail(homeId.toLong(), sceneId, sceneCb(promise, "execute_scene_error") { r ->
      val s = r as? NormalScene
      if (s == null) {
        TuyaReject.reject(promise, "scene_not_found", "Scene $sceneId not found")
        return@sceneCb
      }
      svc().executeService().executeScene(s, object : SdkResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          TuyaReject.reject(promise, code ?: "execute_scene_error", error ?: "Tuya SDK error (execute_scene_error)")
      })
    })
  }

  override fun enableAutomation(sceneId: String, promise: Promise) = guard(promise, "enable_scene_error") {
    svc().baseService().enableAutomation(sceneId, sceneCb(promise, "enable_scene_error") { r ->
      promise.resolve((r as? Boolean) ?: true)
    })
  }

  override fun disableAutomation(sceneId: String, promise: Promise) = guard(promise, "disable_scene_error") {
    svc().baseService().disableAutomation(sceneId, sceneCb(promise, "disable_scene_error") { r ->
      promise.resolve((r as? Boolean) ?: true)
    })
  }

  // ⚠️ Đơn vị `time` của SDK KHÔNG được doc ghi rõ (Int, gửi `thing.m.linkage.rule.enable` v2.0 {ruleId, time}).
  // Giả định GIÂY (quy ước thời lượng của Tuya) → durationMs / 1000. Xác nhận trên thiết bị thật.
  override fun enableAutomationWithTime(sceneId: String, durationMs: Double, promise: Promise) =
    guard(promise, "enable_scene_error") {
      val seconds = durationMs / 1000.0
      if (seconds.isNaN() || seconds < 1 || seconds > Int.MAX_VALUE) bad("durationMs must be >= 1000")
      svc().baseService().enableAutomationWithTime(sceneId, seconds.toInt(), sceneCb(promise, "enable_scene_error") { r ->
        promise.resolve((r as? Boolean) ?: true)
      })
    }

  // ---------- Builders (condition/action → JSON) ----------
  override fun buildDeviceCondition(devId: String, dpId: String, op: String, value: String, promise: Promise) =
    guard(promise, "build_condition_error") {
      if (devId.isBlank() || dpId.isBlank()) bad("devId and dpId are required")
      val dev = deviceOf(devId)
      val type = dpTypeOf(dev, dpId) ?: sniffType(value)
      val operator = opOf(op)
      var simpleMatch = false
      val rule: Rule = when (type) {
        "bool" -> {
          requireEq(operator, "bool DP")
          BoolRule.newInstance(dpId, parseBool(value), ExprType.DEVICE)
        }
        "value" -> {
          requireValueOp(operator)
          ValueRule.newInstance(dpId, operator, parseInt(value), ExprType.DEVICE)
        }
        "enum" -> {
          requireEq(operator, "enum DP")
          if (value.isBlank()) bad("value is required")
          EnumRule.newInstance(dpId, value.trim(), ExprType.DEVICE)
        }
        // string/raw: biểu thức [["$dpX"]] (báo bất kỳ giá trị) + condType SIMPLE_MATCH theo doc; value bỏ qua.
        "string", "raw" -> {
          simpleMatch = true
          RawRule.newInstance(dpId, ExprType.DEVICE)
        }
        else -> bad("DP $dpId of type '$type' is not supported as a condition")
      }
      val base = DeviceConditionBuilder().setDevId(devId).setDpId(dpId).setRule(rule).build() as ConditionBase
      if (simpleMatch) base.condType = CondType.SIMPLE_MATCH.type
      val cond = SceneCondition(base)
      dev?.getName()?.let { cond.entityName = it }
      dev?.getIconUrl()?.let { cond.iconUrl = it }
      promise.resolve(json(cond))
    }

  // weatherType = WeatherType.type: temp · humidity · condition · pm25 · aqi · sunsetrise · windSpeed.
  // temp/windSpeed là số (°C, m/s) → op so sánh; còn lại là enum (vd condition 'sunny') → op '=='.
  override fun buildWeatherCondition(
    cityId: String,
    cityName: String,
    weatherType: String,
    op: String,
    value: String,
    promise: Promise,
  ) = guard(promise, "build_condition_error") {
    if (cityId.isBlank()) bad("cityId is required")
    val wt = WeatherType.getByType(weatherType.trim()) ?: bad("unsupported weatherType '$weatherType'")
    if (wt == WeatherType.WEATHER_TYPE_SUN_TIMER) bad("weatherType 'sunsetriseTimer' is not supported by buildWeatherCondition")
    val operator = opOf(op)
    val builder = if (WeatherType.valueTypeArray.contains(wt)) {
      requireValueOp(operator)
      WeatherConditionBuilder(cityId, cityName, WeatherConditionBuilder.entityType, wt, operator, parseInt(value))
    } else {
      requireEq(operator, "weather '${wt.type}'")
      if (value.isBlank()) bad("value is required")
      WeatherConditionBuilder(cityId, cityName, WeatherConditionBuilder.entityType, wt, null, value.trim())
    }
    if (wt == WeatherType.WEATHER_TYPE_TEMP) builder.setTempUnit("celsius")
    if (wt == WeatherType.WEATHER_TYPE_WIND) builder.setWindSpeedUnit("m/s")
    val cond = SceneCondition(builder.build() as ConditionBase)
    cond.entityName = cityName
    promise.resolve(json(cond))
  }

  // loops: 7 ký tự CN→T7 ('0000000' = một lần, cần date). time 'HH:mm'. date 'yyyyMMdd' (rỗng = hôm nay theo timeZoneId).
  override fun buildTimerCondition(timeZoneId: String, loops: String, time: String, date: String, promise: Promise) =
    guard(promise, "build_condition_error") {
      val tz = timeZoneId.trim().ifEmpty { TimeZone.getDefault().id }
      if (!Regex("[01]{7}").matches(loops)) bad("loops must be 7 chars of 0/1 (Sunday→Saturday)")
      if (!Regex("([01]\\d|2[0-3]):[0-5]\\d").matches(time)) bad("time must be HH:mm")
      val day = date.trim().ifEmpty {
        SimpleDateFormat("yyyyMMdd", Locale.US).apply { timeZone = TimeZone.getTimeZone(tz) }.format(Date())
      }
      if (!Regex("\\d{8}").matches(day)) bad("date must be yyyyMMdd")
      val base = TimingConditionBuilder().setTimeZoneId(tz).setLoops(loops).setTime(time).setDate(day).build() as ConditionBase
      val cond = SceneCondition(base)
      cond.exprDisplay = time
      promise.resolve(json(cond))
    }

  // ⚠️ Chỉ build condition. Đăng ký geofence với hệ điều hành (extService().addGeofence sau khi lưu) KHÔNG làm ở đây.
  override fun buildGeofenceCondition(
    geoType: String,
    latitude: Double,
    longitude: Double,
    radius: Double,
    title: String,
    promise: Promise,
  ) = guard(promise, "build_condition_error") {
    val type = when (geoType.trim().lowercase(Locale.ROOT)) {
      "reach", "enter" -> "enter"
      "exit", "leave" -> "exit"
      "inside", "outside" -> geoType.trim().lowercase(Locale.ROOT)
      else -> bad("geoType must be 'reach' or 'exit'")
    }
    if (latitude.isNaN() || latitude < -90 || latitude > 90 || longitude.isNaN() || longitude < -180 || longitude > 180) {
      bad("latitude/longitude out of range")
    }
    if (radius.isNaN() || radius < 1) bad("radius must be >= 1 (meters)")
    val base = GeofenceConditionBuilder()
      .setGeofenceType(type)
      .setLat(latitude)
      .setLng(longitude)
      .setRadius(radius.roundToInt())
      .setAddress(title)
      .build() as ConditionBase
    val cond = SceneCondition(base)
    cond.entityName = title
    promise.resolve(json(cond))
  }

  override fun buildDeviceAction(devId: String, dpId: String, value: String, promise: Promise) =
    guard(promise, "build_action_error") {
      if (devId.isBlank() || dpId.isBlank()) bad("devId and dpId are required")
      val dev = deviceOf(devId)
      val typed: Any = when (dpTypeOf(dev, dpId) ?: sniffType(value)) {
        "bool" -> parseBool(value)
        "value", "bitmap" -> parseInt(value)
        else -> value // enum/string/raw(hex) gửi nguyên chuỗi
      }
      val builder = DeviceActionBuilder().setDevId(devId)
      builder.setExecutorProperty<DeviceActionBuilder>(mutableMapOf(dpId to typed))
      val action = SceneAction(builder.build() as ActionBase)
      dev?.getName()?.let { action.entityName = it }
      dev?.getIconUrl()?.let { action.devIcon = it }
      promise.resolve(json(action))
    }

  // SDK chỉ nhận phút + giây → giờ quy đổi ra phút (iOS factory cũng làm y vậy: {"minutes":"h*60+m","seconds":"s"}).
  override fun buildDelayAction(hours: Double, minutes: Double, seconds: Double, promise: Promise) =
    guard(promise, "build_action_error") {
      val parts = listOf(hours, minutes, seconds)
      if (parts.any { it.isNaN() || it < 0 || it != Math.floor(it) }) bad("hours/minutes/seconds must be non-negative integers")
      val totalMinutes = hours.toInt() * 60 + minutes.toInt()
      if (totalMinutes == 0 && seconds.toInt() == 0) bad("delay must be > 0")
      val action = SceneAction(DelayActionBuilder(totalMinutes, seconds.toInt()).build() as ActionBase)
      promise.resolve(json(action))
    }

  override fun buildTriggerSceneAction(sceneId: String, sceneName: String, promise: Promise) =
    guard(promise, "build_action_error") {
      if (sceneId.isBlank()) bad("sceneId is required")
      val base = LinkageRuleActionBuilder().setLinkageRuleId(sceneId).setLinkageOperator("ruleTrigger").build() as ActionBase
      val action = SceneAction(base)
      if (sceneName.isNotEmpty()) action.entityName = sceneName
      promise.resolve(json(action))
    }

  override fun buildAutomationToggleAction(sceneId: String, enable: Boolean, promise: Promise) =
    guard(promise, "build_action_error") {
      if (sceneId.isBlank()) bad("sceneId is required")
      val operator = if (enable) "ruleEnable" else "ruleDisable"
      val base = LinkageRuleActionBuilder().setLinkageRuleId(sceneId).setLinkageOperator(operator).build() as ActionBase
      promise.resolve(json(SceneAction(base)))
    }

  // channel: 'message' (push trung tâm tin nhắn) · 'sms' · 'phone' (gọi thoại - gói dịch vụ trả phí của Tuya).
  override fun buildNotificationAction(channel: String, promise: Promise) = guard(promise, "build_action_error") {
    val notifyType = when (channel.trim().lowercase(Locale.ROOT)) {
      "message" -> "appPushTrigger"
      "sms" -> "smsSend"
      "phone" -> "mobileVoiceSend"
      else -> bad("channel must be 'message', 'sms' or 'phone'")
    }
    promise.resolve(json(SceneAction(NotifyActionBuilder().setNotifyType(notifyType).build() as ActionBase)))
  }

  // ---------- Helpers ----------
  override fun getConditionDeviceList(homeId: Double, promise: Promise) = guard(promise, "condition_device_list_error") {
    svc().deviceService().getConditionDeviceAll(homeId.toLong(), sceneCb(promise, "condition_device_list_error") { r ->
      promise.resolve(deviceItems(r as? List<*>))
    })
  }

  // Chỉ trả thiết bị lẻ (bỏ group): buildDeviceAction phát `dpIssue` cho devId, không hỗ trợ group.
  override fun getActionDeviceList(homeId: Double, promise: Promise) = guard(promise, "action_device_list_error") {
    svc().deviceService().getActionDeviceAll(homeId.toLong(), sceneCb(promise, "action_device_list_error") { r ->
      promise.resolve(deviceItems((r as? ActionDeviceGroup)?.getDevices()))
    })
  }

  override fun getCityListByCountryCode(countryCode: String, promise: Promise) = guard(promise, "city_list_error") {
    svc().conditionService().getLocalCityAll(countryCode, sceneCb(promise, "city_list_error") { r ->
      val arr = Arguments.createArray()
      (r as? List<*>).orEmpty().filterIsInstance<LocationCity>().forEach { arr.pushMap(cityOf(it)) }
      promise.resolve(arr)
    })
  }

  override fun getCityByLocation(latitude: Double, longitude: Double, promise: Promise) = guard(promise, "city_error") {
    if (latitude.isNaN() || longitude.isNaN()) bad("latitude/longitude are required")
    val lon = BigDecimal.valueOf(longitude).toPlainString()
    val lat = BigDecimal.valueOf(latitude).toPlainString()
    svc().conditionService().getLocalByCoordinate(lon, lat, sceneCb(promise, "city_error") { r ->
      val city = r as? LocationCity
      if (city == null) {
        TuyaReject.reject(promise, "city_not_found", "No city found for $lat,$lon")
      } else {
        promise.resolve(cityOf(city))
      }
    })
  }

  // ---------- Realtime listener (MQTT) → emit onSceneChange { type, sceneId } ----------
  // Callback chạy trên thread MQTT của SDK → không để lỗi bridge (context đã huỷ...) văng ngược vào SDK.
  private fun emitChange(type: String, sceneId: String) {
    try {
      emit(EVT_SCENE, Arguments.createMap().apply {
        putString("type", type)
        putString("sceneId", sceneId)
      })
    } catch (e: Throwable) {
      android.util.Log.w(NAME, "emit $EVT_SCENE failed: ${e.message}")
    }
  }

  override fun registerSceneChangeListener() {
    if (sceneListener != null) return
    val cb = object : SceneChangeCallback {
      override fun onAddScene(sceneId: String) = emitChange("add", sceneId)
      override fun onUpdateScene(sceneId: String) = emitChange("update", sceneId)
      override fun onDeleteScene(sceneId: String) = emitChange("delete", sceneId)
      override fun onEnableScene(sceneId: String) = emitChange("enable", sceneId)
      override fun onDisableScene(sceneId: String) = emitChange("disable", sceneId)
    }
    try {
      svc().executeService().registerDeviceMqttListener(cb)
      sceneListener = cb
    } catch (e: Throwable) {
      android.util.Log.w(NAME, "registerSceneChangeListener failed: ${e.message}")
    }
  }

  // Gỡ ĐÚNG listener của module (bản không tham số của SDK gỡ TẤT CẢ listener trong app).
  override fun unregisterSceneChangeListener() {
    val cb = sceneListener ?: return
    sceneListener = null
    try {
      svc().executeService().unRegisterDeviceMqttListener(cb)
    } catch (e: Throwable) {
      android.util.Log.w(NAME, "unregisterSceneChangeListener failed: ${e.message}")
    }
  }

  override fun invalidate() {
    unregisterSceneChangeListener()
    super.invalidate()
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}
}
