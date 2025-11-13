#import <Foundation/Foundation.h>

// 最简版本：仅在动态库加载时打印一条日志
%ctor {
    NSLog(@"[VCAM] Hello World - tweak loaded");
}
