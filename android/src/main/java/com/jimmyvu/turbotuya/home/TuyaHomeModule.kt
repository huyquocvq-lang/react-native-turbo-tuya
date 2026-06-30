package com.jimmyvu.turbotuya.home

// B10 mở rộng theo docs/research/tuya-home-sdk-home-management.md (verbatim) — CHƯA build-verify.
// ⚠️ Verify import/chữ ký: WeatherBean + IIGetHomeWetherSketchCallBack (package + onFailure args),
//    IThingHomeChangeListener/IThingHomeStatusListener (package .home.sdk.api?), unRegisterHomeStatusListener,
//    DashBoardBean (getHomeWeatherDetail → để TODO vì field chưa rõ).

import com.jimmyvu.turbotuya.NativeTuyaHomeSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.api.IThingHomeChangeListener
import com.thingclips.smart.home.sdk.api.IThingHomeStatusListener
import com.thingclips.smart.home.sdk.bean.HomeBean
import com.thingclips.smart.home.sdk.bean.WeatherBean
import com.thingclips.smart.home.sdk.callback.IIGetHomeWetherSketchCallBack
import com.thingclips.smart.home.sdk.callback.IThingGetHomeListCallback
import com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback
import com.thingclips.smart.sdk.api.IResultCallback
import com.thingclips.smart.sdk.bean.DeviceBean
import com.thingclips.smart.sdk.bean.group.bean.GroupBean

// TuyaHome — quản lý home (app dùng 1 nhà/user) + weather + listeners. Phát event onHomeChange.
class TuyaHomeModule(reactContext: ReactApplicationContext) :
  NativeTuyaHomeSpec(reactContext) {

  private val ctx = reactContext
  // Listener cấp manager (1) + listener cấp home theo homeId (n) — giữ tham chiếu để gỡ đúng instance.
  private var changeListener: IThingHomeChangeListener? = null
  private val statusListeners = mutableMapOf<Long, IThingHomeStatusListener>()

  companion object {
    const val NAME = NativeTuyaHomeSpec.NAME
    private const val EVT_HOME = "onHomeChange"
  }

  private fun emit(params: WritableMap) {
    ctx.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(EVT_HOME, params)
  }

  private fun event(type: String): WritableMap =
    Arguments.createMap().apply { putString("type", type) }

  override fun createHome(
    name: String,
    lon: Double,
    lat: Double,
    geoName: String,
    rooms: ReadableArray,
    promise: Promise,
  ) {
    val roomList = (0 until rooms.size()).mapNotNull { rooms.getString(it) }
    ThingHomeSdk.getHomeManagerInstance().createHome(
      name, lon, lat, geoName, roomList,
      object : IThingHomeResultCallback {
        override fun onSuccess(bean: HomeBean?) = promise.resolve(homeToMap(bean))
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "create_home_error", error)
      },
    )
  }

  override fun getHomeList(promise: Promise) {
    ThingHomeSdk.getHomeManagerInstance().queryHomeList(
      object : IThingGetHomeListCallback {
        override fun onSuccess(homeBeans: MutableList<HomeBean>?) {
          val arr = Arguments.createArray()
          homeBeans?.forEach { arr.pushMap(homeToMap(it)) }
          promise.resolve(arr)
        }
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "home_list_error", error)
      },
    )
  }

  override fun getHomeDetail(homeId: Double, promise: Promise) {
    ThingHomeSdk.newHomeInstance(homeId.toLong()).getHomeDetail(
      object : IThingHomeResultCallback {
        override fun onSuccess(bean: HomeBean?) = promise.resolve(homeToMap(bean))
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "home_detail_error", error)
      },
    )
  }

  override fun updateHome(
    homeId: Double,
    name: String,
    lon: Double,
    lat: Double,
    geoName: String,
    rooms: ReadableArray,
    promise: Promise,
  ) {
    val roomList = (0 until rooms.size()).mapNotNull { rooms.getString(it) }
    ThingHomeSdk.newHomeInstance(homeId.toLong()).updateHome(
      name, lon, lat, geoName, roomList,
      object : IResultCallback {
        override fun onSuccess() = promise.resolve(null)
        override fun onError(code: String?, error: String?) =
          promise.reject(code ?: "update_home_error", error)
      },
    )
  }

  override fun dismissHome(homeId: Double, promise: Promise) {
    ThingHomeSdk.newHomeInstance(homeId.toLong()).dismissHome(object : IResultCallback {
      override fun onSuccess() = promise.resolve(null)
      override fun onError(code: String?, error: String?) =
        promise.reject(code ?: "dismiss_home_error", error)
    })
  }

  // ---------- Weather ----------
  override fun getHomeWeatherSketch(homeId: Double, lon: Double, lat: Double, promise: Promise) {
    ThingHomeSdk.getHomeManagerInstance().getHomeWeatherSketch(
      lon, lat,
      object : IIGetHomeWetherSketchCallBack {
        override fun onSuccess(result: WeatherBean?) {
          val m = Arguments.createMap()
          m.putString("condition", result?.condition ?: "")
          m.putString("temp", result?.temp?.toString() ?: "")
          m.putString("iconUrl", result?.iconUrl ?: "")
          m.putString("inIconUrl", result?.inIconUrl ?: "")
          promise.resolve(m)
        }
        override fun onFailure(code: String?, error: String?) =
          promise.reject(code ?: "weather_sketch_error", error)
      },
    )
  }

  override fun getHomeWeatherDetail(homeId: Double, limit: Double, unitJson: String, promise: Promise) {
    // intended: newHomeInstance(homeId).getHomeWeatherDetail(limit, unitMap, IGetHomeWetherCallBack)
    //           → onSuccess(ArrayList<DashBoardBean>); field DashBoardBean chưa verbatim → serialize TODO.
    promise.reject(
      "not_implemented",
      "getHomeWeatherDetail chưa wire (DashBoardBean field chưa rõ) — xem docs/research/tuya-home-sdk-home-management.md",
    )
  }

  // ---------- Listeners ----------
  override fun startHomeChangeListener(promise: Promise) {
    changeListener?.let { ThingHomeSdk.getHomeManagerInstance().unRegisterThingHomeChangeListener(it) }
    val l = object : IThingHomeChangeListener {
      override fun onHomeAdded(homeId: Long) =
        emit(event("homeAdded").apply { putDouble("homeId", homeId.toDouble()) })
      override fun onHomeInvite(homeId: Long, homeName: String?) =
        emit(event("homeInvite").apply { putDouble("homeId", homeId.toDouble()); putString("homeName", homeName ?: "") })
      override fun onHomeRemoved(homeId: Long) =
        emit(event("homeRemoved").apply { putDouble("homeId", homeId.toDouble()) })
      override fun onHomeInfoChanged(homeId: Long) =
        emit(event("homeInfoChanged").apply { putDouble("homeId", homeId.toDouble()) })
      override fun onSharedDeviceList(sharedDeviceList: MutableList<DeviceBean>?) {
        val ids = Arguments.createArray()
        sharedDeviceList?.forEach { ids.pushString(it.devId ?: "") }
        emit(event("sharedDeviceList").apply { putArray("devIds", ids) })
      }
      override fun onSharedGroupList(sharedGroupList: MutableList<GroupBean>?) =
        emit(event("sharedGroupList"))
      override fun onServerConnectSuccess() = emit(event("serverConnected"))
    }
    ThingHomeSdk.getHomeManagerInstance().registerThingHomeChangeListener(l)
    changeListener = l
    promise.resolve(null)
  }

  override fun stopHomeChangeListener(promise: Promise) {
    changeListener?.let { ThingHomeSdk.getHomeManagerInstance().unRegisterThingHomeChangeListener(it) }
    changeListener = null
    promise.resolve(null)
  }

  override fun startHomeStatusListener(homeId: Double, promise: Promise) {
    val id = homeId.toLong()
    val home = ThingHomeSdk.newHomeInstance(id)
    statusListeners[id]?.let { home.unRegisterHomeStatusListener(it) }
    val l = object : IThingHomeStatusListener {
      override fun onDeviceAdded(devId: String?) =
        emit(event("deviceAdded").apply { putDouble("homeId", homeId); putString("devId", devId ?: "") })
      override fun onDeviceRemoved(devId: String?) =
        emit(event("deviceRemoved").apply { putDouble("homeId", homeId); putString("devId", devId ?: "") })
      override fun onGroupAdded(groupId: Long) =
        emit(event("groupAdded").apply { putDouble("homeId", homeId); putDouble("groupId", groupId.toDouble()) })
      override fun onGroupRemoved(groupId: Long) =
        emit(event("groupRemoved").apply { putDouble("homeId", homeId); putDouble("groupId", groupId.toDouble()) })
      override fun onMeshAdded(meshId: String?) =
        emit(event("meshAdded").apply { putDouble("homeId", homeId); putString("meshId", meshId ?: "") })
    }
    home.registerHomeStatusListener(l)
    statusListeners[id] = l
    promise.resolve(null)
  }

  override fun stopHomeStatusListener(homeId: Double, promise: Promise) {
    val id = homeId.toLong()
    statusListeners[id]?.let { ThingHomeSdk.newHomeInstance(id).unRegisterHomeStatusListener(it) }
    statusListeners.remove(id)
    promise.resolve(null)
  }

  // ---------- RN event emitter plumbing (no-op; bắt buộc cho NativeEventEmitter) ----------
  override fun addListener(eventName: String) {}
  override fun removeListeners(count: Double) {}

  // Gỡ listener khi RN instance huỷ → tránh leak / callback rò rỉ.
  override fun invalidate() {
    super.invalidate()
    changeListener?.let { runCatching { ThingHomeSdk.getHomeManagerInstance().unRegisterThingHomeChangeListener(it) } }
    changeListener = null
    statusListeners.forEach { (id, l) ->
      runCatching { ThingHomeSdk.newHomeInstance(id).unRegisterHomeStatusListener(l) }
    }
    statusListeners.clear()
  }

  // ---------- helpers ----------
  private fun homeToMap(bean: HomeBean?): WritableMap {
    val m = Arguments.createMap()
    m.putDouble("homeId", (bean?.homeId ?: 0L).toDouble())
    m.putString("name", bean?.name ?: "")
    m.putDouble("role", (bean?.role ?: 0).toDouble())
    m.putBoolean("admin", bean?.isAdmin ?: false)
    m.putDouble("lon", bean?.lon ?: 0.0)
    m.putDouble("lat", bean?.lat ?: 0.0)
    m.putString("geoName", bean?.geoName ?: "")
    return m
  }
}
