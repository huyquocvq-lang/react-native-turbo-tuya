require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "TurboTuya"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/huyquocvq-lang/react-native-turbo-tuya.git", :tag => "v#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  # Tuya Smart Life App SDK (Home SDK). LƯU Ý: file bảo mật `ThingSmartCryption`
  # (giải nén từ ios_core_sdk.tar.gz) là per-app → khai báo ở Podfile của app
  # tiêu thụ (example / apps/mobile), KHÔNG ở đây. Xem README.md.
  s.dependency "ThingSmartHomeKit"
  s.dependency "ThingSmartBusinessExtensionKit"
  # TuyaScene.mm serialize model scene bằng YYModel (đã có sẵn qua các pod Tuya - khai báo cho tường minh).
  s.dependency "YYModel"

  install_modules_dependencies(s)
end
