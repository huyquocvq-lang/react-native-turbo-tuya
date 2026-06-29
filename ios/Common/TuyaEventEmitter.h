#import <React/RCTEventEmitter.h>

// Base class cho các TurboModule iOS phát event qua NativeEventEmitter (pattern addListener/
// removeListeners — KHÔNG dùng codegen EventEmitter type; xem quyết định ở m1-tuya-sdk-library).
// Subclass + override -supportedEvents; gọi [self emit:name body:body] (tương đương Android
// RCTDeviceEventEmitter.emit). addListener:/removeListeners: do RCTEventEmitter cung cấp sẵn → khớp spec.
//
// ⚠️ VERIFY trên Xcode (New Architecture): RCTEventEmitter + TurboModule (getTurboModule) cùng tồn tại.
//    Nếu event không tới JS trong bridgeless mode → fallback sang codegen EventEmitter type trong spec.
@interface TuyaEventEmitter : RCTEventEmitter

/** Gửi event chỉ khi đang có listener (tránh cảnh báo "sending event with no listeners"). */
- (void)emit:(NSString *)name body:(id)body;

@end
