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
  s.source       = { :git => "https://github.com/drakenvu/cool-bath.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  # Tuya Smart Life App SDK (Home SDK). LƯU Ý: file bảo mật `ThingSmartCryption`
  # (giải nén từ ios_core_sdk.tar.gz) là per-app → khai báo ở Podfile của app
  # tiêu thụ (example / apps/mobile), KHÔNG ở đây. Xem README.md.
  s.dependency "ThingSmartHomeKit"
  s.dependency "ThingSmartBusinessExtensionKit"

  install_modules_dependencies(s)
end
