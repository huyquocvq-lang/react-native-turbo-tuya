#import "TuyaEventEmitter.h"

// Lớp cơ sở trừu tượng - KHÔNG RCT_EXPORT_MODULE (chỉ subclass cụ thể mới đăng ký).
@implementation TuyaEventEmitter {
  BOOL _hasListeners;
}

+ (BOOL)requiresMainQueueSetup { return NO; }

// Subclass override để khai báo event của mình.
- (NSArray<NSString *> *)supportedEvents { return @[]; }

// RCTEventEmitter gọi khi có/không còn listener.
- (void)startObserving { _hasListeners = YES; }
- (void)stopObserving { _hasListeners = NO; }

- (void)emit:(NSString *)name body:(id)body {
  if (_hasListeners) {
    [self sendEventWithName:name body:body];
  }
}

@end
