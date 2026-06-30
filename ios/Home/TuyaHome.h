#import <TurboTuyaSpec/TurboTuyaSpec.h>
#import "TuyaEventEmitter.h"

// Phát event 'onHomeChange' → subclass TuyaEventEmitter (RCTEventEmitter) thay vì NSObject.
@interface TuyaHome : TuyaEventEmitter <NativeTuyaHomeSpec>

@end
