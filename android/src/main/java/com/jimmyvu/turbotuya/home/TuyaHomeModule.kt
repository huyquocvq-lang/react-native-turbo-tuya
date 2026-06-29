package com.jimmyvu.turbotuya.home

import com.jimmyvu.turbotuya.NativeTuyaHomeSpec
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.thingclips.smart.home.sdk.ThingHomeSdk
import com.thingclips.smart.home.sdk.bean.HomeBean
import com.thingclips.smart.home.sdk.callback.IThingGetHomeListCallback
import com.thingclips.smart.home.sdk.callback.IThingHomeResultCallback

// TuyaHome — quản lý home cơ bản (app dùng 1 nhà/user).
class TuyaHomeModule(reactContext: ReactApplicationContext) :
  NativeTuyaHomeSpec(reactContext) {

  companion object {
    const val NAME = NativeTuyaHomeSpec.NAME
  }

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
