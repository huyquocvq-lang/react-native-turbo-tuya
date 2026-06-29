package com.jimmyvu.turbotuya

import com.jimmyvu.turbotuya.auth.TuyaAuthModule
import com.jimmyvu.turbotuya.core.TuyaCoreModule
import com.jimmyvu.turbotuya.device.TuyaDeviceModule
import com.jimmyvu.turbotuya.home.TuyaHomeModule
import com.jimmyvu.turbotuya.pairing.TuyaPairingModule
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

// Đăng ký 5 TurboModule tách theo tính năng: Core / Auth / Home / Pairing / Device.
class TurboTuyaPackage : BaseReactPackage() {
  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
    when (name) {
      TuyaCoreModule.NAME -> TuyaCoreModule(reactContext)
      TuyaAuthModule.NAME -> TuyaAuthModule(reactContext)
      TuyaHomeModule.NAME -> TuyaHomeModule(reactContext)
      TuyaPairingModule.NAME -> TuyaPairingModule(reactContext)
      TuyaDeviceModule.NAME -> TuyaDeviceModule(reactContext)
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
    )
  }
}
