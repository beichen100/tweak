#include <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

static NSFileManager *g_fileManager = nil;
static UIPasteboard *g_pasteboard = nil;
static BOOL g_canReleaseBuffer = YES;
static BOOL g_bufferReload = YES;
static AVSampleBufferDisplayLayer *g_previewLayer = nil;
static NSTimeInterval g_refreshPreviewByVideoDataOutputTime = 0;
static BOOL g_cameraRunning = NO;
static NSString *g_cameraPosition = @"B";
static AVCaptureVideoOrientation g_photoOrientation = AVCaptureVideoOrientationPortrait;

NSString *g_isMirroredMark = @"/var/mobile/Library/Caches/vcam_is_mirrored_mark";
NSString *g_tempFile = @"/var/mobile/Library/Caches/temp.mov";

static AVAssetReader *reader = nil;
static AVAssetReaderTrackOutput *videoTrackout_32BGRA = nil;
static AVAssetReaderTrackOutput *videoTrackout_420YpCbCr8BiPlanarVideoRange = nil;
static AVAssetReaderTrackOutput *videoTrackout_420YpCbCr8BiPlanarFullRange = nil;

@interface GetFrame : NSObject
+ (CMSampleBufferRef _Nullable)getCurrentFrame:(CMSampleBufferRef)originSampleBuffer :(BOOL)forceReNew;
+ (UIWindow*)getKeyWindow;
@end

@implementation GetFrame
+ (CMSampleBufferRef _Nullable)getCurrentFrame:(CMSampleBufferRef _Nullable)originSampleBuffer :(BOOL)forceReNew {
    static CMSampleBufferRef sampleBuffer = nil;

    CMFormatDescriptionRef formatDescription = nil;
    CMMediaType mediaType = -1;
    CMMediaType subMediaType = -1;
    
    if (originSampleBuffer != nil) {
        formatDescription = CMSampleBufferGetFormatDescription(originSampleBuffer);
        mediaType = CMFormatDescriptionGetMediaType(formatDescription);
        subMediaType = CMFormatDescriptionGetMediaSubType(formatDescription);
        
        if (mediaType != kCMMediaType_Video) {
            return originSampleBuffer;
        }
    }

    if ([g_fileManager fileExistsAtPath:g_tempFile] == NO) return nil;
    if (sampleBuffer != nil && !g_canReleaseBuffer && CMSampleBufferIsValid(sampleBuffer) && forceReNew != YES) {
        return sampleBuffer;
    }

    static NSTimeInterval renewTime = 0;
    if ([g_fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile]]) {
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970];
        if (nowTime - renewTime > 3) {
            renewTime = nowTime;
            g_bufferReload = YES;
        }
    }

    if (g_bufferReload) {
        g_bufferReload = NO;
        @try {
            AVAsset *asset = [AVAsset assetWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"file://%@", g_tempFile]]];
            reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            
            AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
            
            videoTrackout_32BGRA = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
            videoTrackout_420YpCbCr8BiPlanarVideoRange = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
            videoTrackout_420YpCbCr8BiPlanarFullRange = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];
            
            [reader addOutput:videoTrackout_32BGRA];
            [reader addOutput:videoTrackout_420YpCbCr8BiPlanarVideoRange];
            [reader addOutput:videoTrackout_420YpCbCr8BiPlanarFullRange];

            [reader startReading];
        } @catch(NSException *except) {
            NSLog(@"[VCAM] 初始化读取视频出错:%@", except);
        }
    }

    CMSampleBufferRef videoTrackout_32BGRA_Buffer = [videoTrackout_32BGRA copyNextSampleBuffer];
    CMSampleBufferRef videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer = [videoTrackout_420YpCbCr8BiPlanarVideoRange copyNextSampleBuffer];
    CMSampleBufferRef videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer = [videoTrackout_420YpCbCr8BiPlanarFullRange copyNextSampleBuffer];

    CMSampleBufferRef newsampleBuffer = nil;
    
    switch(subMediaType) {
        case kCVPixelFormatType_32BGRA:
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_32BGRA_Buffer, &newsampleBuffer);
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer, &newsampleBuffer);
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer, &newsampleBuffer);
            break;
        default:
            CMSampleBufferCreateCopy(kCFAllocatorDefault, videoTrackout_32BGRA_Buffer, &newsampleBuffer);
    }
    
    if (videoTrackout_32BGRA_Buffer != nil) CFRelease(videoTrackout_32BGRA_Buffer);
    if (videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer != nil) CFRelease(videoTrackout_420YpCbCr8BiPlanarVideoRange_Buffer);
    if (videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer != nil) CFRelease(videoTrackout_420YpCbCr8BiPlanarFullRange_Buffer);

    if (newsampleBuffer == nil) {
        g_bufferReload = YES;
    } else {
        if (sampleBuffer != nil) CFRelease(sampleBuffer);
        
        if (originSampleBuffer != nil) {
            CMSampleBufferRef copyBuffer = nil;
            CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(newsampleBuffer);

            CMSampleTimingInfo sampleTime = {
                .duration = CMSampleBufferGetDuration(originSampleBuffer),
                .presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(originSampleBuffer),
                .decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(originSampleBuffer)
            };

            CMVideoFormatDescriptionRef videoInfo = nil;
            CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &videoInfo);
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, videoInfo, &sampleTime, &copyBuffer);

            if (copyBuffer != nil) {
                CFDictionaryRef exifAttachments = CMGetAttachment(originSampleBuffer, (CFStringRef)@"{Exif}", NULL);
                CFDictionaryRef TIFFAttachments = CMGetAttachment(originSampleBuffer, (CFStringRef)@"{TIFF}", NULL);

                if (exifAttachments != nil) CMSetAttachment(copyBuffer, (CFStringRef)@"{Exif}", exifAttachments, kCMAttachmentMode_ShouldPropagate);
                if (TIFFAttachments != nil) CMSetAttachment(copyBuffer, (CFStringRef)@"{TIFF}", TIFFAttachments, kCMAttachmentMode_ShouldPropagate);
                
                sampleBuffer = copyBuffer;
            }
            CFRelease(newsampleBuffer);
        } else {
            sampleBuffer = newsampleBuffer;
        }
    }
    
    if (CMSampleBufferIsValid(sampleBuffer)) return sampleBuffer;
    return nil;
}

+ (UIWindow*)getKeyWindow {
    UIWindow *keyWindow = nil;
    NSArray *windows = UIApplication.sharedApplication.windows;
    for(UIWindow *window in windows) {
        if(window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}
@end

CALayer *g_maskLayer = nil;

%hook AVCaptureVideoPreviewLayer
- (void)addSublayer:(CALayer *)layer {
    %orig;

    static CADisplayLink *displayLink = nil;
    if (displayLink == nil) {
        displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }

    if (![[self sublayers] containsObject:g_previewLayer]) {
        g_previewLayer = [[AVSampleBufferDisplayLayer alloc] init];

        g_maskLayer = [CALayer new];
        g_maskLayer.backgroundColor = [UIColor blackColor].CGColor;
        [self insertSublayer:g_maskLayer above:layer];
        [self insertSublayer:g_previewLayer above:g_maskLayer];

        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = [GetFrame getKeyWindow];
            if (keyWindow) {
                g_previewLayer.frame = keyWindow.bounds;
                g_maskLayer.frame = keyWindow.bounds;
            }
        });
    }
}

%new
- (void)step:(CADisplayLink *)sender {
    if ([g_fileManager fileExistsAtPath:g_tempFile]) {
        if (g_maskLayer != nil) g_maskLayer.opacity = 1;
        if (g_previewLayer != nil) {
            g_previewLayer.opacity = 1;
            [g_previewLayer setVideoGravity:[self videoGravity]];
        }
    } else {
        if (g_maskLayer != nil) g_maskLayer.opacity = 0;
        if (g_previewLayer != nil) g_previewLayer.opacity = 0;
    }

    if (g_cameraRunning && g_previewLayer != nil) {
        g_previewLayer.frame = self.bounds;

        switch(g_photoOrientation) {
            case AVCaptureVideoOrientationPortrait:
            case AVCaptureVideoOrientationPortraitUpsideDown:
                g_previewLayer.transform = CATransform3DMakeRotation(0 / 180.0 * M_PI, 0.0, 0.0, 1.0);
                break;
            case AVCaptureVideoOrientationLandscapeRight:
                g_previewLayer.transform = CATransform3DMakeRotation(90 / 180.0 * M_PI, 0.0, 0.0, 1.0);
                break;
            case AVCaptureVideoOrientationLandscapeLeft:
                g_previewLayer.transform = CATransform3DMakeRotation(-90 / 180.0 * M_PI, 0.0, 0.0, 1.0);
                break;
            default:
                g_previewLayer.transform = self.transform;
        }

        static NSTimeInterval refreshTime = 0;
        NSTimeInterval nowTime = [[NSDate date] timeIntervalSince1970] * 1000;
        
        if (nowTime - g_refreshPreviewByVideoDataOutputTime > 1000) {
            static CMSampleBufferRef copyBuffer = nil;
            if (nowTime - refreshTime > 1000 / 33 && g_previewLayer.readyForMoreMediaData) {
                refreshTime = nowTime;
                g_photoOrientation = -1;
                
                CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil :NO];
                if (newBuffer != nil) {
                    [g_previewLayer flush];
                    if (copyBuffer != nil) CFRelease(copyBuffer);
                    CMSampleBufferCreateCopy(kCFAllocatorDefault, newBuffer, &copyBuffer);
                    if (copyBuffer != nil) [g_previewLayer enqueueSampleBuffer:copyBuffer];

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
}
%end

%hook AVCaptureSession
- (void)startRunning {
    g_cameraRunning = YES;
    g_bufferReload = YES;
    g_refreshPreviewByVideoDataOutputTime = [[NSDate date] timeIntervalSince1970] * 1000;
    NSLog(@"[VCAM] 开始使用摄像头，预设值是 %@", [self sessionPreset]);
    %orig;
}

- (void)stopRunning {
    g_cameraRunning = NO;
    NSLog(@"[VCAM] 停止使用摄像头");
    %orig;
}

- (void)addInput:(AVCaptureDeviceInput *)input {
    if ([[input device] position] > 0) {
        g_cameraPosition = [[input device] position] == 1 ? @"B" : @"F";
    }
    %orig;
}

- (void)addOutput:(AVCaptureOutput *)output {
    NSLog(@"[VCAM] 添加了一个输出设备");
    %orig;
}
%end

%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef imageDataSampleBuffer, NSError *error))handler {
    g_canReleaseBuffer = NO;
    NSLog(@"[VCAM] 拍照了");
    void (^newHandler)(CMSampleBufferRef imageDataSampleBuffer, NSError *error) = ^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:imageDataSampleBuffer :YES];
        if (newBuffer != nil) {
            imageDataSampleBuffer = newBuffer;
        }
        handler(imageDataSampleBuffer, error);
        g_canReleaseBuffer = YES;
    };
    %orig(connection, [newHandler copy]);
}

+ (NSData *)jpegStillImageNSDataRepresentation:(CMSampleBufferRef)jpegSampleBuffer {
    CMSampleBufferRef newBuffer = [GetFrame getCurrentFrame:nil :NO];
    if (newBuffer != nil) {
        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(newBuffer);
        CIImage *ciimage = [CIImage imageWithCVImageBuffer:pixelBuffer];
        
        if (@available(iOS 11.0, *)) {
            switch(g_photoOrientation) {
                case AVCaptureVideoOrientationPortrait:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationUp];
                    break;
                case AVCaptureVideoOrientationPortraitUpsideDown:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationDown];
                    break;
                case AVCaptureVideoOrientationLandscapeRight:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];
                    break;
                case AVCaptureVideoOrientationLandscapeLeft:
                    ciimage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationLeft];
                    break;
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

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
    %orig;
    NSLog(@"[VCAM] 设置了 VideoDataOutput 的代理");
}
%end

@interface CCUIImagePickerDelegate : NSObject <UINavigationControllerDelegate,UIImagePickerControllerDelegate>
@end

@implementation CCUIImagePickerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [[GetFrame getKeyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
    
    NSString *selectFile = [info[@"UIImagePickerControllerMediaURL"] path];
    if ([g_fileManager fileExistsAtPath:g_tempFile]) {
        [g_fileManager removeItemAtPath:g_tempFile error:nil];
    }

    if ([g_fileManager copyItemAtPath:selectFile toPath:g_tempFile error:nil]) {
        [g_fileManager createDirectoryAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] withIntermediateDirectories:YES attributes:nil error:nil];
        sleep(1);
        [g_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.new", g_tempFile] error:nil];
        
        NSLog(@"[VCAM] 已选择视频: %@", selectFile);
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [[GetFrame getKeyWindow].rootViewController dismissViewControllerAnimated:YES completion:nil];
}
@end

void ui_selectVideo() {
    static CCUIImagePickerDelegate *delegate = nil;
    if (delegate == nil) delegate = [CCUIImagePickerDelegate new];
    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    if (@available(iOS 11.0, *)) {
        picker.videoExportPreset = AVAssetExportPresetPassthrough;
    }
    picker.allowsEditing = YES;
    picker.delegate = delegate;
    
    UIViewController *rootVC = [GetFrame getKeyWindow].rootViewController;
    picker.modalPresentationStyle = UIModalPresentationOverFullScreen;
    picker.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [rootVC presentViewController:picker animated:YES completion:nil];
}

static NSTimeInterval g_volume_up_time = 0;
static NSTimeInterval g_volume_down_time = 0;

%hook SBVolumeControl
- (void)increaseVolume {
    NSTimeInterval nowtime = [[NSDate date] timeIntervalSince1970];
    NSLog(@"[VCAM] Volume Up pressed");
    
    // 写入日志文件测试
    NSString *log = [NSString stringWithFormat:@"Volume UP at %f\n", nowtime];
    [log writeToFile:@"/var/mobile/Library/Logs/vcam_volume.log" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    
    if (g_volume_down_time != 0 && nowtime - g_volume_down_time < 1) {
        NSLog(@"[VCAM] 触发选择视频");
        ui_selectVideo();
    }
    g_volume_up_time = nowtime;
    %orig;
}

- (void)decreaseVolume {
    NSTimeInterval nowtime = [[NSDate date] timeIntervalSince1970];
    NSLog(@"[VCAM] Volume Down pressed");
    
    // 写入日志文件测试
    NSString *log = [NSString stringWithFormat:@"Volume DOWN at %f\n", nowtime];
    [log writeToFile:@"/var/mobile/Library/Logs/vcam_volume.log" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    
    if (g_volume_up_time != 0 && nowtime - g_volume_up_time < 1) {
        NSLog(@"[VCAM] 触发菜单");
        
        NSString *str = g_pasteboard.string;
        NSString *infoStr = @"使用相机后将记录信息";
        if (str != nil && [str hasPrefix:@"CCVCAM"]) {
            str = [str substringFromIndex:6];
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:str options:0];
            NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
            infoStr = decodedString;
        }
        
        NSString *title = @"VCAM - 虚拟摄像头";
        if ([g_fileManager fileExistsAtPath:g_tempFile]) {
            title = @"VCAM ✅ - 虚拟摄像头";
        }
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title 
                                                                                  message:infoStr 
                                                                           preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *selectVideo = [UIAlertAction actionWithTitle:@"📹 选择视频" 
                                                             style:UIAlertActionStyleDefault 
                                                           handler:^(UIAlertAction *action) {
            ui_selectVideo();
        }];
        
        UIAlertAction *disableReplace = [UIAlertAction actionWithTitle:@"❌ 禁用替换" 
                                                                style:UIAlertActionStyleDestructive 
                                                              handler:^(UIAlertAction *action) {
            if ([g_fileManager fileExistsAtPath:g_tempFile]) {
                [g_fileManager removeItemAtPath:g_tempFile error:nil];
                NSLog(@"[VCAM] 已禁用视频替换");
            }
        }];
        
        NSString *mirrorText = @"🔄 修复拍照翻转";
        if ([g_fileManager fileExistsAtPath:g_isMirroredMark]) {
            mirrorText = @"🔄 修复拍照翻转 ✅";
        }
        UIAlertAction *toggleMirror = [UIAlertAction actionWithTitle:mirrorText 
                                                              style:UIAlertActionStyleDefault 
                                                            handler:^(UIAlertAction *action) {
            if ([g_fileManager fileExistsAtPath:g_isMirroredMark]) {
                [g_fileManager removeItemAtPath:g_isMirroredMark error:nil];
            } else {
                [g_fileManager createDirectoryAtPath:g_isMirroredMark withIntermediateDirectories:YES attributes:nil error:nil];
            }
        }];
        
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" 
                                                        style:UIAlertActionStyleCancel 
                                                      handler:nil];

        [alertController addAction:selectVideo];
        [alertController addAction:disableReplace];
        [alertController addAction:toggleMirror];
        [alertController addAction:cancel];
        
        [[GetFrame getKeyWindow].rootViewController presentViewController:alertController animated:YES completion:nil];
    }
    g_volume_down_time = nowtime;
    %orig;
}
%end

%ctor {
    // 写入测试文件证明tweak已加载
    NSString *testLog = @"[VCAM] Tweak loaded successfully\n";
    [testLog writeToFile:@"/var/mobile/Library/Logs/vcam_loaded.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSLog(@"===============================================");
    NSLog(@"[VCAM] Virtual Camera Tweak Loaded");
    NSLog(@"[VCAM] iOS Version: %@", [[UIDevice currentDevice] systemVersion]);
    NSLog(@"[VCAM] Target: SpringBoard & Camera");
    NSLog(@"===============================================");
    
    g_fileManager = [NSFileManager defaultManager];
    g_pasteboard = [UIPasteboard generalPasteboard];
    
    NSLog(@"[VCAM] 初始化完成");
    NSLog(@"[VCAM] 使用方法：");
    NSLog(@"[VCAM]   - 音量+ 然后 音量- : 选择视频");
    NSLog(@"[VCAM]   - 音量- 然后 音量+ : 打开菜单");
}
