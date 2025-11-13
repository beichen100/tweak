// VCAM Hello World Test - 最小化测试版本
// 目的：验证编译环境和基础 Hook 功能

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 测试计数器
static int hookCallCount = 0;

// Hook SpringBoard 的 applicationDidFinishLaunching
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig; // 调用原始方法
    
    hookCallCount++;
    
    // 打印到系统日志
    NSLog(@"🎉 VCAM Test Hook Success! Call count: %d", hookCallCount);
    
    // 显示一个简单的通知（3秒后自动消失）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ VCAM Test" 
                                                                       message:@"Hello World!\nHook 功能正常工作" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:nil];
        [alert addAction:okAction];
        
        // 获取当前可见的 window
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        
        if (keyWindow && keyWindow.rootViewController) {
            [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
            
            // 自动关闭（可选）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }
    });
}

%end

// Hook UIApplication 来验证更多 hook 点
%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    
    NSLog(@"🚀 VCAM Test: UIApplication didFinishLaunchingWithOptions called");
    NSLog(@"📱 Device: %@", [[UIDevice currentDevice] name]);
    NSLog(@"📱 System: %@ %@", [[UIDevice currentDevice] systemName], [[UIDevice currentDevice] systemVersion]);
    
    return result;
}

%end

// Constructor - 插件加载时执行
%ctor {
    NSLog(@"===============================================");
    NSLog(@"🔧 VCAM Test Plugin Loaded Successfully!");
    NSLog(@"📅 Load Time: %@", [NSDate date]);
    NSLog(@"🏗️ Build: iOS 14.0+ compatible");
    NSLog(@"===============================================");
    
    // 初始化测试
    hookCallCount = 0;
    
    NSLog(@"✅ VCAM Test: Constructor executed");
}

// Destructor - 插件卸载时执行（很少被调用）
%dtor {
    NSLog(@"👋 VCAM Test: Plugin unloaded. Total hook calls: %d", hookCallCount);
}
