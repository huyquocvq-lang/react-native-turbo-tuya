package com.jimmyvu.turbotuya

import com.jimmyvu.turbotuya.auth.TuyaAuthModule
import com.jimmyvu.turbotuya.core.TuyaCoreModule
import com.jimmyvu.turbotuya.device.TuyaDeviceModule
import com.jimmyvu.turbotuya.home.TuyaHomeModule
import com.jimmyvu.turbotuya.matter.TuyaMatterModule
import com.jimmyvu.turbotuya.mesh.TuyaMeshModule
import com.jimmyvu.turbotuya.member.TuyaMemberModule
import com.jimmyvu.turbotuya.message.TuyaMessageModule
import com.jimmyvu.turbotuya.ota.TuyaOtaModule
import com.jimmyvu.turbotuya.pairing.TuyaPairingModule
import com.jimmyvu.turbotuya.scene.TuyaSceneModule
import com.jimmyvu.turbotuya.timer.TuyaTimerModule
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

// Đăng ký 12 TurboModule tách theo tính năng: Core / Auth / Home / Pairing / Device / Ota / Scene / Timer / Message / Member / Matter / Mesh.
class TurboTuyaPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
    when (name) {
      TuyaCoreModule.NAME -> TuyaCoreModule(reactContext)
      TuyaAuthModule.NAME -> TuyaAuthModule(reactContext)
      TuyaHomeModule.NAME -> TuyaHomeModule(reactContext)
      TuyaPairingModule.NAME -> TuyaPairingModule(reactContext)
      TuyaDeviceModule.NAME -> TuyaDeviceModule(reactContext)
      TuyaOtaModule.NAME -> TuyaOtaModule(reactContext)
      TuyaSceneModule.NAME -> TuyaSceneModule(reactContext)
      TuyaTimerModule.NAME -> TuyaTimerModule(reactContext)
      TuyaMessageModule.NAME -> TuyaMessageModule(reactContext)
      TuyaMemberModule.NAME -> TuyaMemberModule(reactContext)
      TuyaMatterModule.NAME -> TuyaMatterModule(reactContext)
      TuyaMeshModule.NAME -> TuyaMeshModule(reactContext)
      else -> null
    }

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    fun info(n: String) = ReactModuleInfo(
      name = n,
      className = n,
      canOverrideExistingModule = false,
      needsEagerInit = false,
      isCxxModule = false,
      isTurboModule = true,
    )
    mapOf(
      TuyaCoreModule.NAME to info(TuyaCoreModule.NAME),
      TuyaAuthModule.NAME to info(TuyaAuthModule.NAME),
      TuyaHomeModule.NAME to info(TuyaHomeModule.NAME),
      TuyaPairingModule.NAME to info(TuyaPairingModule.NAME),
      TuyaDeviceModule.NAME to info(TuyaDeviceModule.NAME),
      TuyaOtaModule.NAME to info(TuyaOtaModule.NAME),
      TuyaSceneModule.NAME to info(TuyaSceneModule.NAME),
      TuyaTimerModule.NAME to info(TuyaTimerModule.NAME),
      TuyaMessageModule.NAME to info(TuyaMessageModule.NAME),
      TuyaMemberModule.NAME to info(TuyaMemberModule.NAME),
      TuyaMatterModule.NAME to info(TuyaMatterModule.NAME),
      TuyaMeshModule.NAME to info(TuyaMeshModule.NAME),
    )
  }
}
