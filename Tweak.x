#include <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
// #import "util.h"

static NSFileManager *g_fileManager = nil; // 文件管理对象
static UIPasteboard *g_pasteboard = nil; // 剪贴板对象
static BOOL g_canReleaseBuffer = YES; // 当前是否可以释放buffer
static BOOL g_bufferReload = YES; // 是否需要立即重新刷新视频文件
static AVSampleBufferDisplayLayer *g_previewLayer = nil; // 原生相机预览
static NSTimeInterval g_refreshPreviewByVideoDataOutputTime = 0; // 如果存在 VideoDataOutput, 预览画面会同步VideoDataOutput的画面, 如果没有则会直接读取视频显示
static BOOL g_cameraRunning = NO;
static NSString *g_cameraPosition = @"B"; // B 为后置摄像头、F 为前置摄像头
static AVCaptureVideoOrientation g_photoOrientation = AVCaptureVideoOrientationPortrait; // 视频的方向

NSString *g_isMirroredMark = @"/var/mobile/Library/Caches/vcam_is_mirrored_mark";
NSString *g_tempFile = @"/var/mobile/Library/Caches/temp.mov"; // 临时文件位置

static AVAssetReader *reader = nil;
static AVAssetReaderTrackOutput *videoTrackout_32BGRA = nil;
static AVAssetReaderTrackOutput *videoTrackout_420YpCbCr8BiPlanarVideoRange = nil;
static AVAssetReaderTrackOutput *videoTrackout_420YpCbCr8BiPlanarFullRange = nil;
static AVAssetReaderTrackOutput *audioTrackout_pcm = nil;

// Thêm biến toàn cục cho âm thanh
static AVAudioEngine *g_audioEngine = nil;
static AVPlayerItem *g_audioPlayerItem = nil;
static AVPlayer *g_audioPlayer = nil;
static BOOL g_audioEnabled = YES;

// Thêm biến để theo dõi thời gian quay video
static NSTimeInterval g_videoRecordingStartTime = 0;
static NSTimeInterval g_lastBufferRefreshTime = 0;
static const NSTimeInterval BUFFER_REFRESH_INTERVAL = 30.0; // Làm mới buffer mỗi 30 giây

// Biến kiểm tra phiên bản iOS
static BOOL g_isIOS15OrLater = NO;

// Các biến cấu hình UI
static BOOL g_enableNotification = YES; // Cho phép thông báo
static BOOL g_minimizeUIInteraction = NO; // Giảm thiểu giao diện tương tác

// Thêm biến để kiểm tra trạng thái camera
static BOOL g_cameraErrorDetected = NO;
static BOOL g_ldRestartCompleted = NO;

// Thêm đọc cài đặt từ preferences
static NSDictionary *preferences;
static BOOL loadPreferences() {
    CFArrayRef keyList = CFPreferencesCopyKeyList(CFSTR("com.trizau.sileo.vcam"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keyList) {
        preferences = (__bridge NSDictionary *)CFPreferencesCopyMultiple(keyList, CFSTR("com.trizau.sileo.vcam"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFRelease(keyList);
        return YES;
    }
    return NO;
}

// Hàm lấy giá trị từ preferences
static BOOL getBoolFromPreferences(NSString *key, BOOL defaultValue) {
    if (preferences && [preferences objectForKey:key]) {
        return [[preferences objectForKey:key] boolValue];
    }
    return defaultValue;
}

// Các biến cấu hình từ preferences
static void updatePreferences() {
    if (loadPreferences()) {
        g_audioEnabled = getBoolFromPreferences(@"enableAudio", YES);
        g_enableNotification = getBoolFromPreferences(@"enableNotification", YES);
        g_minimizeUIInteraction = getBoolFromPreferences(@"minimizeUI", NO);
    }
}

// Hàm xử lý khi preferences thay đổi
static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    updatePreferences();
}

@interface GetFrame : NSObject
+ (CMSampleBufferRef _Nullable)getCurrentFrame:(CMSampleBufferRef) originSampleBuffer :(BOOL)forceReNew;
+ (UIWindow*)getKeyWindow;
+ (void)setupAudioPlayback;
+ (void)showMinimalNotification:(NSString *)message;
+ (void)fixCameraWithLDRestart;
@end

@implementation GetFrame
+ (CMSampleBufferRef _Nullable)getCurrentFrame:(CMSampleBufferRef _Nullable) originSampleBuffer :(BOOL)forceReNew{
    static CMSampleBufferRef sampleBuffer = nil;

    // origin buffer info
    CMFormatDescriptionRef formatDescription = nil;
    CMMediaType mediaType = -1;
    CMMediaType subMediaType = -1;
    CMVideoDimensions dimensions;
    if (originSampleBuffer != nil) {
        formatDescription = CMSampleBufferGetFormatDescription(originSampleBuffer);
        mediaType = CMFormatDescriptionGetMediaType(formatDescription);
        subMediaType = CMFormatDescriptionGetMediaSubType(formatDescription);
        dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        if (mediaType != kCMMediaType_Video) {
            // if (mediaType == kCMMediaType_Audio && subMediaType == kAudioFormatLinearPCM) {
            //     if (reader != nil && audioTrackout_pcm != nil && [reader status] == AVAssetReaderStatusReading) {
            //         NSLog(@"ok");
                    
            //         static CMSampleBufferRef audioBuffer = nil;
            //         if (audioBuffer != nil) CFRelease(audioBuffer);
            //         audioBuffer = [audioTrackout_pcm copyNextSampleBuffer];
            //         NSLog(@"audioBuffer = %@", audioBuffer);
            //         // return audioBuffer;
            //     }
            // }
            // @see https://developer.apple.com/documentation/coremedia/cmmediatype?language=objc
            return originSampleBuffer;
        }
    }

    // 没有替换视频则返回空以使用原来的数据
    if ([g_fileManager fileExistsAtPath:g_tempFile] == NO) return nil;
    if (sampleBuffer != nil && !g_canReleaseBuffer && CMSampleBufferIsValid(sampleBuffer) && forceReNew != YES) return sampleBuffer; // 不能释放buffer时返回上一个buffer


    static NSTimeInterval renewTime = 0;
    // 选择了新的替换视频
    if ([g_fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile]]) {
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970];
        if (nowTime - renewTime > 3) {
            renewTime = nowTime;
            g_bufferReload = YES;
        }
    }

    if (g_bufferReload) {
        g_bufferReload = NO;
        @try{
            AVAsset *asset = [AVAsset assetWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", g_tempFile]]];
            reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            
            AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject]; // 获取轨道
            
            videoTrackout_32BGRA = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
            videoTrackout_420YpCbCr8BiPlanarVideoRange = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
            videoTrackout_420YpCbCr8BiPlanarFullRange = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];
            
            // Thêm xử lý âm thanh
            AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
            if (audioTrack) {
                audioTrackout_pcm = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:@{AVFormatIDKey : [NSNumber numberWithInt:kAudioFormatLinearPCM]}];
                if (audioTrackout_pcm) {
                    [reader addOutput:audioTrackout_pcm];
                }
            }
            
            [reader addOutput:videoTrackout_32BGRA];
            [reader addOutput:videoTrackout_420YpCbCr8BiPlanarVideoRange];
            [reader addOutput:videoTrackout_420YpCbCr8BiPlanarFullRange];

            [reader startReading];
        }@catch(NSException *except) {
            NSLog(@"初始化读取视频出错:%@", except);
        }
    }
    // NSLog(@"刷新了");

    CMSampleBufferRef videoTrackout_32BGRA_Buffer = [videoTrackout_32BGRA copyNextSampleBuffer];
    CMSampleBufferRef videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer = [videoTrackout_420YpCbCr8BiPlanarVideoRange copyNextSampleBuffer];
    CMSampleBufferRef videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer = [videoTrackout_420YpCbCr8BiPlanarFullRange copyNextSampleBuffer];

    CMSampleBufferRef newsampleBuffer = nil;
    // 根据subMediaTyp拷贝对应的类型
    switch(subMediaType) {
        case kCVPixelFormatType_32BGRA:
            // NSLog(@"--->kCVPixelFormatType_32BGRA");
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_32BGRA_Buffer, &newsampleBuffer);
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // NSLog(@"--->kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange");
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer, &newsampleBuffer);
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            // NSLog(@"--->kCVPixelFormatType_420YpCbCr8BiPlanarFullRange");
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer, &newsampleBuffer);
            break;
        default:
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_32BGRA_Buffer, &newsampleBuffer);
    }
    // 释放内存
    if (videoTrackout_32BGRA_Buffer != nil) CFRelease(videoTrackout_32BGRA_Buffer);
    if (videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer != nil) CFRelease(videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer);
    if (videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer != nil) CFRelease(videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer);

    if (newsampleBuffer == nil) {
        g_bufferReload = YES;
    }else {
        if (sampleBuffer != nil) CFRelease(sampleBuffer);
        if (originSampleBuffer != nil) {

            // NSLog(@"---->%@", originSampleBuffer);
            // NSLog(@"====>%@", formatDescription);

            CMSampleBufferRef copyBuffer = nil;
            
            CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(newsampleBuffer);

            // NSLog(@"width:%ld height:%ld", CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
            // NSLog(@"width:%d height:%d ===", dimensions.width, dimensions.height);

            // TODO:: 滤镜

            CMSampleTimingInfo sampleTime = {
                .duration = CMSampleBufferGetDuration(originSampleBuffer),
                .presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(originSampleBuffer),
                .decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(originSampleBuffer)
            };

            CMVideoFormatDescriptionRef videoInfo = nil;
            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &videoInfo);
            
            // 如果传了这个buffer则需要按照这个buffer去生成
            // CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, [[NSDate date] timeIntervalSince1970] * 1000);

            // CVImage Buffer
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, videoInfo, &sampleTime, &copyBuffer);
            // NSLog(@"cvimagebuffer ->%@", copyBuffer);

            if (copyBuffer != nil) {
                CFDictionaryRef exifAttachments = CMGetAttachment(originSampleBuffer, (CFStringRef)@"{Exif}", NULL);
                CFDictionaryRef TIFFAttachments = CMGetAttachment(originSampleBuffer, (CFStringRef)@"{TIFF}", NULL);

                // 设定EXIF信息
                if (exifAttachments != nil) CMSetAttachment(copyBuffer, (CFStringRef)@"{Exif}", exifAttachments, kCMAttachmentMode_ShouldPropagate);
                // 设定TIFF信息
                if (exifAttachments != nil) CMSetAttachment(copyBuffer, (CFStringRef)@"{TIFF}", TIFFAttachments, kCMAttachmentMode_ShouldPropagate);
                
                // NSLog(@"设置了exit信息 %@", CMGetAttachment(copyBuffer, (CFStringRef)@"{TIFF}", NULL));
                sampleBuffer = copyBuffer;
                // NSLog(@"--->GetDataBuffer = %@", CMSampleBufferGetDataBuffer(copyBuffer));
            }
            CFRelease(newsampleBuffer);
            // sampleBuffer = newsampleBuffer;
        }else {
            // 直接从视频读取的 kCVPixelFormatType_32BGRA 
            sampleBuffer = newsampleBuffer;
        }
    }
    if (CMSampleBufferIsValid(sampleBuffer)) return sampleBuffer;
    return nil;
}
+(UIWindow*)getKeyWindow{
    // need using [GetFrame getKeyWindow].rootViewController
    UIWindow *keyWindow = nil;
    if (keyWindow == nil) {
        NSArray *windows = UIApplication.sharedApplication.windows;
        for(UIWindow *window in windows){
            if(window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
    }
    return keyWindow;
}
+ (void)setupAudioPlayback {
    static BOOL isAudioSetup = NO;
    if (!g_audioEnabled || isAudioSetup || ![g_fileManager fileExistsAtPath:g_tempFile]) return;
    
    @try {
        // Dọn dẹp phiên âm thanh cũ
        [g_audioPlayer pause];
        g_audioPlayer = nil;
        g_audioPlayerItem = nil;
        
        // Tạo player mới
        NSURL *videoURL = [NSURL fileURLWithPath:g_tempFile];
        g_audioPlayerItem = [AVPlayerItem playerItemWithURL:videoURL];
        g_audioPlayer = [AVPlayer playerWithPlayerItem:g_audioPlayerItem];
        
        // Lặp lại video
        [g_audioPlayer setActionAtItemEnd:AVPlayerActionAtItemEndNone];
        [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                         object:g_audioPlayerItem
                                                          queue:nil
                                                     usingBlock:^(NSNotification *note) {
            // Khi phát hết, quay lại thời điểm 0
            [g_audioPlayer seekToTime:kCMTimeZero];
        }];
        
        [g_audioPlayer play];
        isAudioSetup = YES;
    } @catch (NSException *exception) {
        NSLog(@"Lỗi khi thiết lập âm thanh: %@", exception);
    }
}
+ (void)showMinimalNotification:(NSString *)message {
    if (!g_enableNotification) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [GetFrame getKeyWindow];
        UIView *notificationView = [[UIView alloc] initWithFrame:CGRectMake(0, 44, window.bounds.size.width, 40)];
        notificationView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        notificationView.layer.cornerRadius = 10;
        notificationView.clipsToBounds = YES;
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, notificationView.bounds.size.width - 20, 30)];
        label.text = message;
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:14];
        [notificationView addSubview:label];
        
        [window addSubview:notificationView];
        
        // Tự động ẩn sau 2 giây
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.5 animations:^{
                notificationView.alpha = 0;
            } completion:^(BOOL finished) {
                [notificationView removeFromSuperview];
            }];
        });
    });
}
+ (void)fixCameraWithLDRestart {
    // Kiểm tra nếu PowerSelector có sẵn
    BOOL hasPowerSelector = [[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/PowerSelector.dylib"];
    
    if (hasPowerSelector) {
        NSLog(@"Đang sửa camera bằng PowerSelector...");
        
        // Gọi PowerSelector để thực hiện LDRestart
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/usr/bin/powerselector"];
        [task setArguments:@[@"ldrestart"]];
        [task launch];
        
        // Đánh dấu là đã thực hiện LDRestart
        g_ldRestartCompleted = YES;
        
        // Hiển thị thông báo
        [GetFrame showMinimalNotification:@"Đang khởi động lại các dịch vụ để sửa lỗi camera..."];
        
        // Sau LDRestart, gọi UICache
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSTask *uiCacheTask = [[NSTask alloc] init];
            [uiCacheTask setLaunchPath:@"/usr/bin/uicache"];
            [uiCacheTask launch];
            [GetFrame showMinimalNotification:@"Đã sửa lỗi camera"];
        });
    } else {
        // Nếu không có PowerSelector, hiện thông báo
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Cần PowerSelector" 
                                                                                message:@"Để sửa lỗi camera, hãy cài đặt PowerSelector từ Cydia" 
                                                                         preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alertController addAction:ok];
        [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];
    }
}
@end


CALayer *g_maskLayer = nil;
%hook AVCaptureVideoPreviewLayer
- (void)addSublayer:(CALayer *)layer{
    %orig;
    // self.opacity = 0;
    // self.borderColor = [UIColor blackColor].CGColor;

    static CADisplayLink *displayLink = nil;
    if (displayLink == nil) {
        displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }

    // 播放条目
    if (![[self sublayers] containsObject:g_previewLayer]) {
        g_previewLayer = [[AVSampleBufferDisplayLayer alloc] init];

        // black mask
        g_maskLayer = [CALayer new];
        g_maskLayer.backgroundColor = [UIColor blackColor].CGColor;
        [self insertSublayer:g_maskLayer above:layer];
        [self insertSublayer:g_previewLayer above:g_maskLayer];

        // layer size init
        dispatch_async(dispatch_get_main_queue(), ^{
            g_previewLayer.frame = [UIApplication sharedApplication].keyWindow.bounds;
            g_maskLayer.frame = [UIApplication sharedApplication].keyWindow.bounds;
        });
        // NSLog(@"添加了 %@", [self sublayers]);
    }
}
%new
-(void)step:(CADisplayLink *)sender{
    if ([g_fileManager fileExistsAtPath:g_tempFile]) {
        if (g_maskLayer != nil) g_maskLayer.opacity = 1;
        if (g_previewLayer != nil) {
            g_previewLayer.opacity = 1;
            [g_previewLayer setVideoGravity:[self videoGravity]];
        }
    }else {
        if (g_maskLayer != nil) g_maskLayer.opacity = 0;
        if (g_previewLayer != nil) g_previewLayer.opacity = 0;
    }

    if (g_cameraRunning && g_previewLayer != nil) {
        // NSLog(@"g_previewLayer=>%@", g_previewLayer);
        // NSLog(@"g_previewLayer.readyForMoreMediaData %@", g_previewLayer.readyForMoreMediaData?@"yes":@"no");
        g_previewLayer.frame = self.bounds;
        // NSLog(@"-->%@", NSStringFromCGSize(g_previewLayer.frame.size));

        switch(g_photoOrientation) {
            case AVCaptureVideoOrientationPortrait:
                // NSLog(@"AVCaptureVideoOrientationPortrait");
            case AVCaptureVideoOrientationPortraitUpsideDown:
                // NSLog(@"AVCaptureVideoOrientationPortraitUpsideDown");
                g_previewLayer.transform = CATransform3DMakeRotation(0 / 180.0 * M_PI, 0.0, 0.0, 1.0);break;
            case AVCaptureVideoOrientationLandscapeRight:
                // NSLog(@"AVCaptureVideoOrientationLandscapeRight");
                g_previewLayer.transform = CATransform3DMakeRotation(90 / 180.0 * M_PI, 0.0, 0.0, 1.0);break;
            case AVCaptureVideoOrientationLandscapeLeft:
                // NSLog(@"AVCaptureVideoOrientationLandscapeLeft");
                g_previewLayer.transform = CATransform3DMakeRotation(-90 / 180.0 * M_PI, 0.0, 0.0, 1.0);break;
            default:
                g_previewLayer.transform = self.transform;
        }

        // 防止和VideoOutput冲突
        static NSTimeInterval refreshTime = 0;
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970] * 1000;
        if (nowTime - g_refreshPreviewByVideoDataOutputTime > 1000) {
            // 帧率控制
            static CMSampleBufferRef copyBuffer = nil;
            if (nowTime - refreshTime > 1000 / 33 && g_previewLayer.readyForMoreMediaData) {
                refreshTime = nowTime;
                g_photoOrientation = -1;
                // NSLog(@"-==-·刷新了 %f", nowTime);
                CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil :NO];
                if (newBuffer != nil) {
                    [g_previewLayer flush];
                    if (copyBuffer != nil) CFRelease(copyBuffer);
                    CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);
                    if (copyBuffer != nil) [g_previewLayer enqueueSampleBuffer:copyBuffer];

                    // camera info
                    NSDate *datenow = [NSDate date];
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
                    CGSize dimensions = self.bounds.size;
                    NSString *str = [NSString stringWithFormat:@"%@\n%@ - %@\nW:%.0f  H:%.0f",
                        [formatter stringFromDate:datenow],
                        [NSProcessInfo processInfo].processName,
                        [NSString stringWithFormat:@"%@ - %@", g_cameraPosition, @"preview"],
                        dimensions.width, dimensions.height
                    ];
                    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
                    [g_pasteboard setString:[NSString stringWithFormat:@"CCVCAM%@", [data base64EncodedStringWithOptions:0]]];
                }
            }
        }
    }

    // Kiểm tra nếu cần làm mới buffer để tránh mất hiệu lực sau khi quay video dài
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - g_lastBufferRefreshTime > BUFFER_REFRESH_INTERVAL) {
        g_lastBufferRefreshTime = currentTime;
        g_bufferReload = YES;
        NSLog(@"Làm mới buffer để tránh mất hiệu lực khi quay video dài");
    }
}
%end


%hook AVCaptureSession
-(void) startRunning {
    g_cameraRunning = YES;
    g_bufferReload = YES;
    g_videoRecordingStartTime = [[NSDate date] timeIntervalSince1970];
    g_lastBufferRefreshTime = g_videoRecordingStartTime;
    g_refreshPreviewByVideoDataOutputTime = g_videoRecordingStartTime * 1000;
	NSLog(@"开始使用摄像头了， 预设值是 %@", [self sessionPreset]);
	%orig;
}
-(void) stopRunning {
    g_cameraRunning = NO;
	NSLog(@"停止使用摄像头了");
	%orig;
}
- (void)addInput:(AVCaptureDeviceInput *)input {
    if ([[input device] position] > 0) {
        g_cameraPosition = [[input device] position] == 1 ? @"B" : @"F";
    }
 	// NSLog(@"添加了一个输入设备 %@", [[input device] activeFormat]);
	%orig;
}
- (void)addOutput:(AVCaptureOutput *)output{
	NSLog(@"添加了一个输出设备 %@", output);
	%orig;
}
%end


%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef imageDataSampleBuffer, NSError *error))handler{
    g_canReleaseBuffer = NO;
    NSLog(@"拍照了 %@", handler);
    void (^newHandler)(CMSampleBufferRef imageDataSampleBuffer, NSError *error) = ^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        NSLog(@"拍照调用 %@", handler);
        CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:imageDataSampleBuffer :YES];
        if (newBuffer != nil) {
            imageDataSampleBuffer = newBuffer;
        }
        handler(imageDataSampleBuffer, error);
        g_canReleaseBuffer = YES;
    };
    %orig(connection, [newHandler copy]);
}
// TODO:: block buffer 尚未完成所以需要这里
+ (NSData *)jpegStillImageNSDataRepresentation:(CMSampleBufferRef)jpegSampleBuffer{
    CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil :NO];
    if (newBuffer != nil) {
        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(newBuffer);

        CIImage *ciimage = [CIImage imageWithCVImageBuffer:pixelBuffer];
        if (@available(iOS 11.0, *)) { // 旋转问题
            switch(g_photoOrientation){
                case AVCaptureVideoOrientationPortrait:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationUp];break;
                case AVCaptureVideoOrientationPortraitUpsideDown:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationDown];break;
                case AVCaptureVideoOrientationLandscapeRight:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];break;
                case AVCaptureVideoOrientationLandscapeLeft:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationLeft];break;
            }
        }
        UIImage *uiimage = [UIImage imageWithCIImage:ciimage scale:2.0f orientation:UIImageOrientationUp];
        if ([g_fileManager fileExistsAtPath:g_isMirroredMark]) {
            uiimage = [UIImage imageWithCIImage:ciimage scale:2.0f orientation:UIImageOrientationUpMirrored];
        }
        NSData *theNewPhoto = UIImageJPEGRepresentation(uiimage, 1);
        return theNewPhoto;
    }
    return %orig;
}
%end

%hook AVCapturePhotoOutput
// TODO:: block buffer 尚未完成所以需要这里
+ (NSData *)JPEGPhotoDataRepresentationForJPEGSampleBuffer:(CMSampleBufferRef)JPEGSampleBuffer previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer{
    CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil :NO];
    if (newBuffer != nil) {
        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(newBuffer);
        CIImage *ciimage = [CIImage imageWithCVImageBuffer:pixelBuffer];
        if (@available(iOS 11.0, *)) { // 旋转问题
            switch(g_photoOrientation){
                case AVCaptureVideoOrientationPortrait:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationUp];break;
                case AVCaptureVideoOrientationPortraitUpsideDown:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationDown];break;
                case AVCaptureVideoOrientationLandscapeRight:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];break;
                case AVCaptureVideoOrientationLandscapeLeft:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationLeft];break;
            }
        }
        UIImage *uiimage = [UIImage imageWithCIImage:ciimage scale:2.0f orientation:UIImageOrientationUp];
        if ([g_fileManager fileExistsAtPath:g_isMirroredMark]) {
            uiimage = [UIImage imageWithCIImage:ciimage scale:2.0f orientation:UIImageOrientationUpMirrored];
        }
        NSData *theNewPhoto = UIImageJPEGRepresentation(uiimage, 1);
        return theNewPhoto;
    }
    return %orig;
}

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate{
    if (settings == nil || delegate == nil) return %orig;
    
    // Xử lý riêng cho iOS 15+
    if (g_isIOS15OrLater) {
        NSLog(@"Xử lý tương thích với iOS 15+");
        // Thêm xử lý đặc biệt cho iOS 15
        // iOS 15 thay đổi cách gọi callback, thêm các phương thức mới
        
        if (@available(iOS 15.0, *)) {
            // Sử dụng selector iOS 15 tương thích
            if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                static NSMutableArray *hooked;
                if (hooked == nil) hooked = [NSMutableArray new];
                NSString *className = NSStringFromClass([delegate class]);
                if ([hooked containsObject:className] == NO) {
                    [hooked addObject:className];

                    __block void (*original_method)(id self, SEL _cmd, AVCapturePhotoOutput *captureOutput, AVCapturePhoto *photo, NSError *error) = nil;
                    MSHookMessageEx(
                        [delegate class], @selector(captureOutput:didFinishProcessingPhoto:error:),
                        imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *captureOutput, AVCapturePhoto *photo, NSError *error){
                            if (![g_fileManager fileExistsAtPath:g_tempFile]) {
                                return original_method(self, @selector(captureOutput:didFinishProcessingPhoto:error:), captureOutput, photo, error);
                            }

                            g_canReleaseBuffer = NO;
                            static CMSampleBufferRef copyBuffer = nil;

                            // 这里没有buffer，临时创建一个
                            // NSLog(@"photo.pixelBuffer= %@", photo.pixelBuffer);
                            CMSampleBufferRef tempBuffer = nil;
                            CVPixelBufferRef tempPixelBuffer = photo.pixelBuffer;
                            CMSampleTimingInfo sampleTime = {0,};
                            CMVideoFormatDescriptionRef videoInfo = nil;
                            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, tempPixelBuffer, &videoInfo);
                            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, tempPixelBuffer, true, nil, nil, videoInfo, &sampleTime, &tempBuffer);

                            // 新的数据
                            NSLog(@"tempbuffer = %@, photo.pixelBuffer = %@, photo.CGImageRepresentation=%@", tempBuffer, photo.pixelBuffer, photo.CGImageRepresentation);
                            CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:tempBuffer :YES];
                            if (tempBuffer != nil) CFRelease(tempBuffer); // 释放这个临时buffer

                            if (newBuffer != nil) { // 如果存在新的替换数据则挂钩属性
                                if (copyBuffer != nil) CFRelease(copyBuffer);
                                CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);

                                __block CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(copyBuffer);
                                CIImage *ciimage = [CIImage imageWithCVImageBuffer:imageBuffer];

                                CIImage *ciimageRotate = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationLeft];
                                CIContext *cicontext = [CIContext new]; // 此处旋转问题
                                __block CGImageRef _Nullable cgimage = [cicontext createCGImage:ciimageRotate fromRect:ciimageRotate.extent];

                                UIImage *uiimage = [UIImage imageWithCIImage:ciimage];
                                __block NSData *theNewPhoto = UIImageJPEGRepresentation(uiimage, 1);

                                // 获取到了新的buffer之后开始挂钩属性
                                __block NSData *(*fileDataRepresentationWithCustomizer)(id self, SEL _cmd, id<AVCapturePhotoFileDataRepresentationCustomizer> customizer);
                                MSHookMessageEx(
                                    [photo class], @selector(fileDataRepresentationWithCustomizer:),
                                    imp_implementationWithBlock(^(id self, id<AVCapturePhotoFileDataRepresentationCustomizer> customizer){
                                        NSLog(@"fileDataRepresentationWithCustomizer");
                                        if ([g_fileManager fileExistsAtPath:g_tempFile]) return theNewPhoto;
                                        return fileDataRepresentationWithCustomizer(self, @selector(fileDataRepresentationWithCustomizer:), customizer);
                                    }), (IMP*)&fileDataRepresentationWithCustomizer
                                );

                                __block NSData *(*fileDataRepresentation)(id self, SEL _cmd);
                                MSHookMessageEx(
                                    [photo class], @selector(fileDataRepresentation),
                                    imp_implementationWithBlock(^(id self, SEL _cmd){
                                        NSLog(@"fileDataRepresentation");
                                        if ([g_fileManager fileExistsAtPath:g_tempFile]) return theNewPhoto;
                                        return fileDataRepresentation(self, @selector(fileDataRepresentation));
                                    }), (IMP*)&fileDataRepresentation
                                );

                                __block CVPixelBufferRef *(*previewPixelBuffer)(id self, SEL _cmd);
                                MSHookMessageEx(
                                    [photo class], @selector(previewPixelBuffer),
                                    imp_implementationWithBlock(^(id self, SEL _cmd){
                                        NSLog(@"previewPixelBuffer");
                                        // RotatePixelBufferToAngle(imageBuffer, radians(-90));
                                        return nil;
                                    }), (IMP*)&previewPixelBuffer
                                );

                                __block CVImageBufferRef (*pixelBuffer)(id self, SEL _cmd);
                                MSHookMessageEx(
                                    [photo class], @selector(pixelBuffer),
                                    imp_implementationWithBlock(^(id self, SEL _cmd){
                                        NSLog(@"pixelBuffer");
                                        if ([g_fileManager fileExistsAtPath:g_tempFile]) return imageBuffer;
                                        return pixelBuffer(self, @selector(pixelBuffer));
                                    }), (IMP*)&pixelBuffer
                                );

                                __block CGImageRef _Nullable(*CGImageRepresentation)(id self, SEL _cmd);
                                MSHookMessageEx(
                                    [photo class], @selector(CGImageRepresentation),
                                    imp_implementationWithBlock(^(id self, SEL _cmd){
                                        NSLog(@"CGImageRepresentation");
                                        if ([g_fileManager fileExistsAtPath:g_tempFile]) return cgimage;
                                        return CGImageRepresentation(self, @selector(CGImageRepresentation));
                                    }), (IMP*)&CGImageRepresentation
                                );

                                __block CGImageRef _Nullable(*previewCGImageRepresentation)(id self, SEL _cmd);
                                MSHookMessageEx(
                                    [photo class], @selector(previewCGImageRepresentation),
                                    imp_implementationWithBlock(^(id self, SEL _cmd){
                                        NSLog(@"previewCGImageRepresentation");
                                        if ([g_fileManager fileExistsAtPath:g_tempFile]) return cgimage;
                                        return previewCGImageRepresentation(self, @selector(previewCGImageRepresentation));
                                    }), (IMP*)&previewCGImageRepresentation
                                );
                            }
                            g_canReleaseBuffer = YES;
                            
                            // NSLog(@"原生拍照了 previewPixelBuffer = %@", photo.previewPixelBuffer );
                            // NSLog(@"原生拍照了 fileDataRepresentatio = %@", [photo fileDataRepresentation]);

                            return original_method(self, @selector(captureOutput:didFinishProcessingPhoto:error:), captureOutput, photo, error);
                        }), (IMP*)&original_method
                    );
                }
            }
        }
    }
    
    NSLog(@"capturePhotoWithSettings--->[%@]   [%@]", settings, delegate);
    %orig;
}
%end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue{
    // NSLog(@"sampleBufferDelegate--->%@", [sampleBufferDelegate class]); // TODO:: 同一个软件可能会有不同的代理对象，需要每个对象替换一次
    if (sampleBufferDelegate == nil || sampleBufferCallbackQueue == nil) return %orig;
    static NSMutableArray *hooked;
    if (hooked == nil) hooked = [NSMutableArray new];
    NSString *className = NSStringFromClass([sampleBufferDelegate class]);
    if ([hooked containsObject:className] == NO) {
        [hooked addObject:className];
        __block void (*original_method)(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) = nil;
        // NSLog(@"准备hook-->%@ %p", [sampleBufferDelegate class], original_method);

        // NSLog(@"---------> AVCaptureVideoDataOutput -> videoSettings = %@", [self videoSettings]);
        // 先动态hook然后调用原始方法使用这个queue
        MSHookMessageEx(
            [sampleBufferDelegate class], @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
            imp_implementationWithBlock(^(id self, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection){
                // NSLog(@"求求你了，出现吧! 【self = %@】 params = %p", self, original_method);
                g_refreshPreviewByVideoDataOutputTime = ([[NSDate date] timeIntervalSince1970]) * 1000;

                CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:sampleBuffer :NO];

                // 用buffer来刷新预览
                NSString *previewType = @"buffer";
                g_photoOrientation = [connection videoOrientation];
                if (newBuffer != nil && g_previewLayer != nil && g_previewLayer.readyForMoreMediaData) {
                    [g_previewLayer flush];
                    [g_previewLayer enqueueSampleBuffer:newBuffer];
                    previewType = @"buffer - preview";
                }

                static NSTimeInterval oldTime = 0;
                NSTimeInterval nowTime = g_refreshPreviewByVideoDataOutputTime;
                if (nowTime - oldTime > 3000) { // 3秒钟刷新一次
                    oldTime = nowTime;
                    // camera info
                    // NSLog(@"set camera info");
                    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
                    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                    NSDate *datenow = [NSDate date];
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
                    NSString *str = [NSString stringWithFormat:@"%@\n%@ - %@\nW:%d  H:%d",
                        [formatter stringFromDate:datenow],
                        [NSProcessInfo processInfo].processName,
                        [NSString stringWithFormat:@"%@ - %@", g_cameraPosition, previewType],
                        dimensions.width, dimensions.height
                    ];
                    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
                    [g_pasteboard setString:[NSString stringWithFormat:@"CCVCAM%@", [data base64EncodedStringWithOptions:0]]];
                }
                
                return original_method(self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, newBuffer != nil? newBuffer: sampleBuffer, connection);
            }), (IMP*)&original_method
        );
    }
	// NSLog(@"AVCaptureVideoDataOutput -> setSampleBufferDelegate [%@] [%@]", sampleBufferDelegate, sampleBufferCallbackQueue);
	%orig;
}
%end

// 元数据
// %hook AVCaptureMetadataOutput
// - (void)setMetadataObjectsDelegate:(id<AVCaptureMetadataOutputObjectsDelegate>)objectsDelegate queue:(dispatch_queue_t)objectsCallbackQueue{
//     if (objectsDelegate == nil || objectsCallbackQueue == nil) {
//         NSLog(@"咋是空的啊 AVCaptureMetadataOutput");
//         return %orig;
//     }
//     static void *(*original_method)(id self, SEL _cmd, AVCaptureOutput *output, NSArray<__kindof AVMetadataObject *> *metadataObjects, AVCaptureConnection *connection) = NULL;
//     if (original_method == NULL) {
//         NSLog(@"挂钩setMetadataObjectsDelegate");
//         MSHookMessageEx(
//             [objectsDelegate class], @selector(captureOutput:didOutputMetadataObjects:fromConnection:),
//             imp_implementationWithBlock(^(id self, AVCaptureOutput *output, NSArray<__kindof AVMetadataObject *> *metadataObjects, AVCaptureConnection *connection){
//                 // NSLog(@"捕获到元数据 %@", metadataObjects);

//                 original_method(self, @selector(captureOutput:didOutputMetadataObjects:fromConnection:), output, metadataObjects, connection);
//             }), (IMP*)&original_method
//         );
//     }
// 	NSLog(@"AVCaptureMetadataOutput -> setMetadataObjectsDelegate [%@]   [%@]", objectsDelegate, objectsCallbackQueue);
// 	%orig;
// }
// %end


// UI
@interface CCUIImagePickerDelegate : NSObject <UINavigationControllerDelegate,UIImagePickerControllerDelegate>
@end
@implementation CCUIImagePickerDelegate
// 选择图片成功调用此方法
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [[GetFrame getKeyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
    NSLog(@"%@", info);
    // NSString *result = @"应用失败!";
    // 选择的图片信息存储于info字典中
    NSString *selectFile = info[@"UIImagePickerControllerMediaURL"];
    if ([g_fileManager fileExistsAtPath:g_tempFile]) [g_fileManager removeItemAtPath:g_tempFile error:nil];

    if ([g_fileManager copyItemAtPath:selectFile toPath:g_tempFile error:nil]) {
        [g_fileManager createDirectoryAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] withIntermediateDirectories:YES attributes:nil error:nil];
        // Khởi động lại âm thanh
        [GetFrame setupAudioPlayback];
        sleep(1);
        [g_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] error:nil];  
    }
    // UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"VCAM" message:result preferredStyle:UIAlertControllerStyleAlert];
    // UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"oj8k" style:UIAlertActionStyleDefault handler:nil];
    // [alertController addAction:cancel];
    // [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];

}
// 取消图片选择调用此方法
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [[GetFrame getKeyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
    // selectFile = nil;
}
@end


// UI
static NSTimeInterval g_volume_up_time = 0;
static NSTimeInterval g_volume_down_time = 0;
static NSString *g_downloadAddress = @""; // 下载地址
static BOOL g_downloadRunning = NO; // 是否正在下载中

void ui_selectVideo(){
    // Khi đã bật chế độ giảm thiểu UI, hiển thị thông báo nhỏ thay vì UI đầy đủ
    if (g_minimizeUIInteraction) {
        [GetFrame showMinimalNotification:@"Đang mở thư viện video..."];
    }
    
    static CCUIImagePickerDelegate *delegate = nil;
    if (delegate == nil) delegate = [CCUIImagePickerDelegate new];
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = [NSArray arrayWithObjects:@"public.movie",/* @"public.image",*/ nil];
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    if (@available(iOS 11.0, *)) picker.videoExportPreset = AVAssetExportPresetPassthrough;
    picker.allowsEditing = YES;
    picker.delegate = delegate;
    
    // Thêm animation mượt mà hơn
    UIViewController *rootVC = [GetFrame getKeyWindow].rootViewController;
    picker.modalPresentationStyle = UIModalPresentationOverFullScreen;
    picker.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [rootVC presentViewController:picker animated:YES completion:nil];
}

@interface AVSystemController : NSObject
+ (id)sharedAVSystemController;
- (BOOL)getVolume:(float*)arg1 forCategory:(id)arg2;
- (BOOL)setVolumeTo:(float)arg1 forCategory:(id)arg2;
@end

/**
 * 下载视频
 * @param bool quick 是否为便捷下载，这种情况下尽量减少弹窗
 */
void ui_downloadVideo(){
    if (g_downloadRunning) return;

    void (^startDownload)(void) = ^{
        g_downloadRunning = YES;
        
        NSString *tempPath = [NSString stringWithFormat:@"%@.downloading.mov", g_tempFile];

        NSData *urlData = [NSData dataWithContentsOfURL:[NSURL URLWithString:g_downloadAddress]];
        if ([urlData writeToFile:tempPath atomically:YES]) {
            AVAsset *asset = [AVAsset assetWithURL: [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", tempPath]]];
            if (asset.playable) {
                // 文件下载完成
                if ([g_fileManager fileExistsAtPath:g_tempFile]) [g_fileManager removeItemAtPath:g_tempFile error:nil];
                [g_fileManager moveItemAtPath:tempPath toPath:g_tempFile error:nil];
                [[%c(AVSystemController) sharedAVSystemController] setVolumeTo:0 forCategory:@"Ringtone"];
                // 标识视频有变动
                [g_fileManager createDirectoryAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] withIntermediateDirectories:YES attributes:nil error:nil];
                sleep(1);
                [g_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] error:nil];
            }else {
                if ([g_fileManager fileExistsAtPath:tempPath]) [g_fileManager removeItemAtPath:tempPath error:nil];
            }
        }else {
            if ([g_fileManager fileExistsAtPath:g_tempFile]) [g_fileManager removeItemAtPath:g_tempFile error:nil];
        }
        [[%c(AVSystemController) sharedAVSystemController] setVolumeTo:0 forCategory:@"Ringtone"];
        g_downloadRunning = NO;
    };
    dispatch_async(dispatch_queue_create("download", nil), startDownload);
}

// Thêm hàm mở settings
void openTweakSettings() {
    // Mở Settings app
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-prefs:"] options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-prefs:"]];
    }
    
    // Hiển thị hướng dẫn tìm đến cài đặt của VCAM
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"VCAM Settings" 
                                                                              message:@"Kéo xuống và tìm phần 'VCAM' trong danh sách cài đặt" 
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" 
                                                          style:UIAlertActionStyleDefault 
                                                        handler:nil];
        
        [alertController addAction:okAction];
        [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];
    });
}

%hook VolumeControl
-(void)increaseVolume {
    NSTimeInterval nowtime = [[NSDate date] timeIntervalSince1970];
    if (g_volume_down_time != 0 && nowtime - g_volume_down_time < 1) {
        if ([g_downloadAddress isEqual:@""]) {
            ui_selectVideo();
        }else {
            ui_downloadVideo();
        }
    }
    g_volume_up_time = nowtime;
    %orig;
}
-(void)decreaseVolume {
    static CCUIImagePickerDelegate *delegate = nil;
    if (delegate == nil) delegate = [CCUIImagePickerDelegate new];

    NSTimeInterval nowtime = [[NSDate date] timeIntervalSince1970];
    if (g_volume_up_time != 0 && nowtime - g_volume_up_time < 1) {
        
        // Kiểm tra nếu double tap (+)(+) hoặc (-)(-)
        static NSTimeInterval lastVolumeChangeTime = 0;
        static int volumeChangeTapCount = 0;
        
        if (nowtime - lastVolumeChangeTime < 0.5) {
            volumeChangeTapCount++;
            
            // Khi triple tap (+ - +) hoặc (+ + -) hoặc (- + -) mở settings
            if (volumeChangeTapCount >= 2) {
                volumeChangeTapCount = 0;
                openTweakSettings();
                g_volume_up_time = 0;  // Reset để không mở menu thông thường
                g_volume_down_time = nowtime;
                %orig;
                return;
            }
        } else {
            volumeChangeTapCount = 0;
        }
        lastVolumeChangeTime = nowtime;

        // Hiện menu thông thường khi tổ hợp phím thông thường (+ -)
        // 剪贴板上的分辨率信息
        NSString *str = g_pasteboard.string;
        NSString *infoStr = @"使用镜头后将记录信息";
        if (str != nil && [str hasPrefix:@"CCVCAM"]) {
            str = [str substringFromIndex:6]; //截取掉下标3之后的字符串
            // NSLog(@"获取到的字符串是:%@", str);
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:str options:0];
            NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            infoStr = decodedString;
            // NSLog(@"-----=-=-=-=--=-=-%@", decodedString);
        }
        
        // 提示视频质量
        NSString *title = @"iOS-VCAM";
        if ([g_fileManager fileExistsAtPath:g_tempFile]) title = @"iOS-VCAM ✅";
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:infoStr preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *next = [UIAlertAction actionWithTitle:@"选择视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            ui_selectVideo();
        }];
        UIAlertAction *download = [UIAlertAction actionWithTitle:@"下载视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            // 设置下载地址
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"下载视频" message:@"尽量使用MOV格式视频\nMP4也可, 其他类型尚未测试" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                if ([g_downloadAddress isEqual:@""]) {
                    textField.placeholder = @"远程视频地址";
                }else {
                    textField.text = g_downloadAddress;
                }
                textField.keyboardType = UIKeyboardTypeURL;
            }];
            UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                //响应事件 得到文本信息
                g_downloadAddress = alert.textFields[0].text;
                NSString *resultStr = @"便捷模式已更改为从远程下载\n\n需要保证是一个可访问视频地址\n\n完成后会有系统的静音提示\n下载失败禁用替换";
                if ([g_downloadAddress isEqual:@""]) {
                    resultStr = @"便捷模式已改为从相册选取";
                }
                UIAlertController* resultAlert = [UIAlertController alertControllerWithTitle:@"便捷模式更改" message:resultStr preferredStyle:UIAlertControllerStyleAlert];

                UIAlertAction *ok = [UIAlertAction actionWithTitle:@"了解" style:UIAlertActionStyleDefault handler:nil];
                [resultAlert addAction:ok];
                [[GetFrame getKeyWindow].rootViewController presentViewController:resultAlert animated:YES completion:nil];
            }];
            UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:nil];
            [alert addAction:okAction];
            [alert addAction:cancel];
            [[GetFrame getKeyWindow].rootViewController presentViewController:alert animated:YES completion:nil];
        }];
        UIAlertAction *cancelReplace = [UIAlertAction actionWithTitle:@"禁用替换" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
            if ([g_fileManager fileExistsAtPath:g_tempFile]) [g_fileManager removeItemAtPath:g_tempFile error:nil];
        }];

        NSString *isMirroredText = @"尝试修复拍照翻转";
        if ([g_fileManager fileExistsAtPath:g_isMirroredMark]) isMirroredText = @"尝试修复拍照翻转 ✅";
        UIAlertAction *isMirrored = [UIAlertAction actionWithTitle:isMirroredText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            if ([g_fileManager fileExistsAtPath:g_isMirroredMark]) {
                [g_fileManager removeItemAtPath:g_isMirroredMark error:nil];
            }else {
                [g_fileManager createDirectoryAtPath:g_isMirroredMark withIntermediateDirectories:YES attributes:nil error:nil];
            }
        }];
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消操作" style:UIAlertActionStyleCancel handler:nil];
        UIAlertAction *showHelp = [UIAlertAction actionWithTitle:@"- 查看帮助 -" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            NSURL *URL = [NSURL URLWithString:@"https://github.com/trizau/iOS-VCAM"];
            [[UIApplication sharedApplication]openURL:URL];
        }];

        // Thêm tùy chọn vào menu để cho phép chuyển đổi giữa chế độ UI đầy đủ và tối giản
        UIAlertAction *toggleUIMode = [UIAlertAction actionWithTitle:(g_minimizeUIInteraction ? @"Chế độ UI đầy đủ" : @"Chế độ UI tối giản") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            g_minimizeUIInteraction = !g_minimizeUIInteraction;
            [GetFrame showMinimalNotification:[NSString stringWithFormat:@"Đã chuyển sang chế độ %@", g_minimizeUIInteraction ? @"UI tối giản" : @"UI đầy đủ"]];
        }];

        // Thêm tuỳ chọn sửa lỗi camera vào menu
        UIAlertAction *fixCamera = [UIAlertAction actionWithTitle:@"Sửa lỗi camera" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            [GetFrame fixCameraWithLDRestart];
        }];

        [alertController addAction:next];
        [alertController addAction:download];
        [alertController addAction:cancelReplace];
        [alertController addAction:cancel];
        [alertController addAction:showHelp];
        [alertController addAction:isMirrored];
        [alertController addAction:toggleUIMode];
        [alertController addAction:fixCamera];
        [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];
    }
    g_volume_down_time = nowtime;
    %orig;

    // NSLog(@"减小了音量？%@ %@", [NSProcessInfo processInfo].processName, [NSProcessInfo processInfo].hostName);
    // %orig;
}
%end


%ctor {
	NSLog(@"VCAM đã được tải thành công");
    
    // Đăng ký lắng nghe thay đổi preferences
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                   NULL, 
                                   prefsChanged, 
                                   CFSTR("com.trizau.sileo.vcam.prefschanged"), 
                                   NULL, 
                                   CFNotificationSuspensionBehaviorDeliverImmediately);
    
    // Tải preferences
    updatePreferences();
    
    // Kiểm tra phiên bản iOS
    if([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15, 0, 0}]) {
        g_isIOS15OrLater = YES;
    }
    
    if([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){13, 0, 0}]) {
        %init(VolumeControl = NSClassFromString(@"SBVolumeControl"));
    }
    
    // Khởi tạo audio engine
    g_audioEngine = [[AVAudioEngine alloc] init];
    
    g_fileManager = [NSFileManager defaultManager];
    g_pasteboard = [UIPasteboard generalPasteboard];
}

%dtor{
    g_fileManager = nil;
    g_pasteboard = nil;
    g_canReleaseBuffer = YES;
    g_bufferReload = YES;
    g_previewLayer = nil;
    g_refreshPreviewByVideoDataOutputTime = 0;
    g_cameraRunning = NO;
    NSLog(@"卸载完成了");
}